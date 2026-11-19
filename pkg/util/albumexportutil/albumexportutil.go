// Package albumexportutil exports photo albums, or the whole photo library, as
// plain copied files and a manifest (#3501). An album in Quark is a list of
// pointers to photos that stay in their folders; an export resolves those
// pointers once, into real files that open anywhere, and changes nothing in
// Quark: the originals, their folders and the album pointers are only read.
//
// The copy rule: every album becomes a folder, a sub-album a folder inside it,
// and a photo is copied into the folder of every exported album that holds
// it. manifest.csv, at the top of the export, has one row per copied file
// naming the original's drive and path, its capture date, and every album of
// the account that holds it. An export of the library also copies the photos
// in no album, under [NotInAlbumFolder] in their original folders.
//
// The export runs as a [jobutil] job of [Kind] with the access of the account
// that queued it. A photo it cannot read is left out, as the album view
// leaves it out; one it cannot copy is a row of the manifest saying why, and
// the job fails with a [PartialError] rather than completing.
package albumexportutil

import (
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// Kind is the jobutil kind an export runs under. One export runs at a time.
const Kind = "photo-export"

// ManifestName is the manifest's file name, at the top of the export folder.
const ManifestName = "manifest.csv"

// NotInAlbumFolder holds, in a library export, the photos in no album.
const NotInAlbumFolder = "Not in an album"

// The reasons a manifest row gives for a file it could not copy.
const (
	// ReasonMissing is an original that is no longer there.
	ReasonMissing = "missing"
	// ReasonNotCopied is any other failure to copy, such as a full drive.
	ReasonNotCopied = "not copied"
)

// The failures a caller of [StartExport] can fix.
var (
	// ErrNothingToExport reports a request naming no album and not the
	// library.
	ErrNothingToExport = errors.New("choose at least one album, or the whole library")
	// ErrAlbumNotFound reports an album that does not exist or is another
	// account's.
	ErrAlbumNotFound = errors.New("album not found")
	// ErrFolderNotFound reports a destination that is not a folder.
	ErrFolderNotFound = errors.New("the folder to export into does not exist")
	// ErrDestinationForbidden reports a destination the account cannot add
	// files to.
	ErrDestinationForbidden = errors.New("you can't add files to that folder")
)

// PartialError is an export that copied some files but not all of them. The
// manifest names each one it could not copy.
type PartialError struct {
	Failed int
	Total  int
}

func (e *PartialError) Error() string {
	return fmt.Sprintf("%d of %d photos could not be exported", e.Failed, e.Total)
}

// JobParams is what an export job stores. Serial and RelPath are the export
// folder, under the names [jobutil.Job.Source] reads, so the job is shown to
// whoever queued it while they can read that folder.
type JobParams struct {
	Serial  string `json:"serial"`
	RelPath string `json:"relPath"`
	// AlbumIDs are the albums to export, each with its sub-albums. Ignored
	// when Library is set.
	AlbumIDs []int64 `json:"albumIds"`
	// Library exports every album and every photo in none.
	Library bool `json:"library"`
}

// StartExportParams asks for an export.
type StartExportParams struct {
	// Ctx bounds the checks made before the job is queued.
	Ctx      context.Context
	Queries  db.Querier
	Registry vfs.Registry
	// Queue runs the export. Its Handler for [Kind] comes from [NewHandler].
	Queue *jobutil.Queue
	// Access is the account exporting. The albums are its own, and it needs
	// write access to Folder.
	Access   accessutil.Access
	AlbumIDs []int64
	Library  bool
	// Serial and Folder are the folder the export folder is made in.
	Serial string
	Folder string
}

// StartExportResult is the export that was queued.
type StartExportResult struct {
	JobID int64
	// Serial and RelPath are the new export folder.
	Serial  string
	RelPath string
}

// StartExport checks the albums are the account's and the folder is one it
// can write to, makes a new export folder inside it, named after the album
// or after the library and never one that is already there, and queues the
// job that fills it.
func StartExport(params StartExportParams) (StartExportResult, error) {
	ctx := params.Ctx
	if !params.Library && len(params.AlbumIDs) == 0 {
		return StartExportResult{}, ErrNothingToExport
	}
	userID := params.Access.Principal().UserID
	name := "Photo library export"
	if !params.Library {
		name = "Photo albums export"
		for _, id := range params.AlbumIDs {
			album, err := params.Queries.GetAlbum(ctx, db.GetAlbumParams{ID: id, UserID: userID})
			if errors.Is(err, sql.ErrNoRows) {
				return StartExportResult{}, ErrAlbumNotFound
			}
			if err != nil {
				return StartExportResult{}, fmt.Errorf("read album %d: %w", id, err)
			}
			if len(params.AlbumIDs) == 1 {
				name = folderName(album.Name)
			}
		}
	}

	folder := accessutil.Canonical(params.Folder)
	if !params.Access.Check(params.Serial, folder, accessutil.Write).Allowed {
		return StartExportResult{}, ErrDestinationForbidden
	}
	fsys, err := fileutil.FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return StartExportResult{}, ErrFolderNotFound
	}
	if info, err := fsys.Stat(ctx, folder); err != nil || !info.IsDir {
		if err == nil || errors.Is(err, vfs.ErrNotFound) {
			return StartExportResult{}, ErrFolderNotFound
		}
		return StartExportResult{}, fmt.Errorf("stat %s: %w", folder, err)
	}
	relPath, err := freeFolder(ctx, fsys, folder, name)
	if err != nil {
		return StartExportResult{}, err
	}
	if err := prepareFolder(ctx, fsys, relPath); err != nil {
		return StartExportResult{}, err
	}

	job := JobParams{Serial: params.Serial, RelPath: relPath, AlbumIDs: params.AlbumIDs, Library: params.Library}
	if params.Library {
		job.AlbumIDs = nil
	}
	queued, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   "Export photos to " + path.Base(relPath),
		Params: job,
		UserID: userID,
	})
	if err != nil {
		return StartExportResult{}, fmt.Errorf("queue the export: %w", err)
	}
	return StartExportResult{JobID: queued.Job.ID, Serial: params.Serial, RelPath: relPath}, nil
}

// ExportParams is an export to run.
type ExportParams struct {
	Ctx      context.Context
	Queries  db.Querier
	Registry vfs.Registry
	// Access is the account the export runs as: its albums, and only the
	// photos it can read.
	Access accessutil.Access
	Job    JobParams
	// Storage names the drives in the manifest. Nil names them by serial.
	Storage *storageutil.StorageService
	// EventBus is told of every file copied. Nil publishes nothing.
	EventBus *eventbus.Bus
	// IOSemaphore throttles the copies to yield to interactive requests. Nil
	// does not throttle.
	IOSemaphore *iosemutil.Semaphore
	// Report receives the fraction of files done. Nil reports nothing.
	Report func(float64)
}

// Failure is a photo an export could not copy.
type Failure struct {
	// Name is the original's file name.
	Name string `json:"name"`
	// Path is where the copy would have gone, inside the export folder.
	Path string `json:"path"`
	// Reason is [ReasonMissing] or [ReasonNotCopied].
	Reason string `json:"reason"`
}

// ExportResult is what an export did.
type ExportResult struct {
	Copied   int
	Failures []Failure
}

// Export copies the job's albums into its export folder and writes the
// manifest. Files already there from an earlier run of the same job are
// replaced. A failure to copy one photo is recorded and the export goes on;
// the error is then a [PartialError]. A failure to write the export itself,
// or a canceled ctx, stops it.
func Export(params ExportParams) (ExportResult, error) {
	var result ExportResult
	ctx := params.Ctx
	dst, err := fileutil.FilesVFS(params.Registry, params.Job.Serial)
	if err != nil {
		return result, err
	}
	if err := prepareFolder(ctx, dst, params.Job.RelPath); err != nil {
		return result, err
	}
	entries, err := plan(ctx, params)
	if err != nil {
		return result, err
	}
	taken, err := photoutil.TakenDates(photoutil.TakenDatesParams{Ctx: ctx, Queries: params.Queries})
	if err != nil {
		return result, err
	}
	names := driveNames(params.Storage)

	// Every copy is made before the manifest is written, so the manifest's
	// write is the only one under way while it streams.
	for i := range entries {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		e := &entries[i]
		target := path.Join(params.Job.RelPath, e.dest)
		e.outcome = "copied"
		if copyErr := copyOne(ctx, params, *e, dst, target); copyErr != nil {
			e.outcome = ReasonNotCopied
			if errors.Is(copyErr, vfs.ErrNotFound) {
				e.outcome = ReasonMissing
			}
			result.Failures = append(result.Failures, Failure{Name: path.Base(e.relPath), Path: e.dest, Reason: e.outcome})
		} else {
			result.Copied++
			if params.EventBus != nil {
				params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: target, DeviceSerial: params.Job.Serial})
			}
		}
		if params.Report != nil {
			params.Report(float64(i+1) / float64(len(entries)))
		}
	}
	err = writeManifest(ctx, dst, path.Join(params.Job.RelPath, ManifestName), func(w *csv.Writer) error {
		if err := w.Write(manifestHeader); err != nil {
			return err
		}
		for _, e := range entries {
			takenAt := ""
			if t, ok := taken.Dates[photoutil.DuplicatePhoto{DeviceSerial: e.serial, RelPath: e.relPath}]; ok {
				takenAt = t.UTC().Format(time.RFC3339)
			}
			row := []string{e.dest, driveName(names, e.serial), e.relPath, takenAt, strings.Join(e.albums, "; "), e.outcome}
			if err := w.Write(row); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return result, err
	}
	if len(result.Failures) > 0 {
		return result, &PartialError{Failed: len(result.Failures), Total: len(entries)}
	}
	return result, nil
}

// ReadSummaryParams names an export folder to summarize.
type ReadSummaryParams struct {
	Ctx      context.Context
	Registry vfs.Registry
	Serial   string
	RelPath  string
}

// ReadSummaryResult is what an export's manifest says it did. It is empty for
// an export that has not written its manifest yet.
type ReadSummaryResult struct {
	Copied int
	// Failures is the first [MaxListedFailures] files not copied, in manifest
	// order; MoreFailures counts the rest.
	Failures     []Failure
	MoreFailures int
}

// MaxListedFailures caps the failures a summary names.
const MaxListedFailures = 500

// ReadSummary reads an export's manifest, a row at a time, and counts the
// files it copied and names those it did not.
func ReadSummary(params ReadSummaryParams) (ReadSummaryResult, error) {
	result := ReadSummaryResult{Failures: []Failure{}}
	fsys, err := fileutil.FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return result, err
	}
	file, err := fsys.Open(params.Ctx, path.Join(params.RelPath, ManifestName))
	if errors.Is(err, vfs.ErrNotFound) {
		return result, nil
	}
	if err != nil {
		return result, fmt.Errorf("open the manifest: %w", err)
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.FieldsPerRecord = len(manifestHeader)
	if _, err := reader.Read(); err != nil {
		// A manifest cut short before its header has nothing to count.
		return result, nil
	}
	for {
		row, err := reader.Read()
		if errors.Is(err, io.EOF) {
			return result, nil
		}
		if err != nil {
			return result, fmt.Errorf("read the manifest: %w", err)
		}
		switch outcome := row[colResult]; {
		case outcome == "copied":
			result.Copied++
		case len(result.Failures) < MaxListedFailures:
			result.Failures = append(result.Failures, Failure{Name: path.Base(row[colSourcePath]), Path: row[colFile], Reason: outcome})
		default:
			result.MoreFailures++
		}
	}
}

// NewHandlerParams configures [NewHandler].
type NewHandlerParams struct {
	Database    *db.DatabaseSqlc
	Storage     *storageutil.StorageService
	Registry    vfs.Registry
	EventBus    *eventbus.Bus
	IOSemaphore *iosemutil.Semaphore
}

// NewHandler returns the jobutil Handler for [Kind]. It runs the export as
// the account that queued it, with its access as it stands now, and fails at
// once if that account can no longer write to the export folder.
func NewHandler(params NewHandlerParams) jobutil.Handler {
	return jobutil.Handler{
		Run: func(ctx context.Context, raw json.RawMessage, report func(float64)) error {
			var job JobParams
			if err := json.Unmarshal(raw, &job); err != nil {
				return fmt.Errorf("decode export params: %w", err)
			}
			creator, err := accessutil.LoadCreator(accessutil.LoadCreatorParams{
				Ctx: ctx, Database: params.Database, Storage: params.Storage, UserID: jobutil.UserID(ctx),
			})
			if err != nil {
				return err
			}
			if !creator.Access.Check(job.Serial, job.RelPath, accessutil.Write).Allowed {
				return ErrDestinationForbidden
			}
			_, err = Export(ExportParams{
				Ctx:         ctx,
				Queries:     params.Database.Queries,
				Registry:    params.Registry,
				Access:      creator.Access,
				Job:         job,
				Storage:     params.Storage,
				EventBus:    params.EventBus,
				IOSemaphore: params.IOSemaphore,
				Report:      report,
			})
			return err
		},
		Validate: func(raw json.RawMessage) error {
			var job JobParams
			if err := json.Unmarshal(raw, &job); err != nil {
				return fmt.Errorf("decode export params: %w", err)
			}
			return nil
		},
	}
}

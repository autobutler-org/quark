package backup

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// RestoreKind is the jobutil kind a restore of files from a snapshot drive
// runs under. One restore runs at a time.
const RestoreKind = "snapshot-restore"

// The failures a caller of [StartRestoreFiles] can fix.
var (
	// ErrRestoreRoleRequired reports a drive without the snapshot-backup
	// role: files are restored only from the drive snapshots are written to.
	ErrRestoreRoleRequired = errors.New("files are restored only from a drive with the snapshot-backup role")
	// ErrNoSnapshot reports a drive that holds no device's folder.
	ErrNoSnapshot = errors.New("the drive holds no snapshot of any device")
	// ErrRestoreDevicesMissing reports a snapshot whose every device is
	// gone, when built-in storage was not chosen to take their files.
	ErrRestoreDevicesMissing = errors.New("the drives these files came from are not attached; restore them to built-in storage instead")
)

// RestoreFolder is one device's folder on the snapshot drive and where its
// files go back to.
type RestoreFolder struct {
	// Folder is the device's folder at the drive's root, as the snapshot
	// named it: "internal", or the device name, an underscore, and the
	// first 8 characters of its serial.
	Folder string `json:"folder"`
	// TargetSerial is the device the files go back onto, "" for built-in
	// storage.
	TargetSerial string `json:"targetSerial"`
	// ToBuiltIn is set when the device the files came from is gone. They go
	// into a folder of the same name on built-in storage, beside its own.
	ToBuiltIn bool `json:"toBuiltIn"`
}

// RestoreJobParams is what a restore job stores. Nothing secret goes here.
type RestoreJobParams struct {
	BackupSerial string          `json:"backupSerial"`
	Folders      []RestoreFolder `json:"folders"`
}

// StartRestoreFilesParams asks for the files a snapshot holds to go back.
type StartRestoreFilesParams struct {
	// Ctx bounds the checks made before the job is queued.
	Ctx context.Context
	// Queries reads the drive's role, which must be snapshot-backup.
	Queries db.Querier
	// Registry holds the snapshot drive's files namespace and every device's.
	Registry vfs.Registry
	// Queue runs the restore. Its Handler for [RestoreKind] comes from
	// [NewRestoreHandler].
	Queue *jobutil.Queue
	// UserID is the admin starting the restore. 0 records none.
	UserID int64
	// BackupSerial is the snapshot drive, "" for built-in storage.
	BackupSerial string
	// Storage names the snapshot drive in the job name. Nil names it by
	// serial.
	Storage *storageutil.StorageService
	// MissingToBuiltIn puts the files of a device that is no longer attached
	// on built-in storage. Unset, they stay on the snapshot drive and are
	// named in [StartRestoreFilesResult.Missing].
	MissingToBuiltIn bool
}

// StartRestoreFilesResult is the restore that was queued.
type StartRestoreFilesResult struct {
	JobID string `json:"jobId"`
	// Folders is where each device's files are going, in folder order.
	Folders []RestoreFolder `json:"folders"`
	// Missing is the folders, sorted, whose device is gone and whose files
	// were left on the snapshot drive.
	Missing []string `json:"missing"`
}

// StartRestoreFiles matches each device folder on the snapshot drive to the
// device it was copied from and queues a job that copies the files back.
func StartRestoreFiles(params StartRestoreFilesParams) (StartRestoreFilesResult, error) {
	ctx := params.Ctx
	role, err := params.Queries.GetDeviceRole(ctx, params.BackupSerial)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && role != "snapshot-backup") {
		return StartRestoreFilesResult{}, ErrRestoreRoleRequired
	}
	if err != nil {
		return StartRestoreFilesResult{}, fmt.Errorf("read the drive's role: %w", err)
	}
	drive, err := fileutil.FilesVFS(params.Registry, params.BackupSerial)
	if err != nil {
		return StartRestoreFilesResult{}, err
	}
	entries, err := drive.List(ctx, "", nil)
	if err != nil {
		return StartRestoreFilesResult{}, fmt.Errorf("list the snapshot drive: %w", err)
	}

	devices := vfs.FilesNamespaces(params.Registry)
	result := StartRestoreFilesResult{Folders: []RestoreFolder{}, Missing: []string{}}
	for _, entry := range entries {
		if !entry.IsDir || strings.HasPrefix(entry.Name, ".") {
			continue
		}
		serial, attached := folderDevice(entry.Name, devices)
		switch {
		case attached && serial == params.BackupSerial:
			// The snapshot drive's own files, from before it took the role.
		case attached:
			result.Folders = append(result.Folders, RestoreFolder{Folder: entry.Name, TargetSerial: serial})
		case params.MissingToBuiltIn:
			result.Folders = append(result.Folders, RestoreFolder{Folder: entry.Name, ToBuiltIn: true})
		default:
			result.Missing = append(result.Missing, entry.Name)
		}
	}
	sort.Slice(result.Folders, func(i, j int) bool { return result.Folders[i].Folder < result.Folders[j].Folder })
	sort.Strings(result.Missing)
	if len(result.Folders) == 0 {
		if len(result.Missing) > 0 {
			return result, ErrRestoreDevicesMissing
		}
		return result, ErrNoSnapshot
	}

	queued, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind:   RestoreKind,
		Name:   restoreJobName(driveNames(params.Storage), params.BackupSerial),
		Params: RestoreJobParams{BackupSerial: params.BackupSerial, Folders: result.Folders},
		UserID: params.UserID,
	})
	if err != nil {
		return StartRestoreFilesResult{}, fmt.Errorf("queue the restore: %w", err)
	}
	result.JobID = strconv.FormatInt(queued.Job.ID, 10)
	return result, nil
}

// folderDevice is the attached device a snapshot folder was copied from:
// "internal" is built-in storage, and "<name>_<suffix>" the one device whose
// serial starts with suffix, as [deviceDirName] spelled it. A suffix two
// serials share names neither, so their files are not guessed onto one.
func folderDevice(folder string, devices map[string]vfs.VFS) (string, bool) {
	if folder == "internal" {
		_, ok := devices[""]
		return "", ok
	}
	cut := strings.LastIndex(folder, "_")
	if cut < 0 {
		return "", false
	}
	suffix := folder[cut+1:]
	found, matches := "", 0
	for serial := range devices {
		if serial != "" && serial[:min(len(serial), 8)] == suffix {
			found, matches = serial, matches+1
		}
	}
	return found, matches == 1
}

// RestoreFilesParams is a restore to run.
type RestoreFilesParams struct {
	Ctx          context.Context
	Registry     vfs.Registry
	BackupSerial string
	Folders      []RestoreFolder
	// EventBus is told of every file restored. Nil publishes nothing.
	EventBus *eventbus.Bus
	// IOSemaphore throttles the copies to yield to interactive requests.
	IOSemaphore *iosemutil.Semaphore
	// Report receives the fraction of files done. Nil reports nothing.
	Report func(float64)
}

// RestoreFilesResult counts what a restore did.
type RestoreFilesResult struct {
	FilesCopied int
	// FilesKept is the files left as they are, because the target already
	// has a file at that path. A restore never overwrites.
	FilesKept   int
	BytesCopied int64
}

// RestoreFiles copies each folder's files from the snapshot drive back onto
// its device. A file already at the target path is kept as it is, so a
// restore never overwrites what changed since the snapshot, and each copy
// lands under its name only once it is whole. A failure stops the restore
// and leaves every file already copied, and everything else on the target,
// in place.
func RestoreFiles(params RestoreFilesParams) (RestoreFilesResult, error) {
	ctx := params.Ctx
	drive, err := fileutil.FilesVFS(params.Registry, params.BackupSerial)
	if err != nil {
		return RestoreFilesResult{}, err
	}
	total := 0
	for _, folder := range params.Folders {
		files, err := countFiles(ctx, drive, folder.Folder)
		if err != nil {
			return RestoreFilesResult{}, fmt.Errorf("scan %s: %w", folder.Folder, err)
		}
		total += files
	}

	var result RestoreFilesResult
	lastReport := time.Time{}
	for _, folder := range params.Folders {
		target, err := fileutil.FilesVFS(params.Registry, folder.TargetSerial)
		if err != nil {
			return result, fmt.Errorf("restore %s: %w", folder.Folder, err)
		}
		err = vfs.Walk(ctx, drive, folder.Folder, func(info vfs.FileInfo) error {
			if err := ctx.Err(); err != nil {
				return err
			}
			rel := strings.TrimPrefix(info.Path, folder.Folder+"/")
			if folder.ToBuiltIn {
				rel = path.Join(folder.Folder, rel)
			}
			if info.IsDir {
				return target.MkdirAll(ctx, rel)
			}
			copied, err := restoreFile(ctx, params, drive, info.Path, target, rel)
			if err != nil {
				return err
			}
			if copied {
				result.FilesCopied++
				result.BytesCopied += info.Size
				if params.EventBus != nil {
					params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: rel, DeviceSerial: folder.TargetSerial})
				}
			} else {
				result.FilesKept++
			}
			if params.Report != nil && total > 0 && time.Since(lastReport) > time.Second {
				params.Report(float64(result.FilesCopied+result.FilesKept) / float64(total))
				lastReport = time.Now()
			}
			return nil
		})
		if err != nil {
			return result, fmt.Errorf("restore %s: %w", folder.Folder, err)
		}
	}
	return result, nil
}

// restoreFile copies one file back unless the target already has one there,
// and reports whether it copied.
func restoreFile(ctx context.Context, params RestoreFilesParams, drive vfs.VFS, srcPath string, target vfs.VFS, dstPath string) (bool, error) {
	if _, err := target.Stat(ctx, dstPath); err == nil {
		return false, nil
	} else if !errors.Is(err, vfs.ErrNotFound) {
		return false, fmt.Errorf("stat %s: %w", dstPath, err)
	}
	if params.IOSemaphore != nil {
		if !params.IOSemaphore.AcquireDefault(ctx) {
			return false, fmt.Errorf("restore: IO semaphore timeout copying %s", srcPath)
		}
		defer params.IOSemaphore.Release()
	}
	err := vfs.CopyBetween(ctx, drive, srcPath, target, dstPath, vfs.CopyOptions{IfNoneMatch: "*"})
	if errors.Is(err, vfs.ErrConflict) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("copy %s: %w", srcPath, err)
	}
	return true, nil
}

// countFiles counts the files under dir in fsys.
func countFiles(ctx context.Context, fsys vfs.VFS, dir string) (files int, err error) {
	err = vfs.Walk(ctx, fsys, dir, func(fi vfs.FileInfo) error {
		if !fi.IsDir {
			files++
		}
		return nil
	})
	return
}

// NewRestoreHandlerParams configures [NewRestoreHandler].
type NewRestoreHandlerParams struct {
	Registry    vfs.Registry
	EventBus    *eventbus.Bus
	IOSemaphore *iosemutil.Semaphore
}

// NewRestoreHandler returns the jobutil Handler for [RestoreKind]. It runs
// the restore its job was queued with.
func NewRestoreHandler(params NewRestoreHandlerParams) jobutil.Handler {
	return jobutil.Handler{
		Run: func(ctx context.Context, raw json.RawMessage, report func(float64)) error {
			var job RestoreJobParams
			if err := json.Unmarshal(raw, &job); err != nil {
				return fmt.Errorf("decode restore params: %w", err)
			}
			_, err := RestoreFiles(RestoreFilesParams{
				Ctx:          ctx,
				Registry:     params.Registry,
				BackupSerial: job.BackupSerial,
				Folders:      job.Folders,
				EventBus:     params.EventBus,
				IOSemaphore:  params.IOSemaphore,
				Report:       report,
			})
			return err
		},
		Validate: func(raw json.RawMessage) error {
			var job RestoreJobParams
			if err := json.Unmarshal(raw, &job); err != nil {
				return fmt.Errorf("decode restore params: %w", err)
			}
			return nil
		},
	}
}

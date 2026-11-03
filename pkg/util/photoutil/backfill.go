package photoutil

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/indexutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// BackfillHashesParams points the backfill at the photo library.
type BackfillHashesParams struct {
	Ctx     context.Context
	Queries db.Querier
	// Registry enumerates the library the way [ListPhotos] does, and each
	// photo is read through its device's namespace in it.
	Registry vfs.Registry
	// IOSemaphore, when set, is held while each photo is read. Photos are
	// read one at a time, so the pass takes at most one slot from requests.
	IOSemaphore *iosemutil.Semaphore
	// Control, when set, hears what the pass counts and holds it between
	// photos while paused (#3556).
	Control *IndexControl
	// EventBus, when set, hears photo_index_changed as the pass starts,
	// makes progress, and finishes.
	EventBus *eventbus.Bus
	// Index, when set, lists the library from memory instead of walking it.
	Index *indexutil.FileIndex
}

// BackfillHashesResult counts what the backfill did.
type BackfillHashesResult struct {
	// Scanned is the photos in the library.
	Scanned int
	// Hashed is the photos that had no complete row and now have one.
	Hashed int
	// Dated is the photos whose hashes were complete but whose capture date
	// had never been read, and now has been (#2592).
	Dated int
	// Failed is the photos that could not be read or stored, or that no
	// decoder here could give a perceptual hash.
	Failed int
}

// BackfillHashes hashes every library photo that has no photo_hashes row, or
// a row missing its dHash or content hash, and leaves every complete row
// alone. A complete row whose capture date was never read — every row a
// device stored before #2592 — has its EXIF read, and nothing re-hashed. Photos only used to be hashed when their thumbnail was generated,
// and never by content, so a library whose thumbnails were already cached had
// nothing for [ListDuplicates] to group (#1666). It is idempotent: once
// everything is hashed a run costs one library listing and one query, and a
// pass stopped part way picks up where it left off.
//
// A photo that cannot be decoded keeps the dHash it already had, which a
// client may have sent with its thumbnail, and gains a content hash. Without
// one it is counted failed, with its reason in the [IndexControl].
// ponytail: failures live in memory, so such a photo is read again on every
// run; record them if a library of those shows up.
func BackfillHashes(params BackfillHashesParams) (BackfillHashesResult, error) {
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		return BackfillHashesResult{}, err
	}
	library, err := ListPhotos(ListPhotosParams{
		Ctx: params.Ctx, Registry: params.Registry,
		Access: system.Access, Limit: math.MaxInt, Index: params.Index,
	})
	if err != nil {
		return BackfillHashesResult{}, fmt.Errorf("list photos: %w", err)
	}
	rows, err := params.Queries.ListPhotoHashStates(params.Ctx)
	if err != nil {
		return BackfillHashesResult{}, fmt.Errorf("list photo hashes: %w", err)
	}
	complete := map[DuplicatePhoto]bool{}
	dated := map[DuplicatePhoto]bool{}
	knownDHash := map[DuplicatePhoto]string{}
	for _, row := range rows {
		key := DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}
		complete[key] = row.Dhash.Valid && row.HasContentHash
		dated[key] = row.TakenChecked
		knownDHash[key] = row.Dhash.String
	}

	var todo []DuplicatePhoto
	total, hashed, datesRead := 0, 0, 0
	for _, photo := range library.Photos {
		key := DuplicatePhoto{DeviceSerial: photo.Serial, RelPath: accessutil.Canonical(photo.RelPath)}
		if storageutil.IsTrashPath(key.RelPath) {
			continue
		}
		total++
		if complete[key] {
			hashed++
		}
		if dated[key] {
			datesRead++
		}
		if !complete[key] || !dated[key] {
			todo = append(todo, key)
		}
	}
	params.Control.begin(total, hashed, datesRead)
	publishIndexChanged(params.EventBus)
	result := BackfillHashesResult{Scanned: len(library.Photos)}
	err = backfillPhotos(params, todo, complete, dated, knownDHash, &result)
	params.Control.finish(err == nil)
	publishIndexChanged(params.EventBus)
	return result, err
}

// backfillPhotos indexes each photo in todo, waiting out a pause before each
// one, and counts what happened in result.
func backfillPhotos(
	params BackfillHashesParams, todo []DuplicatePhoto,
	complete, dated map[DuplicatePhoto]bool, knownDHash map[DuplicatePhoto]string,
	result *BackfillHashesResult,
) error {
	for _, key := range todo {
		// Checked between photos, with no IO slot held, so a paused pass
		// leaves every slot to requests.
		if err := params.Control.waitWhilePaused(params.Ctx); err != nil {
			return err
		}
		var err error
		failure := ""
		hashedNow, datedNow := false, false
		if complete[key] {
			err = backfillTakenAt(params, key)
			datedNow = err == nil
		} else {
			var decodeErr error
			decodeErr, err = backfillPhoto(params, key, knownDHash[key])
			if err == nil {
				hashedNow, datedNow = decodeErr == nil, !dated[key]
			}
			if decodeErr != nil {
				log.Printf("[photo-hashes] %q (serial=%q): no perceptual hash: %v", key.RelPath, key.DeviceSerial, decodeErr)
				failure = indexFailureReason(key.RelPath, decodeErr)
			}
		}
		if err != nil {
			log.Printf("[photo-hashes] %q (serial=%q): %v", key.RelPath, key.DeviceSerial, err)
			failure = IndexFailureUnreadable
		}
		switch {
		case failure != "":
			result.Failed++
		case complete[key]:
			result.Dated++
		default:
			result.Hashed++
		}
		progress := params.Control.indexed(hashedNow, datedNow)
		if failure != "" {
			progress = params.Control.failed(IndexFailure{
				Serial: key.DeviceSerial, RelPath: key.RelPath, Reason: failure,
			}) || progress
		}
		if progress {
			publishIndexChanged(params.EventBus)
		}
	}
	return nil
}

// indexFailureReason names why relPath would not decode.
func indexFailureReason(relPath string, decodeErr error) string {
	switch {
	case errors.Is(decodeErr, ErrImageTooLarge):
		return IndexFailureTooLarge
	case IsRawFile(relPath) && !IsRawConverterAvailable():
		return IndexFailureMissingConverter
	default:
		return IndexFailureUndecodable
	}
}

// backfillPhoto hashes one photo under the IO semaphore, keeping dhash when
// the file will not decode. decodeErr is why the photo still has no dHash
// once its content hash is stored; err is why nothing was stored.
func backfillPhoto(params BackfillHashesParams, photo DuplicatePhoto, dhash string) (decodeErr, err error) {
	release, err := acquireBackfillSlot(params)
	if err != nil {
		return nil, err
	}
	defer release()
	fsys, err := DeviceFS(params.Registry, photo.DeviceSerial)
	if err != nil {
		return nil, err
	}
	f, err := fsys.Open(params.Ctx, photo.RelPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	decoded, decodeErr := DHashSource(params.Ctx, fsys, photo.RelPath, f)
	if decodeErr == nil {
		dhash = decoded
	}
	if _, err := StorePhotoHashes(StorePhotoHashesParams{
		Ctx: params.Ctx, Queries: params.Queries,
		Serial: photo.DeviceSerial, RelPath: photo.RelPath,
		DHash: dhash, Source: f,
	}); err != nil {
		return nil, err
	}
	if dhash != "" {
		return nil, nil
	}
	return decodeErr, nil
}

// backfillTakenAt reads the capture date of one already-hashed photo under
// the IO semaphore. Only the EXIF header is read, not the whole file.
func backfillTakenAt(params BackfillHashesParams, photo DuplicatePhoto) error {
	release, err := acquireBackfillSlot(params)
	if err != nil {
		return err
	}
	defer release()
	fsys, err := DeviceFS(params.Registry, photo.DeviceSerial)
	if err != nil {
		return err
	}
	f, err := fsys.Open(params.Ctx, photo.RelPath)
	if err != nil {
		return err
	}
	defer f.Close()
	takenAt, err := readTakenAt(f, photo.RelPath)
	if err != nil {
		return err
	}
	return params.Queries.SetPhotoTakenAt(params.Ctx, db.SetPhotoTakenAtParams{
		TakenAt: takenAt, DeviceSerial: photo.DeviceSerial, RelPath: photo.RelPath,
	})
}

// acquireBackfillSlot waits for the IO semaphore, when there is one, and
// returns its release.
func acquireBackfillSlot(params BackfillHashesParams) (func(), error) {
	sem := params.IOSemaphore
	if sem == nil {
		return func() {}, nil
	}
	// Wait as long as it takes: requests come first.
	for !sem.AcquireDefault(params.Ctx) {
		if err := params.Ctx.Err(); err != nil {
			return nil, err
		}
	}
	return sem.Release, nil
}

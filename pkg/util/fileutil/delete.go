package fileutil

import (
	"context"
	"errors"
	"log"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// DeleteFilesParams moves a batch of files to the device's trash. The
// filesystem half returns in under a second even for a large batch; the
// database and event-bus cleanup it leaves behind is dispatched in the
// background.
type DeleteFilesParams struct {
	// Storage owns the files directory and the trash inside it.
	Storage *storageutil.StorageService
	// EventBus is told about every deleted path, and that the trash changed.
	EventBus *eventbus.Bus
	// Database holds the album membership and rotation rows to clean up. Nil
	// skips that half.
	Database *db.DatabaseSqlc
	// RootDir is the directory the paths are relative to.
	RootDir string
	// FilePaths are the files to delete.
	FilePaths []string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// DeleteFilesResult reports a completed delete. The background cleanup it
// started may still be running.
type DeleteFilesResult struct{}

// DeleteFiles moves files to the trash and starts the cleanup their absence
// implies. Every device trashes, the internal one included: the "files" VFS
// namespace is the internal device's files directory, so trashing through the
// StorageService with the empty serial lands where a VFS delete used to remove
// files for good (#1814).
func DeleteFiles(params DeleteFilesParams) (DeleteFilesResult, error) {
	// ── Phase 1: fast filesystem op (returns in < 1 s even for large batches) ─

	// A rename into .trash/ is a metadata-only op, microseconds on an SD card.
	if _, err := params.Storage.TrashFiles(storageutil.TrashFilesParams{
		RootDir:      params.RootDir,
		FilePaths:    params.FilePaths,
		DeviceSerial: params.Serial,
	}); err != nil {
		if errors.Is(err, storageutil.ErrDeviceNotFound) {
			return DeleteFilesResult{}, notFound(err)
		}
		return DeleteFilesResult{}, err
	}

	// ── Phase 2: async cleanup — event bus + DB ──────────────────────────────
	// Capture everything the goroutine needs before the context is cancelled.
	bus := params.EventBus
	database := params.Database
	serial := params.Serial
	// The paths are relative to RootDir; everything downstream (the search
	// index, the file index, the album rows) keys on the path relative to the
	// files directory.
	relPaths := make([]string, len(params.FilePaths))
	for i, p := range params.FilePaths {
		relPaths[i] = filepath.ToSlash(filepath.Join(params.RootDir, p))
	}

	go func() {
		bus.Publish(eventbus.Event{Kind: eventbus.EventTrashChanged, DeviceSerial: serial})
		for _, p := range relPaths {
			bus.Publish(eventbus.Event{
				Kind:         eventbus.EventDelete,
				Path:         p,
				DeviceSerial: serial,
			})
			if database == nil {
				continue
			}
			ctx := context.Background()
			if err := database.Queries.DeletePhotoFromAllAlbums(ctx, db.DeletePhotoFromAllAlbumsParams{
				DeviceSerial: serial,
				RelPath:      p,
			}); err != nil {
				log.Printf("quark: delete cleanup: remove album items for %q (serial=%q): %v", p, serial, err)
			}
			if err := database.Queries.DeletePhotoRotation(ctx, db.DeletePhotoRotationParams{
				DeviceSerial: serial,
				RelPath:      p,
			}); err != nil {
				log.Printf("quark: delete cleanup: remove rotation for %q (serial=%q): %v", p, serial, err)
			}
		}
	}()

	return DeleteFilesResult{}, nil
}

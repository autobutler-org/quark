package server

import (
	"context"
	"log"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// startContentIndexer subscribes to file events and keeps the FTS5 content
// index in sync. It runs as a background goroutine for the lifetime of the
// server process.
//
// Upload → index content (if file is a supported text format)
// Delete → remove index entry
// Move   → remove old entry, index new path
//
// Indexing is best-effort: failures are logged but never surfaced to the
// caller. The index can always be rebuilt from disk.
func startContentIndexer(deps deputil.Dependencies) {
	bus := deps.EventBus()
	if bus == nil {
		return
	}
	dbConn := deps.Database()
	if dbConn == nil || dbConn.Db == nil {
		return
	}
	db := dbConn.Db

	ch, unsub := bus.Subscribe("content-indexer")
	defer unsub()

	for evt := range ch {
		switch evt.Kind {
		case eventbus.EventUpload:
			if evt.Path == "" {
				continue
			}
			serial, absPath := resolveEventPath(deps, evt)
			if absPath == "" {
				continue
			}
			relPath := evt.Path
			if err := searchutil.IndexFileWithTimeout(db, serial, relPath, absPath, indexTimeout); err != nil {
				log.Printf("[content-indexer] index %s: %v", relPath, err)
			}

		case eventbus.EventDelete:
			if evt.Path == "" {
				continue
			}
			serial := evt.DeviceSerial
			if err := searchutil.DeleteContent(context.Background(), db, serial, evt.Path); err != nil {
				log.Printf("[content-indexer] delete %s: %v", evt.Path, err)
			}

		case eventbus.EventMove:
			if evt.Path == "" {
				continue
			}
			serial := evt.DeviceSerial
			// Remove old entry.
			if err := searchutil.DeleteContent(context.Background(), db, serial, evt.Path); err != nil {
				log.Printf("[content-indexer] delete old path %s: %v", evt.Path, err)
			}
			// Index new path if non-empty.
			if evt.NewPath != "" {
				serial2, absNew := resolveEventPath(deps, eventbus.Event{
					Path:         evt.NewPath,
					DeviceSerial: evt.DeviceSerial,
				})
				if absNew != "" {
					if err := searchutil.IndexFileWithTimeout(db, serial2, evt.NewPath, absNew, indexTimeout); err != nil {
						log.Printf("[content-indexer] index new path %s: %v", evt.NewPath, err)
					}
				}
			}
		}
	}
}

const indexTimeout = 5 * time.Second

// backfillTimeout bounds the whole startup indexing pass. A home server with
// a few thousand documents finishes in well under this; the cap exists so a
// pathological tree cannot leave the goroutine running forever.
const backfillTimeout = 10 * time.Minute

// backfillContentIndex indexes the files already present on every managed
// device. Run once at startup, after startContentIndexer, so that documents
// written before this build — or before the indexer understood their format —
// become searchable without the user having to re-save them.
//
// Best-effort, like the event-driven path: everything is logged and nothing
// surfaces to callers, since the index can always be rebuilt from disk.
func backfillContentIndex(deps deputil.Dependencies) {
	dbConn := deps.Database()
	if dbConn == nil || dbConn.Db == nil {
		return
	}
	devices, err := deps.StorageService().GetManagedDevices()
	if err != nil {
		log.Printf("[content-indexer] backfill: list devices: %v", err)
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), backfillTimeout)
	defer cancel()

	for _, dev := range devices {
		serial := ""
		if dev.UsbInfo != nil {
			serial = dev.UsbInfo.GetSerial()
		}
		res, err := searchutil.BackfillTree(ctx, dbConn.Db, serial, dev.FilesDir)
		if err != nil {
			log.Printf("[content-indexer] backfill %s: %v", dev.FilesDir, err)
			continue
		}
		log.Printf(
			"[content-indexer] backfill %s: scanned %d, indexed %d, failed %d",
			dev.FilesDir, res.Scanned, res.Indexed, res.Failed,
		)
	}
}

// resolveEventPath maps an event's DeviceSerial + relative path to an
// absolute filesystem path. Returns ("", "") when the device cannot be found.
func resolveEventPath(deps deputil.Dependencies, evt eventbus.Event) (serial, absPath string) {
	// Trashed files are not searchable; the backfill skips the trash too.
	if storageutil.IsTrashPath(evt.Path) {
		return "", ""
	}
	serial = evt.DeviceSerial
	devices, err := deps.StorageService().GetManagedDevices()
	if err != nil {
		return "", ""
	}
	for _, dev := range devices {
		devSerial := ""
		if dev.UsbInfo != nil {
			devSerial = dev.UsbInfo.GetSerial()
		}
		if devSerial == serial || (serial == "" && dev.UsbInfo == nil) {
			abs := filepath.Join(dev.FilesDir, evt.Path)
			return devSerial, abs
		}
	}
	return "", ""
}

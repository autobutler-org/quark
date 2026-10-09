package server

import (
	"context"
	"database/sql"
	"log"
	"maps"
	"slices"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// startContentIndexer subscribes to file events and keeps the FTS5 content
// index in sync. It runs as a background goroutine for the lifetime of the
// server process.
//
// Upload → index content (if file is a supported text format)
// Delete → remove index entry
// Move   → remove old entry, index new path
// Resync → backfill every device, as at startup
//
// Every file is read through its device's files namespace in the VFS
// registry. A device plugged in later is backfilled once its namespace is
// registered, and its entries are dropped when it is unplugged.
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
	registry := deps.VFSRegistry()

	if svc := deps.StorageService(); svc != nil {
		devices := newContentDevices(registry)
		svc.OnDevicesChanged(func() { go devices.sync(db, registry) })
	}

	ch, unsub := bus.Subscribe("content-indexer")
	defer unsub()

	for evt := range ch {
		handleContentEvent(deps, db, registry, evt)
	}
}

// handleContentEvent applies one file event to the content index.
func handleContentEvent(deps deputil.Dependencies, db *sql.DB, registry vfs.Registry, evt eventbus.Event) {
	if evt.Kind == eventbus.EventResync {
		// The bus dropped events while this loop was busy (#2753), so
		// index the whole tree again, as at startup.
		backfillContentIndex(deps)
		return
	}
	if evt.Path == "" {
		return
	}
	serial := evt.DeviceSerial
	switch evt.Kind {
	case eventbus.EventUpload:
		indexEventPath(db, registry, serial, evt.Path)

	case eventbus.EventDelete:
		if err := searchutil.DeleteContent(context.Background(), db, serial, evt.Path); err != nil {
			log.Printf("[content-indexer] delete %s: %v", evt.Path, err)
		}

	case eventbus.EventMove:
		// Remove old entry.
		if err := searchutil.DeleteContent(context.Background(), db, serial, evt.Path); err != nil {
			log.Printf("[content-indexer] delete old path %s: %v", evt.Path, err)
		}
		// Index new path if non-empty.
		if evt.NewPath != "" {
			indexEventPath(db, registry, serial, evt.NewPath)
		}
	}
}

// indexEventPath indexes relPath on the device with serial through its files
// namespace. A device with no namespace is skipped, and so is the trash.
func indexEventPath(db *sql.DB, registry vfs.Registry, serial, relPath string) {
	fsys, ok := registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		return
	}
	if err := searchutil.IndexFileWithTimeout(db, fsys, serial, relPath, indexTimeout); err != nil {
		log.Printf("[content-indexer] index %s: %v", relPath, err)
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
	ctx, cancel := context.WithTimeout(context.Background(), backfillTimeout)
	defer cancel()
	namespaces := vfs.FilesNamespaces(deps.VFSRegistry())
	for _, serial := range slices.Sorted(maps.Keys(namespaces)) {
		backfillDevice(ctx, dbConn.Db, serial, namespaces[serial])
	}
}

// backfillDevice indexes the files already on one device.
func backfillDevice(ctx context.Context, db *sql.DB, serial string, fsys vfs.VFS) {
	res, err := searchutil.BackfillTree(ctx, searchutil.BackfillTreeParams{DB: db, Serial: serial, FS: fsys})
	if err != nil {
		log.Printf("[content-indexer] backfill %s: %v", vfs.FilesNamespace(serial), err)
		return
	}
	log.Printf(
		"[content-indexer] backfill %s: scanned %d, indexed %d, failed %d",
		vfs.FilesNamespace(serial), res.Scanned, res.Indexed, res.Failed,
	)
}

// contentDevices is the set of devices the content index covers, kept in step
// with the registry's files namespaces as drives come and go.
type contentDevices struct {
	mu    sync.Mutex
	known map[string]bool
}

// newContentDevices starts from the namespaces registered now, which the
// startup backfill covers.
func newContentDevices(registry vfs.Registry) *contentDevices {
	known := make(map[string]bool)
	for serial := range vfs.FilesNamespaces(registry) {
		known[serial] = true
	}
	return &contentDevices{known: known}
}

// sync backfills every device whose namespace appeared and drops the entries
// of every device whose namespace went away. The internal drive is never
// dropped.
func (d *contentDevices) sync(db *sql.DB, registry vfs.Registry) {
	d.mu.Lock()
	defer d.mu.Unlock()
	present := vfs.FilesNamespaces(registry)
	for serial := range d.known {
		if _, ok := present[serial]; ok || serial == "" {
			continue
		}
		delete(d.known, serial)
		if err := searchutil.DeleteContentBySerial(context.Background(), db, serial); err != nil {
			log.Printf("[content-indexer] drop %s: %v", vfs.FilesNamespace(serial), err)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), backfillTimeout)
	defer cancel()
	for _, serial := range slices.Sorted(maps.Keys(present)) {
		if d.known[serial] {
			continue
		}
		d.known[serial] = true
		backfillDevice(ctx, db, serial, present[serial])
	}
}

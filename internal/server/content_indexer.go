package server

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"maps"
	"slices"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// startContentIndexer subscribes to file events and keeps the FTS5 content
// index in sync. It runs as a background goroutine for the lifetime of the
// server process.
//
//	upload     → a file is indexed; a folder (an upload's root, including the
//	             files root) is walked and every indexable file under it is indexed
//	new_folder → the same as a folder upload: a created, restored, or extracted folder
//	delete     → remove the index entry
//	move       → remove the old entry, index the new path
//	resync     → backfill every device, as at startup
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
	serial := evt.DeviceSerial
	switch evt.Kind {
	case eventbus.EventUpload, eventbus.EventNewFolder:
		indexChangedPath(db, registry, serial, evt.Path)

	case eventbus.EventDelete:
		if evt.Path == "" {
			return
		}
		if err := searchutil.DeleteContent(context.Background(), db, serial, evt.Path); err != nil {
			log.Printf("[content-indexer] delete %s: %v", evt.Path, err)
		}

	case eventbus.EventMove:
		if evt.Path == "" {
			return
		}
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

// openIndexPath is the files namespace for serial and relPath in canonical
// form. A device with no namespace, and the trash, have nothing to index.
func openIndexPath(registry vfs.Registry, serial, relPath string) (vfs.VFS, string, bool) {
	fsys, ok := registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		return nil, "", false
	}
	relPath = accessutil.Canonical(relPath)
	if storageutil.IsTrashPath(relPath) {
		return nil, "", false
	}
	return fsys, relPath, true
}

// indexChangedPath indexes what an upload or new_folder event names. A
// directory is walked and every indexable file under it is read. A file is
// indexed on its own. An empty path is the files root.
func indexChangedPath(db *sql.DB, registry vfs.Registry, serial, relPath string) {
	fsys, relPath, ok := openIndexPath(registry, serial, relPath)
	if !ok {
		return
	}
	if relPath != "" {
		ctx, cancel := context.WithTimeout(context.Background(), indexTimeout)
		fi, err := fsys.Stat(ctx, relPath)
		cancel()
		switch {
		case errors.Is(err, vfs.ErrNotFound):
			return
		case err != nil:
			log.Printf("[content-indexer] stat %s: %v", relPath, err)
			return
		case !fi.IsDir:
			indexOne(db, fsys, serial, relPath)
			return
		}
	}
	indexFolder(db, fsys, serial, relPath)
}

// indexFolder reads every indexable file under relPath into the content
// index. The walk lists names through the VFS, and each file is read by
// IndexFile, which stops at searchutil.MaxExtractBytes. The pass stops at
// backfillTimeout so a large tree cannot run forever.
func indexFolder(db *sql.DB, fsys vfs.VFS, serial, relPath string) {
	ctx, cancel := context.WithTimeout(context.Background(), backfillTimeout)
	defer cancel()
	err := vfs.Walk(ctx, fsys, relPath, func(fi vfs.FileInfo) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if fi.IsDir {
			return nil
		}
		fileCtx, fileCancel := context.WithTimeout(ctx, indexTimeout)
		indexFile(fileCtx, db, fsys, serial, fi.Path)
		fileCancel()
		return nil
	})
	if err != nil && !errors.Is(err, vfs.ErrNotFound) && !errors.Is(err, vfs.ErrPermissionDenied) {
		log.Printf("[content-indexer] walk %s: %v", relPath, err)
	}
}

// indexEventPath indexes relPath on the device with serial through its files
// namespace. A move names the file's new path here.
func indexEventPath(db *sql.DB, registry vfs.Registry, serial, relPath string) {
	fsys, relPath, ok := openIndexPath(registry, serial, relPath)
	if !ok {
		return
	}
	indexOne(db, fsys, serial, relPath)
}

// indexOne reads one file with indexTimeout.
func indexOne(db *sql.DB, fsys vfs.VFS, serial, relPath string) {
	ctx, cancel := context.WithTimeout(context.Background(), indexTimeout)
	defer cancel()
	indexFile(ctx, db, fsys, serial, relPath)
}

// indexFile reads one file into the content index. The caller bounds ctx.
func indexFile(ctx context.Context, db *sql.DB, fsys vfs.VFS, serial, relPath string) {
	if err := searchutil.IndexFile(ctx, db, fsys, serial, relPath); err != nil {
		log.Printf("[content-indexer] index %s: %v", relPath, err)
	}
}

const indexTimeout = 5 * time.Second

// backfillTimeout bounds one indexing pass over a tree: startup, a resync,
// and a folder walk from an upload or new_folder event. A home server with
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

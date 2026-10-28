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
// Upload     → index the file, or every file under the folder the event names
// New folder → the same: a restored or extracted folder names itself
// Delete     → remove the index entry
// Move       → remove the old entry, index the new file
// Resync     → backfill every device, as at startup
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
		// An upload names the folder the files landed in, and a restored
		// or extracted folder arrives as new_folder. Either may name a file.
		indexEventPath(db, registry, serial, evt.Path)

	case eventbus.EventDelete:
		deleteContentPath(db, serial, evt.Path)

	case eventbus.EventMove:
		// An empty path is the root, not a row.
		if accessutil.Canonical(evt.Path) == "" {
			return
		}
		deleteContentPath(db, serial, evt.Path)
		// A moved folder is not walked. Its rows still name the old paths,
		// and indexing the new tree would leave both.
		indexMovedPath(db, registry, serial, evt.NewPath)
	}
}

// deleteContentPath removes the index row for relPath. An empty path names
// the root, which is not a row.
func deleteContentPath(db *sql.DB, serial, relPath string) {
	relPath = accessutil.Canonical(relPath)
	if relPath == "" {
		return
	}
	if err := searchutil.DeleteContent(context.Background(), db, serial, relPath); err != nil {
		log.Printf("[content-indexer] delete %s: %v", relPath, err)
	}
}

// indexEventPath indexes relPath on the device with serial. A folder —
// including the device root, which an upload into it names as "" — is walked
// and every file under it is indexed. A file is indexed alone. A device with
// no namespace is skipped, and so is the trash.
func indexEventPath(db *sql.DB, registry vfs.Registry, serial, relPath string) {
	fsys, relPath, ok := contentFS(registry, serial, relPath)
	if !ok {
		return
	}
	fi, err := statContentPath(fsys, relPath)
	switch {
	case errors.Is(err, vfs.ErrNotFound):
		return
	case err != nil:
		log.Printf("[content-indexer] stat %s: %v", relPath, err)
		return
	case !fi.IsDir:
		indexContentFile(db, fsys, serial, relPath)
		return
	}

	// One file's cap is indexTimeout. A folder holds many, so the walk has
	// the same bound as a device backfill and stops between files.
	ctx, cancel := context.WithTimeout(context.Background(), backfillTimeout)
	defer cancel()
	walkErr := vfs.Walk(ctx, fsys, relPath, func(info vfs.FileInfo) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if !info.IsDir {
			indexContentFile(db, fsys, serial, info.Path)
		}
		return nil
	})
	if walkErr != nil && !errors.Is(walkErr, vfs.ErrNotFound) {
		log.Printf("[content-indexer] walk %s: %v", relPath, walkErr)
	}
}

// indexMovedPath indexes the file a move landed on. A folder is left alone:
// the rows under it still name the old paths, and walking would index the
// new ones beside them.
func indexMovedPath(db *sql.DB, registry vfs.Registry, serial, relPath string) {
	fsys, relPath, ok := contentFS(registry, serial, relPath)
	if !ok || relPath == "" {
		return
	}
	fi, err := statContentPath(fsys, relPath)
	if err != nil {
		if !errors.Is(err, vfs.ErrNotFound) {
			log.Printf("[content-indexer] stat %s: %v", relPath, err)
		}
		return
	}
	if fi.IsDir {
		return
	}
	indexContentFile(db, fsys, serial, relPath)
}

// statContentPath stats relPath, giving up after indexTimeout.
func statContentPath(fsys vfs.VFS, relPath string) (vfs.FileInfo, error) {
	ctx, cancel := context.WithTimeout(context.Background(), indexTimeout)
	defer cancel()
	return fsys.Stat(ctx, relPath)
}

// contentFS is the files namespace for serial and relPath in canonical form.
// A serial with no namespace, and the trash, have nothing to index.
func contentFS(registry vfs.Registry, serial, relPath string) (vfs.VFS, string, bool) {
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

// indexContentFile indexes one file. A file that is not indexable, or that
// is in the trash, is a no-op inside IndexFile.
func indexContentFile(db *sql.DB, fsys vfs.VFS, serial, relPath string) {
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

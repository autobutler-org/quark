package indexutil

import (
	"context"
	"errors"
	"io/fs"
	"log"
	"maps"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// pageSize is how many files a search reads from the database at a time, and
// batchSize how many rows a walk writes in one transaction.
const (
	pageSize  = 500
	batchSize = 500
)

// Build brings the index in line with every device's files namespace in
// registry: each device is walked and what the walk did not find is dropped,
// as is every device no longer in registry. Searches keep answering from the
// rows already there while it runs.
func (idx *FileIndex) Build(ctx context.Context, registry vfs.Registry) {
	present := vfs.FilesNamespaces(registry)
	for _, serial := range slices.Sorted(maps.Keys(present)) {
		idx.reconcile(ctx, present[serial], serial)
	}
	idx.dropAbsent(ctx, present)
}

// Sync brings the set of indexed devices in line with registry: a device
// whose namespace appeared is walked and added, and one whose namespace is
// gone is dropped. Devices already indexed are left as they are.
func (idx *FileIndex) Sync(ctx context.Context, registry vfs.Registry) {
	present := vfs.FilesNamespaces(registry)
	indexed := make(map[string]bool)
	for _, serial := range idx.serials(ctx) {
		indexed[serial] = true
	}
	for _, serial := range slices.Sorted(maps.Keys(present)) {
		if !indexed[serial] {
			idx.reconcile(ctx, present[serial], serial)
		}
	}
	idx.dropAbsent(ctx, present)
}

// Search returns all indexed files whose Name contains query (case-insensitive).
// If query is empty, returns all files.
// If serials is non-empty, only returns files from those devices.
func (idx *FileIndex) Search(query string, serials map[string]bool) []IndexedFile {
	out := make([]IndexedFile, 0)
	idx.SearchEach(query, serials, func(f IndexedFile) bool {
		out = append(out, f)
		return true
	})
	return out
}

// SearchEach calls visit for each file Search would return, stopping as soon
// as visit returns false, so a caller filtering or capping the matches never
// builds the full list. Devices come in serial order, the internal drive
// first, and on each the files in order of the folder they sit in, then of
// their names, comparing bytes: a folder's files come before those of its
// subfolders (#2817's order, but a folder named "a b" now sorts before "a/c"). The rows are read a page at a time and no connection is held
// while visit runs, so visit may query the database.
func (idx *FileIndex) SearchEach(query string, serials map[string]bool, visit func(IndexedFile) bool) {
	ctx := context.Background()
	order := slices.Sorted(maps.Keys(serials))
	if len(order) == 0 {
		order = idx.serials(ctx)
	}
	lower := strings.ToLower(query)
	for _, serial := range order {
		params := db.ListIndexedFilesPageParams{Serial: serial, Query: lower, Limit: pageSize}
		for {
			page, err := db.SearchIndexedFiles(ctx, idx.database.Db, params)
			if err != nil {
				log.Printf("[file-index] search %q on %q: %v", query, serial, err)
				return
			}
			for _, row := range page {
				if !visit(IndexedFile{
					Name: row.Name, RelPath: joinRel(row.Dir, row.Name), DeviceSerial: serial,
					Size: row.Size, ModTime: time.Unix(0, row.ModTime),
				}) {
					return
				}
			}
			if len(page) < pageSize {
				break
			}
			params.AfterDir, params.AfterName = page[len(page)-1].Dir, page[len(page)-1].Name
		}
	}
}

// HandleAdd adds a file to the index with its size and mtime (Unix nanoseconds),
// or updates them for a file the index already holds. It takes the place of a
// folder at that path, and of a file at any folder above it.
func (idx *FileIndex) HandleAdd(serial, relPath string, size, mtime int64) {
	parts := splitRel(relPath)
	if len(parts) == 0 || isInternalPath(parts) {
		return
	}
	stamp := idx.stamp()
	idx.write(context.Background(), "add "+relPath, func(q db.Querier) error {
		if err := ensureFolders(q, serial, parts[:len(parts)-1], stamp); err != nil {
			return err
		}
		if err := q.DeleteIndexedDescendants(context.Background(), descendantsParams(serial, parts)); err != nil {
			return err
		}
		return q.UpsertIndexedEntry(context.Background(), entry(serial, parts, false, size, mtime, stamp))
	})
}

// FolderSize returns the sum of every file's size under the folder at relPath
// on the device with serial, the root for "", and false when the index holds
// no such folder.
//
// ponytail: sums the rows under the folder on every call, so listing a root
// whose folders hold a million files reads a million sizes; remember totals
// per folder if that listing shows up slow.
func (idx *FileIndex) FolderSize(serial, relPath string) (int64, bool) {
	ctx := context.Background()
	parts := splitRel(relPath)
	if len(parts) == 0 {
		row, err := idx.database.Queries.SumIndexedSerial(ctx, serial)
		if err != nil {
			log.Printf("[file-index] size of %q: %v", serial, err)
		}
		return row.Total, row.Entries > 0
	}
	d := descendantsParams(serial, parts)
	row, err := idx.database.Queries.SumIndexedFolder(ctx, db.SumIndexedFolderParams{
		Serial: serial, Parent: joinParts(parts[:len(parts)-1]), Name: parts[len(parts)-1],
		Path: d.Path, DirFrom: d.DirFrom, DirTo: d.DirTo,
	})
	if err != nil {
		log.Printf("[file-index] size of %q on %q: %v", relPath, serial, err)
	}
	return row.Total, row.Entries > 0
}

// HandleDelete removes a file or a folder, and everything in the folder,
// from the index.
func (idx *FileIndex) HandleDelete(serial, relPath string) {
	parts := splitRel(relPath)
	if len(parts) == 0 {
		return
	}
	idx.write(context.Background(), "delete "+relPath, func(q db.Querier) error {
		_, err := q.DeleteIndexedPath(context.Background(), pathParams(serial, parts))
		return err
	})
}

// HandleMove renames a file or a folder in the index; a folder takes
// everything in it along. A path the index never held is read from fsys, the
// device's namespace, at its new location instead.
func (idx *FileIndex) HandleMove(ctx context.Context, fsys vfs.VFS, serial, oldRelPath, newRelPath string) {
	oldParts, newParts := splitRel(oldRelPath), splitRel(newRelPath)
	if len(oldParts) == 0 || len(newParts) == 0 || slices.Equal(oldParts, newParts) {
		return
	}
	stamp := idx.stamp()
	moved := false
	idx.write(ctx, "move "+oldRelPath, func(q db.Querier) error {
		moved = false
		if isInternalPath(newParts) {
			// A move into the trash only drops it.
			n, err := q.DeleteIndexedPath(ctx, pathParams(serial, oldParts))
			moved = n > 0
			return err
		}
		if _, err := q.DeleteIndexedPath(ctx, pathParams(serial, newParts)); err != nil {
			return err
		}
		from := descendantsParams(serial, oldParts)
		under, err := q.MoveIndexedDescendants(ctx, db.MoveIndexedDescendantsParams{
			NewPath: joinParts(newParts), Serial: serial, Path: from.Path, DirFrom: from.DirFrom, DirTo: from.DirTo,
		})
		if err != nil {
			return err
		}
		self, err := q.RenameIndexedEntry(ctx, db.RenameIndexedEntryParams{
			NewDir: joinParts(newParts[:len(newParts)-1]), NewName: newParts[len(newParts)-1],
			NewSearchName: strings.ToLower(newParts[len(newParts)-1]),
			Serial:        serial, Dir: joinParts(oldParts[:len(oldParts)-1]), Name: oldParts[len(oldParts)-1],
		})
		if err != nil {
			return err
		}
		moved = under+self > 0
		if !moved {
			return nil
		}
		return ensureFolders(q, serial, newParts[:len(newParts)-1], stamp)
	})
	if !moved {
		idx.HandleRescan(ctx, fsys, serial, newRelPath)
	}
}

// HandleRescan brings the index for relPath back in line with fsys, the
// device's namespace, for the events that name a folder without saying what
// changed in it: an upload names the folder its files landed in, a new or
// restored folder names itself. A file is added; a folder's direct contents
// replace what the index holds for it, and any subfolder the index has not
// seen is walked whole; a path gone from the namespace is dropped. Folders the
// index already holds below the first level are not reread, so an upload into
// a large tree costs one directory read.
func (idx *FileIndex) HandleRescan(ctx context.Context, fsys vfs.VFS, serial, relPath string) {
	parts := splitRel(relPath)
	if isInternalPath(parts) {
		return
	}
	if len(parts) > 0 {
		info, err := fsys.Stat(ctx, relPath)
		switch {
		case errors.Is(err, vfs.ErrNotFound):
			idx.HandleDelete(serial, relPath)
			return
		case err != nil:
			return
		case !info.IsDir:
			idx.HandleAdd(serial, relPath, info.Size, info.ModTime.UnixNano())
			return
		}
	}

	dir := joinParts(parts)
	names, err := idx.database.Queries.ListIndexedChildFolders(ctx, db.ListIndexedChildFoldersParams{Serial: serial, Dir: dir})
	if err != nil {
		log.Printf("[file-index] rescan %q on %q: %v", relPath, serial, err)
		return
	}
	held := make(map[string]bool, len(names))
	for _, name := range names {
		held[name] = true
	}
	stamp := idx.stamp()
	err = idx.walk(ctx, fsys, serial, parts, held, stamp)
	if errors.Is(err, vfs.ErrNotFound) {
		idx.HandleDelete(serial, relPath)
		return
	}
	if err != nil {
		return
	}
	idx.write(ctx, "rescan "+relPath, func(q db.Querier) error {
		if err := ensureFolders(q, serial, parts, stamp); err != nil {
			return err
		}
		gone, err := q.ListStaleIndexedChildren(ctx, db.ListStaleIndexedChildrenParams{Serial: serial, Dir: dir, IndexedAt: stamp})
		if err != nil {
			return err
		}
		for _, name := range gone {
			if _, err := q.DeleteIndexedPath(ctx, pathParams(serial, append(slices.Clone(parts), name))); err != nil {
				return err
			}
		}
		return nil
	})
}

// BuildAndWatch subscribes to the event bus, brings the index in line with
// every device namespace in the registry, then starts a background goroutine
// that keeps the index current on upload, delete, move and new folder events,
// rebuilding it whole on a resync. An event for a device with no registered
// namespace is dropped. The server runs it off the path to binding its
// listener: until it finishes, searches answer from what the index held when
// the last process stopped.
//
// Call this once at startup. The goroutine runs until the event bus channel
// is closed (i.e. when the bus is shut down).
func (idx *FileIndex) BuildAndWatch(params BuildAndWatchParams) {
	ctx := params.Ctx
	if ctx == nil {
		ctx = context.Background()
	}
	// Subscribe before the walk, so no event published while it runs is
	// missed.
	events, unsub := params.Bus.Subscribe("file-index")
	idx.Build(ctx, params.Registry)
	if params.Storage != nil {
		params.Storage.OnDevicesChanged(func() { go idx.Sync(ctx, params.Registry) })
	}
	go func() {
		defer unsub()
		for evt := range events {
			idx.handleEvent(ctx, params.Registry, evt)
		}
	}()
}

// handleEvent applies one file event to the index.
func (idx *FileIndex) handleEvent(ctx context.Context, registry vfs.Registry, evt eventbus.Event) {
	// A resync replaces events this subscriber missed, so nothing short of
	// a rebuild is known to be current.
	if evt.Kind == eventbus.EventResync {
		idx.Build(ctx, registry)
		return
	}
	fsys, ok := registry.Get(vfs.FilesNamespace(evt.DeviceSerial))
	if !ok {
		return
	}
	switch evt.Kind {
	case eventbus.EventUpload, eventbus.EventNewFolder:
		idx.HandleRescan(ctx, fsys, evt.DeviceSerial, evt.Path)
	case eventbus.EventDelete:
		idx.HandleDelete(evt.DeviceSerial, evt.Path)
	case eventbus.EventMove:
		idx.HandleMove(ctx, fsys, evt.DeviceSerial, evt.Path, evt.NewPath)
	}
}

// reconcile walks the device with serial whole and drops every row the walk
// did not write. A walk that fails part way keeps only what it read, as the
// in-memory index did.
func (idx *FileIndex) reconcile(ctx context.Context, fsys vfs.VFS, serial string) {
	stamp := idx.stamp()
	_ = idx.walk(ctx, fsys, serial, nil, nil, stamp)
	idx.write(ctx, "reconcile", func(q db.Querier) error {
		return q.DeleteStaleIndexedSerial(ctx, db.DeleteStaleIndexedSerialParams{Serial: serial, IndexedAt: stamp})
	})
}

// walk writes every entry under the folder at parts in fsys, stamped with
// stamp, a batch per transaction. A subfolder directly in it named in held is
// written but not walked: its rows are kept as they are. One held name that is
// now a file loses what the index held under it.
func (idx *FileIndex) walk(ctx context.Context, fsys vfs.VFS, serial string, parts []string, held map[string]bool, stamp int64) error {
	var batch []db.UpsertIndexedEntryParams
	var dropped [][]string
	flush := func() {
		if len(batch) == 0 && len(dropped) == 0 {
			return
		}
		idx.write(ctx, "walk", func(q db.Querier) error {
			for _, p := range dropped {
				if err := q.DeleteIndexedDescendants(ctx, descendantsParams(serial, p)); err != nil {
					return err
				}
			}
			for _, row := range batch {
				if err := q.UpsertIndexedEntry(ctx, row); err != nil {
					return err
				}
			}
			return nil
		})
		batch, dropped = batch[:0], dropped[:0]
	}
	depth := len(parts)
	err := vfs.Walk(ctx, fsys, joinParts(parts), func(fi vfs.FileInfo) error {
		rel := splitRel(fi.Path)
		if len(rel) <= depth {
			return nil
		}
		if isInternalPath(rel[depth:]) {
			if fi.IsDir {
				return fs.SkipDir
			}
			return nil
		}
		size := fi.Size
		if fi.IsDir {
			size = 0
		}
		batch = append(batch, entry(serial, rel, fi.IsDir, size, fi.ModTime.UnixNano(), stamp))
		direct := len(rel) == depth+1 && held[rel[depth]]
		if direct && !fi.IsDir {
			dropped = append(dropped, rel)
		}
		if len(batch) >= batchSize {
			flush()
		}
		if direct && fi.IsDir {
			return fs.SkipDir
		}
		return nil
	})
	flush()
	return err
}

// dropAbsent drops every device not in present.
func (idx *FileIndex) dropAbsent(ctx context.Context, present map[string]vfs.VFS) {
	for _, serial := range idx.serials(ctx) {
		if _, ok := present[serial]; !ok {
			idx.write(ctx, "drop device", func(q db.Querier) error { return q.DeleteIndexedSerial(ctx, serial) })
		}
	}
}

// serials lists the devices the index holds rows for, in order.
func (idx *FileIndex) serials(ctx context.Context) []string {
	serials, err := idx.database.Queries.ListIndexedSerials(ctx)
	if err != nil {
		log.Printf("[file-index] list devices: %v", err)
	}
	return serials
}

// write runs fn in one transaction, logging a failure: an index that missed a
// change is brought back in line by the next reconcile.
func (idx *FileIndex) write(ctx context.Context, what string, fn func(db.Querier) error) {
	if err := db.InTx(ctx, idx.database.Db, fn); err != nil {
		log.Printf("[file-index] %s: %v", what, err)
	}
}

// stamp returns an indexed_at later than any this index handed out before.
func (idx *FileIndex) stamp() int64 {
	for {
		last, now := idx.lastStamp.Load(), time.Now().UnixNano()
		if now <= last {
			now = last + 1
		}
		if idx.lastStamp.CompareAndSwap(last, now) {
			return now
		}
	}
}

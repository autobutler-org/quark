package indexutil

import (
	"context"
	"errors"
	"maps"
	"slices"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// Build walks every device's files namespace in registry and replaces the
// index with what it finds. The walks run before the lock is taken, so
// searches keep answering from the old index while they do.
func (idx *FileIndex) Build(ctx context.Context, registry vfs.Registry) {
	roots := make(map[string]*indexDir)
	for serial, fsys := range vfs.FilesNamespaces(registry) {
		roots[serial] = scanTree(ctx, fsys, "")
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.roots = roots
}

// Sync brings the set of indexed devices in line with registry: a device
// whose namespace appeared is walked and added, and one whose namespace is
// gone is dropped. Devices already indexed are left as they are.
func (idx *FileIndex) Sync(ctx context.Context, registry vfs.Registry) {
	present := vfs.FilesNamespaces(registry)
	idx.mu.RLock()
	var missing []string
	for serial := range present {
		if idx.roots[serial] == nil {
			missing = append(missing, serial)
		}
	}
	idx.mu.RUnlock()
	added := make(map[string]*indexDir, len(missing))
	for _, serial := range missing {
		added[serial] = scanTree(ctx, present[serial], "")
	}
	idx.syncRoots(present, added)
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
// first, and each folder's files, then its subfolders, in name order. visit
// runs under the index's read lock and must not call back into the index.
func (idx *FileIndex) SearchEach(query string, serials map[string]bool, visit func(IndexedFile) bool) {
	match := newNameMatcher(query)
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	for _, serial := range slices.Sorted(maps.Keys(idx.roots)) {
		if len(serials) > 0 && !serials[serial] {
			continue
		}
		more := idx.roots[serial].collect("", match, func(name, relPath string) bool {
			return visit(IndexedFile{Name: name, RelPath: relPath, DeviceSerial: serial})
		})
		if !more {
			return
		}
	}
}

// HandleAdd adds a file to the index.
func (idx *FileIndex) HandleAdd(serial, relPath string) {
	parts := splitRel(relPath)
	if len(parts) == 0 || isInternalPath(parts) {
		return
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.root(serial).ensure(parts[:len(parts)-1]).putFile(parts[len(parts)-1])
}

// HandleDelete removes a file or a folder, and everything in the folder,
// from the index.
func (idx *FileIndex) HandleDelete(serial, relPath string) {
	parts := splitRel(relPath)
	if len(parts) == 0 {
		return
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	if root := idx.roots[serial]; root != nil {
		root.lookup(parts[:len(parts)-1]).remove(parts[len(parts)-1])
	}
}

// HandleMove renames a file or a folder in the index; a folder takes
// everything in it along. A path the index never held is read from fsys, the
// device's namespace, at its new location instead.
func (idx *FileIndex) HandleMove(ctx context.Context, fsys vfs.VFS, serial, oldRelPath, newRelPath string) {
	oldParts, newParts := splitRel(oldRelPath), splitRel(newRelPath)
	if len(oldParts) == 0 || len(newParts) == 0 {
		return
	}
	if !idx.reattach(serial, oldParts, newParts) {
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
			idx.HandleAdd(serial, relPath)
			return
		}
	}

	// The subfolders the index already holds are not walked again; the rest
	// are walked whole, before the write lock is taken.
	idx.mu.RLock()
	var held map[string]bool
	if root := idx.roots[serial]; root != nil {
		if known := root.lookup(parts); known != nil {
			held = make(map[string]bool, len(known.dirs))
			for _, dir := range known.dirs {
				held[dir.name] = true
			}
		}
	}
	idx.mu.RUnlock()
	fresh, err := scanFolder(ctx, fsys, parts, held)
	if errors.Is(err, vfs.ErrNotFound) {
		idx.HandleDelete(serial, relPath)
		return
	}
	if err != nil {
		return
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(serial)
	var parent *indexDir
	old := root
	if len(parts) > 0 {
		parent = root.ensure(parts[:len(parts)-1])
		old = parent.child(parts[len(parts)-1])
	}
	// A held folder a rebuild dropped in between stays empty.
	for i, dir := range fresh.dirs {
		if !held[dir.name] {
			continue
		}
		if kept := old.child(dir.name); kept != nil {
			fresh.dirs[i] = kept
		}
	}
	if parent == nil {
		idx.roots[serial] = fresh
	} else {
		parent.putDir(parts[len(parts)-1], fresh)
	}
}

// BuildAndWatch builds the index from every device namespace in the
// registry, then starts a background goroutine that subscribes to the event
// bus and keeps the index current on upload, delete, move and new folder
// events, rebuilding it whole on a resync. An event for a device with no
// registered namespace is dropped.
//
// Call this once at startup. The goroutine runs until the event bus channel
// is closed (i.e. when the bus is shut down).
func (idx *FileIndex) BuildAndWatch(params BuildAndWatchParams) {
	ctx := params.Ctx
	if ctx == nil {
		ctx = context.Background()
	}
	idx.Build(ctx, params.Registry)
	if params.Storage != nil {
		params.Storage.OnDevicesChanged(func() { go idx.Sync(ctx, params.Registry) })
	}

	// Subscribe before returning, so no event published after the build is
	// missed while the goroutine starts.
	events, unsub := params.Bus.Subscribe("file-index")
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

// reattach moves the node at oldParts to newParts, reporting whether there was
// one. A move into an internal folder, the trash, only drops it.
func (idx *FileIndex) reattach(serial string, oldParts, newParts []string) bool {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(serial)
	oldParent, oldName := root.lookup(oldParts[:len(oldParts)-1]), oldParts[len(oldParts)-1]
	if oldParent == nil {
		return false
	}
	_, isFile := oldParent.findFile(oldName)
	dir := oldParent.child(oldName)
	if !isFile && dir == nil {
		return false
	}
	oldParent.remove(oldName)
	if isInternalPath(newParts) {
		return true
	}
	newParent, newName := root.ensure(newParts[:len(newParts)-1]), newParts[len(newParts)-1]
	if isFile {
		newParent.putFile(newName)
	} else {
		newParent.putDir(newName, dir)
	}
	return true
}

// syncRoots drops the devices not in present and adds the walked ones not
// indexed yet.
func (idx *FileIndex) syncRoots(present map[string]vfs.VFS, added map[string]*indexDir) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	for serial := range idx.roots {
		if _, ok := present[serial]; !ok {
			delete(idx.roots, serial)
		}
	}
	for serial, dir := range added {
		if idx.roots[serial] == nil {
			idx.roots[serial] = dir
		}
	}
}

// root returns the tree for serial, creating it. Callers hold the write lock.
func (idx *FileIndex) root(serial string) *indexDir {
	root := idx.roots[serial]
	if root == nil {
		root = &indexDir{}
		idx.roots[serial] = root
	}
	return root
}

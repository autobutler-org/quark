package indexutil

// The index as it stood before #2760: a map per folder. The equivalence
// tests in file_index_equiv_test.go hold the compact index to its results.

import (
	"context"
	"os"
	"strings"
	"sync"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// refIndex is a thread-safe in-memory index of all files across managed devices.
// It reads the disk under each namespace's host path directly, so it shares
// no walking code with FileIndex.
//
// Each device is a tree of folders, so an event naming a folder reaches
// everything under it in one step: a delete unlinks the folder's node and a
// move reattaches it, whatever it holds (#2754). Paths are never stored; a
// search rebuilds them on the way down.
type refIndex struct {
	mu    sync.RWMutex
	roots map[string]*refDir // key: device serial
}

// refDir is one folder: the names of the files directly in it and its
// subfolders. Either map is nil until something is put in it.
type refDir struct {
	files map[string]struct{}
	dirs  map[string]*refDir
}

// newRefIndex creates and returns an empty refIndex.
func newRefIndex() *refIndex {
	return &refIndex{roots: make(map[string]*refDir)}
}

// Build reads every device namespace's tree from disk.
func (idx *refIndex) Build(ctx context.Context, registry vfs.Registry) {
	roots := make(map[string]*refDir)
	for serial, fsys := range vfs.FilesNamespaces(registry) {
		roots[serial] = refScanDir(refHostPath(ctx, fsys, ""))
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.roots = roots
}

// refHostPath is where path in fsys sits on disk.
func refHostPath(ctx context.Context, fsys vfs.VFS, path string) string {
	abs, err := fsys.(vfs.HostPather).HostPath(ctx, path)
	if err != nil {
		return ""
	}
	return abs
}

// Search returns all indexed files whose Name contains query (case-insensitive).
// If query is empty, returns all files.
// If serials is non-empty, only returns files from those devices.
func (idx *refIndex) Search(query string, serials map[string]bool) []IndexedFile {
	out := make([]IndexedFile, 0)
	idx.SearchEach(query, serials, func(f IndexedFile) bool {
		out = append(out, f)
		return true
	})
	return out
}

// SearchEach calls visit for each file Search would return, stopping as soon
// as visit returns false, so a caller filtering or capping the matches never
// builds the full list. visit runs under the index's read lock and must not
// call back into the index.
func (idx *refIndex) SearchEach(query string, serials map[string]bool, visit func(IndexedFile) bool) {
	lq := strings.ToLower(query)
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	for serial, root := range idx.roots {
		if len(serials) > 0 && !serials[serial] {
			continue
		}
		more := root.collect("", func(name, relPath string) bool {
			if query != "" && !strings.Contains(strings.ToLower(name), lq) {
				return true
			}
			return visit(IndexedFile{Name: name, RelPath: relPath, DeviceSerial: serial})
		})
		if !more {
			return
		}
	}
}

// HandleAdd adds or updates a file in the index.
func (idx *refIndex) HandleAdd(serial, relPath string) {
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
func (idx *refIndex) HandleDelete(serial, relPath string) {
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
// everything in it along. A path the index never held is read from disk at
// its new location instead.
func (idx *refIndex) HandleMove(ctx context.Context, fsys vfs.VFS, serial, oldRelPath, newRelPath string) {
	oldParts, newParts := splitRel(oldRelPath), splitRel(newRelPath)
	if len(oldParts) == 0 || len(newParts) == 0 {
		return
	}
	if !idx.reattach(serial, oldParts, newParts) {
		idx.HandleRescan(ctx, fsys, serial, newRelPath)
	}
}

// reattach moves the node at oldParts to newParts, reporting whether there was
// one. A move into an internal folder, the trash, only drops it.
func (idx *refIndex) reattach(serial string, oldParts, newParts []string) bool {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(serial)
	oldParent, oldName := root.lookup(oldParts[:len(oldParts)-1]), oldParts[len(oldParts)-1]
	if oldParent == nil {
		return false
	}
	_, isFile := oldParent.files[oldName]
	dir := oldParent.dirs[oldName]
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

// HandleRescan brings the index for relPath back in line with the disk, for
// the events that name a folder without saying what changed in it: an upload
// names the folder its files landed in, a new or restored folder names
// itself. A file is added; a folder's direct contents replace what the index
// holds for it, and any subfolder the index has not seen is walked whole; a
// path gone from disk is dropped. Folders the index already holds below the
// first level are not reread, so an upload into a large tree costs one
// directory read.
func (idx *refIndex) HandleRescan(ctx context.Context, fsys vfs.VFS, serial, relPath string) {
	parts := splitRel(relPath)
	if isInternalPath(parts) {
		return
	}
	abs := refHostPath(ctx, fsys, strings.Join(parts, "/"))
	info, err := os.Stat(abs)
	switch {
	case err != nil:
		idx.HandleDelete(serial, relPath)
		return
	case !info.IsDir():
		idx.HandleAdd(serial, relPath)
		return
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		return
	}

	// Walk the subfolders the index lacks before taking the write lock.
	idx.mu.RLock()
	var known *refDir
	if root := idx.roots[serial]; root != nil {
		known = root.lookup(parts)
	}
	fresh := &refDir{}
	for _, entry := range entries {
		name := entry.Name()
		switch {
		case storageutil.IsInternalName(name):
		case !entry.IsDir():
			fresh.putFile(name)
		case known != nil && known.dirs[name] != nil:
			fresh.putDir(name, nil) // kept from the index below
		default:
			fresh.putDir(name, &refDir{})
		}
	}
	idx.mu.RUnlock()
	for name, dir := range fresh.dirs {
		if dir != nil {
			fresh.dirs[name] = refScanDir(abs + "/" + name)
		}
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(serial)
	if len(parts) == 0 {
		fresh.adopt(root)
		idx.roots[serial] = fresh
		return
	}
	parent := root.ensure(parts[:len(parts)-1])
	fresh.adopt(parent.dirs[parts[len(parts)-1]])
	parent.putDir(parts[len(parts)-1], fresh)
}

// root returns the tree for serial, creating it. Callers hold the write lock.
func (idx *refIndex) root(serial string) *refDir {
	root := idx.roots[serial]
	if root == nil {
		root = &refDir{}
		idx.roots[serial] = root
	}
	return root
}

// refScanDir reads the tree under abs from disk, skipping internal names.
func refScanDir(abs string) *refDir {
	dir := &refDir{}
	entries, err := os.ReadDir(abs)
	if err != nil {
		return dir
	}
	for _, entry := range entries {
		switch name := entry.Name(); {
		case storageutil.IsInternalName(name):
		case entry.IsDir():
			dir.putDir(name, refScanDir(abs+"/"+name))
		default:
			dir.putFile(name)
		}
	}
	return dir
}

// lookup returns the folder at parts, nil when the index has none.
func (d *refDir) lookup(parts []string) *refDir {
	for _, seg := range parts {
		if d == nil {
			return nil
		}
		d = d.dirs[seg]
	}
	return d
}

// ensure returns the folder at parts, creating any that are missing.
func (d *refDir) ensure(parts []string) *refDir {
	for _, seg := range parts {
		next := d.dirs[seg]
		if next == nil {
			next = &refDir{}
			d.putDir(seg, next)
		}
		d = next
	}
	return d
}

// putFile records a file; a name is a file or a folder, never both.
func (d *refDir) putFile(name string) {
	delete(d.dirs, name)
	if d.files == nil {
		d.files = make(map[string]struct{})
	}
	d.files[name] = struct{}{}
}

// putDir records a folder.
func (d *refDir) putDir(name string, dir *refDir) {
	delete(d.files, name)
	if d.dirs == nil {
		d.dirs = make(map[string]*refDir)
	}
	d.dirs[name] = dir
}

// remove drops a file or a folder with everything under it. A nil d holds
// nothing to remove.
func (d *refDir) remove(name string) {
	if d != nil {
		delete(d.files, name)
		delete(d.dirs, name)
	}
}

// adopt fills the subfolders HandleRescan left nil with the nodes old already
// holds for them. One a rebuild dropped in between starts out empty.
func (d *refDir) adopt(old *refDir) {
	for name, dir := range d.dirs {
		if dir == nil {
			if dir = old.lookup([]string{name}); dir == nil {
				dir = &refDir{}
			}
			d.dirs[name] = dir
		}
	}
}

// collect calls visit for every file under d with its path relative to the
// tree's root, which prefix is the path of d plus a trailing slash. It stops,
// and reports false, once visit does.
func (d *refDir) collect(prefix string, visit func(name, relPath string) bool) bool {
	for name := range d.files {
		if !visit(name, prefix+name) {
			return false
		}
	}
	for name, dir := range d.dirs {
		if !dir.collect(prefix+name+"/", visit) {
			return false
		}
	}
	return true
}

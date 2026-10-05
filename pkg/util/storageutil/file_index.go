package storageutil

import (
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"sync"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// IndexedFile is a lightweight record stored in the FileIndex.
type IndexedFile struct {
	Name         string // filename only (no directory)
	RelPath      string // relative path from FilesDir root (e.g. "docs/notes.txt")
	FilesDir     string // absolute path to the device's FilesDir
	DeviceSerial string // empty = internal
}

// FileIndex is a thread-safe in-memory index of all files across managed devices.
// It is built once at startup and updated incrementally via HandleEvent.
//
// Each device is a tree of folders, so an event naming a folder reaches
// everything under it in one step: a delete unlinks the folder's node and a
// move reattaches it, whatever it holds (#2754). Paths are never stored; a
// search rebuilds them on the way down.
type FileIndex struct {
	mu    sync.RWMutex
	roots map[string]*indexRoot // key: FilesDir
}

// indexRoot is one device's tree.
type indexRoot struct {
	serial string // empty = internal
	dir    *indexDir
}

// indexDir is one folder: the names of the files directly in it and its
// subfolders. Either map is nil until something is put in it.
type indexDir struct {
	files map[string]struct{}
	dirs  map[string]*indexDir
}

// NewFileIndex creates and returns an empty FileIndex.
func NewFileIndex() *FileIndex {
	return &FileIndex{roots: make(map[string]*indexRoot)}
}

// Build walks all managed devices and populates the index. The walk runs
// before the lock is taken, so searches keep answering from the old index
// while it does.
func (idx *FileIndex) Build(devices []ManagedDevice) {
	roots := make(map[string]*indexRoot, len(devices))
	for _, dev := range devices {
		serial := ""
		if dev.UsbInfo != nil {
			serial = dev.UsbInfo.GetSerial()
		}
		roots[dev.FilesDir] = &indexRoot{serial: serial, dir: scanDir(dev.FilesDir)}
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.roots = roots
}

// Search returns all indexed files whose Name contains query (case-insensitive).
// If query is empty, returns all files.
// If serials is non-empty, only returns files from those devices.
func (idx *FileIndex) Search(query string, serials map[string]bool) []IndexedFile {
	lq := strings.ToLower(query)
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	out := make([]IndexedFile, 0)
	for filesDir, root := range idx.roots {
		if len(serials) > 0 && !serials[root.serial] {
			continue
		}
		root.dir.collect("", func(name, relPath string) {
			if query == "" || strings.Contains(strings.ToLower(name), lq) {
				out = append(out, IndexedFile{Name: name, RelPath: relPath, FilesDir: filesDir, DeviceSerial: root.serial})
			}
		})
	}
	return out
}

// HandleAdd adds or updates a file in the index.
func (idx *FileIndex) HandleAdd(filesDir, relPath, serial string) {
	parts := splitRel(relPath)
	if len(parts) == 0 || isInternalPath(parts) {
		return
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.root(filesDir, serial).dir.ensure(parts[:len(parts)-1]).putFile(parts[len(parts)-1])
}

// HandleDelete removes a file or a folder, and everything in the folder,
// from the index.
func (idx *FileIndex) HandleDelete(filesDir, relPath string) {
	parts := splitRel(relPath)
	if len(parts) == 0 {
		return
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	if root := idx.roots[filesDir]; root != nil {
		root.dir.lookup(parts[:len(parts)-1]).remove(parts[len(parts)-1])
	}
}

// HandleMove renames a file or a folder in the index; a folder takes
// everything in it along. A path the index never held is read from disk at
// its new location instead.
func (idx *FileIndex) HandleMove(filesDir, oldRelPath, newRelPath, serial string) {
	oldParts, newParts := splitRel(oldRelPath), splitRel(newRelPath)
	if len(oldParts) == 0 || len(newParts) == 0 {
		return
	}
	if !idx.reattach(filesDir, oldParts, newParts, serial) {
		idx.HandleRescan(filesDir, newRelPath, serial)
	}
}

// reattach moves the node at oldParts to newParts, reporting whether there was
// one. A move into an internal folder, the trash, only drops it.
func (idx *FileIndex) reattach(filesDir string, oldParts, newParts []string, serial string) bool {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(filesDir, serial)
	oldParent, oldName := root.dir.lookup(oldParts[:len(oldParts)-1]), oldParts[len(oldParts)-1]
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
	newParent, newName := root.dir.ensure(newParts[:len(newParts)-1]), newParts[len(newParts)-1]
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
func (idx *FileIndex) HandleRescan(filesDir, relPath, serial string) {
	parts := splitRel(relPath)
	if isInternalPath(parts) {
		return
	}
	abs := filepath.Join(filesDir, filepath.FromSlash(strings.Join(parts, "/")))
	info, err := os.Stat(abs)
	switch {
	case err != nil:
		idx.HandleDelete(filesDir, relPath)
		return
	case !info.IsDir():
		idx.HandleAdd(filesDir, relPath, serial)
		return
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		return
	}

	// Walk the subfolders the index lacks before taking the write lock.
	idx.mu.RLock()
	var known *indexDir
	if root := idx.roots[filesDir]; root != nil {
		known = root.dir.lookup(parts)
	}
	fresh := &indexDir{}
	for _, entry := range entries {
		name := entry.Name()
		switch {
		case IsInternalName(name):
		case !entry.IsDir():
			fresh.putFile(name)
		case known != nil && known.dirs[name] != nil:
			fresh.putDir(name, nil) // kept from the index below
		default:
			fresh.putDir(name, &indexDir{})
		}
	}
	idx.mu.RUnlock()
	for name, dir := range fresh.dirs {
		if dir != nil {
			fresh.dirs[name] = scanDir(filepath.Join(abs, name))
		}
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(filesDir, serial)
	if len(parts) == 0 {
		fresh.adopt(root.dir)
		root.dir = fresh
		return
	}
	parent := root.dir.ensure(parts[:len(parts)-1])
	fresh.adopt(parent.dirs[parts[len(parts)-1]])
	parent.putDir(parts[len(parts)-1], fresh)
}

// root returns the tree for filesDir, creating it, and records its serial.
// Callers hold the write lock.
func (idx *FileIndex) root(filesDir, serial string) *indexRoot {
	root := idx.roots[filesDir]
	if root == nil {
		root = &indexRoot{dir: &indexDir{}}
		idx.roots[filesDir] = root
	}
	root.serial = serial
	return root
}

// scanDir reads the tree under abs from disk, skipping internal names.
func scanDir(abs string) *indexDir {
	dir := &indexDir{}
	entries, err := os.ReadDir(abs)
	if err != nil {
		return dir
	}
	for _, entry := range entries {
		switch name := entry.Name(); {
		case IsInternalName(name):
		case entry.IsDir():
			dir.putDir(name, scanDir(filepath.Join(abs, name)))
		default:
			dir.putFile(name)
		}
	}
	return dir
}

// splitRel turns a slash-separated relative path into its segments, nil for
// the root. Events carry paths with and without a leading slash.
func splitRel(relPath string) []string {
	clean := strings.Trim(path.Clean("/"+filepath.ToSlash(relPath)), "/")
	if clean == "" {
		return nil
	}
	return strings.Split(clean, "/")
}

// isInternalPath reports whether any segment is an internal name, which the
// index never holds.
func isInternalPath(parts []string) bool {
	return slices.ContainsFunc(parts, IsInternalName)
}

// lookup returns the folder at parts, nil when the index has none.
func (d *indexDir) lookup(parts []string) *indexDir {
	for _, seg := range parts {
		if d == nil {
			return nil
		}
		d = d.dirs[seg]
	}
	return d
}

// ensure returns the folder at parts, creating any that are missing.
func (d *indexDir) ensure(parts []string) *indexDir {
	for _, seg := range parts {
		next := d.dirs[seg]
		if next == nil {
			next = &indexDir{}
			d.putDir(seg, next)
		}
		d = next
	}
	return d
}

// putFile records a file; a name is a file or a folder, never both.
func (d *indexDir) putFile(name string) {
	delete(d.dirs, name)
	if d.files == nil {
		d.files = make(map[string]struct{})
	}
	d.files[name] = struct{}{}
}

// putDir records a folder.
func (d *indexDir) putDir(name string, dir *indexDir) {
	delete(d.files, name)
	if d.dirs == nil {
		d.dirs = make(map[string]*indexDir)
	}
	d.dirs[name] = dir
}

// remove drops a file or a folder with everything under it. A nil d holds
// nothing to remove.
func (d *indexDir) remove(name string) {
	if d != nil {
		delete(d.files, name)
		delete(d.dirs, name)
	}
}

// adopt fills the subfolders HandleRescan left nil with the nodes old already
// holds for them. One a rebuild dropped in between starts out empty.
func (d *indexDir) adopt(old *indexDir) {
	for name, dir := range d.dirs {
		if dir == nil {
			if dir = old.lookup([]string{name}); dir == nil {
				dir = &indexDir{}
			}
			d.dirs[name] = dir
		}
	}
}

// collect calls visit for every file under d with its path relative to the
// tree's root, which prefix is the path of d plus a trailing slash.
func (d *indexDir) collect(prefix string, visit func(name, relPath string)) {
	for name := range d.files {
		visit(name, prefix+name)
	}
	for name, dir := range d.dirs {
		dir.collect(prefix+name+"/", visit)
	}
}

// GetManagedDevicesFunc is the signature of StorageService.GetManagedDevices,
// accepted by Watch so the index doesn't depend on StorageService directly.
type GetManagedDevicesFunc func() ([]ManagedDevice, error)

// BuildAndWatch builds the index from the current filesystem state, then
// starts a background goroutine that subscribes to the event bus and keeps
// the index current on upload/delete/move/new_folder events, rebuilding it
// whole on a resync.
//
// Call this once at startup. The goroutine runs until the event bus channel
// is closed (i.e. when the bus is shut down).
func (idx *FileIndex) BuildAndWatch(bus *eventbus.Bus, getDevices GetManagedDevicesFunc) {
	if devices, err := getDevices(); err == nil {
		idx.Build(devices)
	}

	// Subscribe before returning, so no event published after the build is
	// missed while the goroutine starts.
	events, unsub := bus.Subscribe("file-index")
	go func() {
		defer unsub()
		for evt := range events {
			devices, err := getDevices()
			if err != nil {
				continue
			}
			// A resync replaces events this subscriber missed, so nothing
			// short of a rebuild is known to be current.
			if evt.Kind == eventbus.EventResync {
				idx.Build(devices)
				continue
			}
			filesDir, serial := resolveDevice(devices, evt.DeviceSerial)
			if filesDir == "" {
				continue
			}
			switch evt.Kind {
			case eventbus.EventUpload, eventbus.EventNewFolder:
				idx.HandleRescan(filesDir, evt.Path, serial)
			case eventbus.EventDelete:
				idx.HandleDelete(filesDir, evt.Path)
			case eventbus.EventMove:
				idx.HandleMove(filesDir, evt.Path, evt.NewPath, serial)
			}
		}
	}()
}

// resolveDevice finds the FilesDir and serial for the given sourceSerial.
// If sourceSerial is empty or no USB device matches, falls back to the
// internal (non-USB) device.
func resolveDevice(devices []ManagedDevice, sourceSerial string) (filesDir, serial string) {
	for _, d := range devices {
		s := ""
		if d.UsbInfo != nil {
			s = d.UsbInfo.GetSerial()
		}
		if s == sourceSerial && sourceSerial != "" {
			return d.FilesDir, s
		}
	}
	// Fall back to internal device
	for _, d := range devices {
		if d.UsbInfo == nil {
			return d.FilesDir, ""
		}
	}
	return "", ""
}

package storageutil

import (
	"maps"
	"os"
	"path"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"unicode/utf8"

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
// search rebuilds them on the way down, and only for the files it returns.
//
// A folder keeps the names of its files sorted and end to end in one string,
// so a file costs its name's bytes and a 4-byte offset (#2760): ~30 B a file
// against ~100 B for a map per folder (BenchmarkFileIndexHeap).
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
// subfolders, both in name order. A name is a file or a folder, never both.
type indexDir struct {
	// name is the folder's name in its parent; empty for a device's root.
	name string
	// names is every file name, sorted, end to end; ends[i] is where the
	// i-th one stops.
	names string
	ends  []uint32
	dirs  []*indexDir
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
		roots[dev.FilesDir] = &indexRoot{serial: serial, dir: scanDir(dev.FilesDir, "")}
	}
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.roots = roots
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
// builds the full list. Devices come in the order of their files directories
// and each folder's files, then its subfolders, in name order. visit runs
// under the index's read lock and must not call back into the index.
func (idx *FileIndex) SearchEach(query string, serials map[string]bool, visit func(IndexedFile) bool) {
	match := newNameMatcher(query)
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	for _, filesDir := range slices.Sorted(maps.Keys(idx.roots)) {
		root := idx.roots[filesDir]
		if len(serials) > 0 && !serials[root.serial] {
			continue
		}
		more := root.dir.collect("", match, func(name, relPath string) bool {
			return visit(IndexedFile{Name: name, RelPath: relPath, FilesDir: filesDir, DeviceSerial: root.serial})
		})
		if !more {
			return
		}
	}
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
	_, isFile := oldParent.findFile(oldName)
	dir := oldParent.child(oldName)
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

	// Walk the subfolders the index lacks before taking the write lock. The
	// ones it holds get an empty stand-in, swapped for the held node below.
	idx.mu.RLock()
	var known *indexDir
	if root := idx.roots[filesDir]; root != nil {
		known = root.dir.lookup(parts)
	}
	keep := make(map[*indexDir]bool)
	var unknown []*indexDir
	fresh := fromEntries(entries, func(name string) *indexDir {
		dir := &indexDir{name: name}
		if known.child(name) != nil {
			keep[dir] = true
		} else {
			unknown = append(unknown, dir)
		}
		return dir
	})
	idx.mu.RUnlock()
	for _, dir := range unknown {
		*dir = *scanDir(filepath.Join(abs, dir.name), dir.name)
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()
	root := idx.root(filesDir, serial)
	var parent *indexDir
	old := root.dir
	if len(parts) > 0 {
		parent = root.dir.ensure(parts[:len(parts)-1])
		old = parent.child(parts[len(parts)-1])
	}
	// A held folder a rebuild dropped in between starts out empty.
	for i, dir := range fresh.dirs {
		if held := old.child(dir.name); keep[dir] && held != nil {
			fresh.dirs[i] = held
		}
	}
	if parent == nil {
		root.dir = fresh
	} else {
		parent.putDir(parts[len(parts)-1], fresh)
	}
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

// scanDir reads the tree under abs from disk, skipping internal names. name
// is the folder's name in its parent.
func scanDir(abs, name string) *indexDir {
	entries, err := os.ReadDir(abs)
	if err != nil {
		return &indexDir{name: name}
	}
	dir := fromEntries(entries, func(sub string) *indexDir {
		return scanDir(filepath.Join(abs, sub), sub)
	})
	dir.name = name
	return dir
}

// fromEntries makes a folder of a directory listing, which os.ReadDir sorts
// by name, skipping internal names. subdir supplies each subfolder's node.
func fromEntries(entries []os.DirEntry, subdir func(name string) *indexDir) *indexDir {
	dir := &indexDir{}
	size, count := 0, 0
	for _, entry := range entries {
		if !entry.IsDir() && !IsInternalName(entry.Name()) {
			size += len(entry.Name())
			count++
		}
	}
	var names strings.Builder
	names.Grow(size)
	dir.ends = make([]uint32, 0, count)
	for _, entry := range entries {
		switch name := entry.Name(); {
		case IsInternalName(name):
		case entry.IsDir():
			dir.dirs = append(dir.dirs, subdir(name))
		default:
			names.WriteString(name)
			dir.ends = append(dir.ends, uint32(names.Len()))
		}
	}
	dir.names = names.String()
	if count == 0 {
		dir.ends = nil
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

// file returns the i-th file name, a slice of names.
func (d *indexDir) file(i int) string {
	start := uint32(0)
	if i > 0 {
		start = d.ends[i-1]
	}
	return d.names[start:d.ends[i]]
}

// findFile returns where name is, or would be, among the files.
func (d *indexDir) findFile(name string) (int, bool) {
	i := sort.Search(len(d.ends), func(i int) bool { return d.file(i) >= name })
	return i, i < len(d.ends) && d.file(i) == name
}

// findDir returns where the folder name is, or would be, among the folders.
func (d *indexDir) findDir(name string) (int, bool) {
	return slices.BinarySearchFunc(d.dirs, name, func(dir *indexDir, name string) int {
		return strings.Compare(dir.name, name)
	})
}

// child returns the subfolder name, nil when there is none or d is nil.
func (d *indexDir) child(name string) *indexDir {
	if d == nil {
		return nil
	}
	if i, ok := d.findDir(name); ok {
		return d.dirs[i]
	}
	return nil
}

// lookup returns the folder at parts, nil when the index has none.
func (d *indexDir) lookup(parts []string) *indexDir {
	for _, seg := range parts {
		d = d.child(seg)
	}
	return d
}

// ensure returns the folder at parts, creating any that are missing.
func (d *indexDir) ensure(parts []string) *indexDir {
	for _, seg := range parts {
		next := d.child(seg)
		if next == nil {
			next = &indexDir{}
			d.putDir(seg, next)
		}
		d = next
	}
	return d
}

// putFile records a file, in place of a folder of that name. The names are
// rewritten whole, so a folder's strings never carry spare capacity.
func (d *indexDir) putFile(name string) {
	d.removeDir(name)
	i, ok := d.findFile(name)
	if ok {
		return
	}
	at := uint32(0)
	if i > 0 {
		at = d.ends[i-1]
	}
	d.names = d.names[:at] + name + d.names[at:]
	ends := make([]uint32, len(d.ends)+1)
	copy(ends, d.ends[:i])
	ends[i] = at + uint32(len(name))
	for j := i; j < len(d.ends); j++ {
		ends[j+1] = d.ends[j] + uint32(len(name))
	}
	d.ends = ends
}

// putDir records a folder, in place of a file or a folder of that name.
func (d *indexDir) putDir(name string, dir *indexDir) {
	d.removeFile(name)
	dir.name = strings.Clone(name)
	if i, ok := d.findDir(name); ok {
		d.dirs[i] = dir
	} else {
		d.dirs = slices.Insert(d.dirs, i, dir)
	}
}

// removeFile drops the file name, if d has it.
func (d *indexDir) removeFile(name string) {
	i, ok := d.findFile(name)
	if !ok {
		return
	}
	start, end := uint32(0), d.ends[i]
	if i > 0 {
		start = d.ends[i-1]
	}
	if len(d.ends) == 1 {
		d.names, d.ends = "", nil
		return
	}
	d.names = d.names[:start] + d.names[end:]
	ends := make([]uint32, len(d.ends)-1)
	copy(ends, d.ends[:i])
	for j := i + 1; j < len(d.ends); j++ {
		ends[j-1] = d.ends[j] - (end - start)
	}
	d.ends = ends
}

// removeDir drops the folder name with everything under it, if d has it.
func (d *indexDir) removeDir(name string) {
	if i, ok := d.findDir(name); ok {
		d.dirs = slices.Delete(d.dirs, i, i+1)
	}
}

// remove drops a file or a folder with everything under it. A nil d holds
// nothing to remove.
func (d *indexDir) remove(name string) {
	if d != nil {
		d.removeFile(name)
		d.removeDir(name)
	}
}

// collect calls visit for every file under d whose name matches, with its
// path relative to the tree's root, which prefix is the path of d plus a
// trailing slash. It stops, and reports false, once visit does.
func (d *indexDir) collect(prefix string, match nameMatcher, visit func(name, relPath string) bool) bool {
	for i := range d.ends {
		if name := d.file(i); match.matches(name) && !visit(name, prefix+name) {
			return false
		}
	}
	for _, dir := range d.dirs {
		if !dir.collect(prefix+dir.name+"/", match, visit) {
			return false
		}
	}
	return true
}

// nameMatcher reports whether a name contains a query, ignoring case exactly
// as strings.Contains(strings.ToLower(name), strings.ToLower(query)) does,
// without lowering every ASCII name it reads.
type nameMatcher struct {
	lower string // strings.ToLower(query)
	all   bool   // the query is empty
	ascii bool   // lower is all ASCII
}

func newNameMatcher(query string) nameMatcher {
	lower := strings.ToLower(query)
	return nameMatcher{lower: lower, all: query == "", ascii: isASCII(lower)}
}

// matches reports whether name holds the query. strings.ToLower changes only
// A-Z in an ASCII name, so the query's lowercase form can be found in one by
// folding those bytes, and only when it is ASCII itself.
func (m nameMatcher) matches(name string) bool {
	switch {
	case m.all:
		return true
	case !isASCII(name):
		return strings.Contains(strings.ToLower(name), m.lower)
	case !m.ascii:
		return false
	}
	for i := 0; i+len(m.lower) <= len(name); i++ {
		j := 0
		for j < len(m.lower) && lowerASCII(name[i+j]) == m.lower[j] {
			j++
		}
		if j == len(m.lower) {
			return true
		}
	}
	return false
}

// isASCII reports whether s is all ASCII.
func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= utf8.RuneSelf {
			return false
		}
	}
	return true
}

// lowerASCII lowercases an ASCII letter and leaves any other byte alone.
func lowerASCII(b byte) byte {
	if 'A' <= b && b <= 'Z' {
		return b + 'a' - 'A'
	}
	return b
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

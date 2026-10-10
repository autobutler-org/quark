package indexutil

import (
	"context"
	"io/fs"
	"path"
	"path/filepath"
	"slices"
	"sort"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// scanTree walks the tree at relPath in fsys. The walk is best-effort: what
// cannot be read is left out, so a device that cannot be walked at all
// indexes as empty.
func scanTree(ctx context.Context, fsys vfs.VFS, relPath string) *indexDir {
	dir, _ := scanFolder(ctx, fsys, splitRel(relPath), nil)
	return dir
}

// scanFolder walks the folder at parts in fsys into a fresh tree. A
// subfolder named in held is recorded but not walked: the caller keeps the
// node it already has for it.
func scanFolder(ctx context.Context, fsys vfs.VFS, parts []string, held map[string]bool) (*indexDir, error) {
	b := newTreeBuilder()
	depth := len(parts)
	err := vfs.Walk(ctx, fsys, strings.Join(parts, "/"), func(fi vfs.FileInfo) error {
		rel := splitRel(fi.Path)
		if len(rel) <= depth {
			return nil
		}
		rel = rel[depth:]
		if isInternalPath(rel) {
			if fi.IsDir {
				return fs.SkipDir
			}
			return nil
		}
		b.add(rel, fi.IsDir)
		if fi.IsDir && len(rel) == 1 && held[rel[0]] {
			return fs.SkipDir
		}
		return nil
	})
	return b.finish(), err
}

func newTreeBuilder() *treeBuilder {
	return &treeBuilder{root: &indexDir{}, files: make(map[*indexDir]*fileList)}
}

// add records the file or folder at parts, relative to the tree's root.
func (b *treeBuilder) add(parts []string, isDir bool) {
	parent, name := b.root.ensure(parts[:len(parts)-1]), parts[len(parts)-1]
	if isDir {
		parent.ensure([]string{name})
		return
	}
	list := b.files[parent]
	if list == nil {
		list = &fileList{sorted: true}
		b.files[parent] = list
	}
	// A walk lists a folder in name order; anything else, a duplicate
	// included, is sorted out in finish.
	if len(list.ends) > 0 && name <= list.last {
		list.sorted = false
	}
	list.names = append(list.names, name...)
	list.ends = append(list.ends, uint32(len(list.names)))
	list.last = strings.Clone(name)
}

// finish packs each folder's file names into its one string and returns the
// tree.
func (b *treeBuilder) finish() *indexDir {
	for dir, list := range b.files {
		if list.sorted {
			dir.names, dir.ends = string(list.names), slices.Clone(list.ends)
			continue
		}
		names := make([]string, len(list.ends))
		start := uint32(0)
		for i, end := range list.ends {
			names[i] = string(list.names[start:end])
			start = end
		}
		slices.Sort(names)
		for _, name := range slices.Compact(names) {
			dir.putFile(name)
		}
	}
	return b.root
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
	return slices.ContainsFunc(parts, storageutil.IsInternalName)
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

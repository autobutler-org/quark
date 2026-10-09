package indexutil

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

// treeBuilder grows a tree from a walk. File names are gathered per folder in
// growable buffers and packed into each folder's one string at the end, so
// building a folder of n files costs n appends, not n rewrites of the string.
type treeBuilder struct {
	root  *indexDir
	files map[*indexDir]*fileList
}

// fileList is one folder's file names while a tree is built.
type fileList struct {
	names  []byte
	ends   []uint32
	last   string
	sorted bool
}

// nameMatcher reports whether a name contains a query, ignoring case exactly
// as strings.Contains(strings.ToLower(name), strings.ToLower(query)) does,
// without lowering every ASCII name it reads.
type nameMatcher struct {
	lower string // strings.ToLower(query)
	all   bool   // the query is empty
	ascii bool   // lower is all ASCII
}

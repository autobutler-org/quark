package indexutil

import (
	"context"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

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

// joinParts is the path of parts, "" for the root.
func joinParts(parts []string) string {
	return strings.Join(parts, "/")
}

// joinRel is the path of name in the folder dir.
func joinRel(dir, name string) string {
	if dir == "" {
		return name
	}
	return dir + "/" + name
}

// entry is the row for the file or folder at parts.
func entry(serial string, parts []string, isDir bool, size, mtime, stamp int64) db.UpsertIndexedEntryParams {
	name := parts[len(parts)-1]
	return db.UpsertIndexedEntryParams{
		Serial: serial, Dir: joinParts(parts[:len(parts)-1]), Name: name, SearchName: strings.ToLower(name),
		IsDir: isDir, Size: size, ModTime: mtime, IndexedAt: stamp,
	}
}

// ensureFolders writes a folder row for parts and each folder above it, in
// place of a file of that name.
func ensureFolders(q db.Querier, serial string, parts []string, stamp int64) error {
	for i := range parts {
		if err := q.UpsertIndexedEntry(context.Background(), entry(serial, parts[:i+1], true, 0, 0, stamp)); err != nil {
			return err
		}
	}
	return nil
}

// descendantsParams names the rows under the folder at parts: its path and
// the range of folders that start with path + "/". '0' is the byte after '/'.
func descendantsParams(serial string, parts []string) db.DeleteIndexedDescendantsParams {
	p := joinParts(parts)
	return db.DeleteIndexedDescendantsParams{Serial: serial, Path: p, DirFrom: p + "/", DirTo: p + "0"}
}

// pathParams names the entry at parts and, when it is a folder, everything
// under it.
func pathParams(serial string, parts []string) db.DeleteIndexedPathParams {
	d := descendantsParams(serial, parts)
	return db.DeleteIndexedPathParams{
		Serial: serial, Parent: joinParts(parts[:len(parts)-1]), Name: parts[len(parts)-1],
		Path: d.Path, DirFrom: d.DirFrom, DirTo: d.DirTo,
	}
}

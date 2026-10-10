package vfs

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// List returns direct children of dir (or all descendants if filter.Recursive
// is true). A dir that does not exist is [ErrNotFound].
func (v *DBVFS) List(ctx context.Context, dir string, filter *ListFilter) ([]FileInfo, error) {
	dir = cleanPath(dir)
	if dir != "" {
		info, err := v.Stat(ctx, dir)
		if err != nil {
			return nil, err
		}
		if !info.IsDir {
			return nil, ErrNotFound
		}
	}
	prefix := childPrefix(dir)

	rows, err := v.queries.ListDBVFSEntriesUnder(ctx, db.ListDBVFSEntriesUnderParams{
		Namespace: v.namespaceID,
		Prefix:    prefix,
		Dir:       dir,
	})
	if err != nil {
		return nil, fmt.Errorf("dbvfs list: %w", err)
	}

	recursive := filter != nil && filter.Recursive
	maxResults := 0
	if filter != nil {
		maxResults = filter.MaxResults
	}

	var results []FileInfo
	for _, row := range rows {
		// A direct child has no further '/' after the dir prefix.
		if !recursive && strings.Contains(strings.TrimPrefix(row.Path, prefix), "/") {
			continue
		}

		results = append(results, v.fileInfo(row.Path, row.IsDir, row.Size, row.MimeType, row.UpdatedAt))

		if maxResults > 0 && len(results) >= maxResults {
			break
		}
	}
	return results, nil
}

// Stat returns metadata for the entry at path. Returns ErrNotFound if missing.
// The root always exists.
func (v *DBVFS) Stat(ctx context.Context, p string) (FileInfo, error) {
	p = cleanPath(p)
	if p == "" {
		return FileInfo{IsDir: true, Namespace: v.namespaceID}, nil
	}
	row, err := v.queries.GetDBVFSEntry(ctx, db.GetDBVFSEntryParams{Namespace: v.namespaceID, Path: p})
	if errors.Is(err, sql.ErrNoRows) {
		return FileInfo{}, ErrNotFound
	}
	if err != nil {
		return FileInfo{}, fmt.Errorf("dbvfs stat: %w", err)
	}
	return v.fileInfo(p, row.IsDir, row.Size, row.MimeType, row.UpdatedAt), nil
}

// fileInfo builds the FileInfo for one vfs_db_entries row.
func (v *DBVFS) fileInfo(p string, isDir bool, size int64, mimeType string, modTime time.Time) FileInfo {
	return FileInfo{
		Name:      path.Base(p),
		Path:      p,
		Size:      size,
		IsDir:     isDir,
		MimeType:  mimeType,
		ModTime:   modTime,
		Namespace: v.namespaceID,
	}
}

// Open returns the file content at path. A directory is [ErrIsDirectory].
func (v *DBVFS) Open(ctx context.Context, p string) (File, error) {
	p = cleanPath(p)
	if p == "" {
		return nil, ErrIsDirectory
	}
	row, err := v.queries.GetDBVFSEntryContent(ctx, db.GetDBVFSEntryContentParams{Namespace: v.namespaceID, Path: p})
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("dbvfs open: %w", err)
	}
	if row.IsDir {
		return nil, ErrIsDirectory
	}
	return bytesFile{bytes.NewReader(row.Content)}, nil
}

// Write creates or replaces the file at path with data from r, creating its
// parent directories. With WriteOptions.IfNoneMatch="*" a name already taken
// is ErrConflict before r is read, and the insert itself refuses one taken
// meanwhile, so two writers racing for one name cannot both win.
func (v *DBVFS) Write(ctx context.Context, p string, r io.Reader, opts WriteOptions) error {
	p = cleanPath(p)
	if p == "" {
		return ErrIsDirectory
	}
	if opts.IfNoneMatch == "*" {
		_, err := v.Stat(ctx, p)
		if err == nil {
			return ErrConflict
		}
		if !errors.Is(err, ErrNotFound) {
			return err
		}
	}

	content, err := readBounded(r)
	if err != nil {
		if errors.Is(err, ErrTooLarge) {
			return err
		}
		return fmt.Errorf("dbvfs write read: %w", err)
	}

	if parent := path.Dir(p); parent != "." {
		if err := v.MkdirAll(ctx, parent); err != nil {
			return err
		}
	}

	arg := db.UpsertDBVFSFileParams{
		Namespace: v.namespaceID,
		Path:      p,
		Size:      int64(len(content)),
		MimeType:  opts.ContentType,
		Content:   content,
	}
	var n int64
	if opts.IfNoneMatch == "*" {
		n, err = v.queries.InsertDBVFSFileIfAbsent(ctx, db.InsertDBVFSFileIfAbsentParams(arg))
	} else {
		n, err = v.queries.UpsertDBVFSFile(ctx, arg)
	}
	if err != nil {
		return fmt.Errorf("dbvfs write: %w", err)
	}
	if n == 0 {
		// Nothing was written: the name is taken, by a file under
		// IfNoneMatch or by a directory either way.
		if opts.IfNoneMatch == "*" {
			return ErrConflict
		}
		return ErrIsDirectory
	}
	return nil
}

// Delete removes the entry at path. Without opts.Recursive, a directory with
// children is [ErrNotEmpty]. A missing path is [ErrNotFound], and the root is
// [ErrPermissionDenied].
func (v *DBVFS) Delete(ctx context.Context, p string, opts DeleteOptions) error {
	p = cleanPath(p)
	if p == "" {
		return ErrPermissionDenied
	}
	prefix := childPrefix(p)

	var n int64
	var err error
	if opts.Recursive {
		n, err = v.queries.DeleteDBVFSEntryTree(ctx, db.DeleteDBVFSEntryTreeParams{
			Namespace: v.namespaceID,
			Path:      p,
			Prefix:    prefix,
		})
	} else {
		var childCount int64
		childCount, err = v.queries.CountDBVFSEntriesUnder(ctx, db.CountDBVFSEntriesUnderParams{
			Namespace: v.namespaceID,
			Prefix:    prefix,
			Dir:       p,
		})
		if err != nil {
			return fmt.Errorf("dbvfs delete child check: %w", err)
		}
		if childCount > 0 {
			return ErrNotEmpty
		}
		// With no children, the entry itself is all there is to delete.
		n, err = v.queries.DeleteDBVFSEntry(ctx, db.DeleteDBVFSEntryParams{Namespace: v.namespaceID, Path: p})
	}
	if err != nil {
		return fmt.Errorf("dbvfs delete: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// MkdirAll ensures that the directory path and all its ancestors exist.
func (v *DBVFS) MkdirAll(ctx context.Context, p string) error {
	p = cleanPath(p)
	if p == "" {
		return nil
	}
	segments := strings.Split(p, "/")
	for i := range segments {
		dir := strings.Join(segments[:i+1], "/")
		err := v.queries.InsertDBVFSDirIfAbsent(ctx, db.InsertDBVFSDirIfAbsentParams{Namespace: v.namespaceID, Path: dir})
		if err != nil {
			return fmt.Errorf("dbvfs mkdirall %q: %w", dir, err)
		}
	}
	return nil
}

// Move renames src to dst, updating all descendant paths atomically.
func (v *DBVFS) Move(ctx context.Context, src, dst string) error {
	src = cleanPath(src)
	dst = cleanPath(dst)
	prefix := childPrefix(src)

	if _, err := v.Stat(ctx, src); err != nil {
		return err
	}
	if parent := path.Dir(dst); parent != "." {
		if err := v.MkdirAll(ctx, parent); err != nil {
			return err
		}
	}
	err := v.queries.MoveDBVFSEntryTree(ctx, db.MoveDBVFSEntryTreeParams{
		Dst:       dst,
		Src:       src,
		Namespace: v.namespaceID,
		Prefix:    prefix,
	})
	if err != nil {
		return fmt.Errorf("dbvfs move: %w", err)
	}
	return nil
}

// Copy copies the file at src to dst through Write. See [VFS.Copy].
func (v *DBVFS) Copy(ctx context.Context, src, dst string, opts CopyOptions) error {
	return copyFile(ctx, v, src, v, dst, opts)
}

// Watch is not supported by DBVFS. Always returns ErrWatchNotSupported.
func (v *DBVFS) Watch(_ context.Context, _ string) (<-chan WatchEvent, error) {
	return nil, ErrWatchNotSupported
}

// childPrefix is the prefix every descendant of dir starts with: "dir/", or
// "" for the root. The queries match it with substr rather than LIKE, so a '%'
// or '_' in a name is not a wildcard.
func childPrefix(dir string) string {
	if dir == "" {
		return ""
	}
	return dir + "/"
}

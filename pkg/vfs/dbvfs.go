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

	rows, err := v.db.QueryContext(ctx,
		`SELECT path, is_dir, size, mime_type, updated_at
		 FROM vfs_db_entries
		 WHERE namespace=? AND substr(path, 1, ?)=? AND path != ?
		 ORDER BY path`,
		v.namespaceID, len(prefix), prefix, dir,
	)
	if err != nil {
		return nil, fmt.Errorf("dbvfs list: %w", err)
	}
	defer rows.Close()

	recursive := filter != nil && filter.Recursive
	maxResults := 0
	if filter != nil {
		maxResults = filter.MaxResults
	}

	var results []FileInfo
	for rows.Next() {
		var (
			p         string
			isDir     bool
			size      int64
			mimeType  string
			updatedAt string
		)
		if err := rows.Scan(&p, &isDir, &size, &mimeType, &updatedAt); err != nil {
			return nil, fmt.Errorf("dbvfs list scan: %w", err)
		}

		// A direct child has no further '/' after the dir prefix.
		if !recursive && strings.Contains(strings.TrimPrefix(p, prefix), "/") {
			continue
		}

		results = append(results, v.fileInfo(p, isDir, size, mimeType, updatedAt))

		if maxResults > 0 && len(results) >= maxResults {
			break
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("dbvfs list rows: %w", err)
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
	var (
		isDir     bool
		size      int64
		mimeType  string
		updatedAt string
	)
	err := v.db.QueryRowContext(ctx,
		`SELECT is_dir, size, mime_type, updated_at
		 FROM vfs_db_entries
		 WHERE namespace=? AND path=?`,
		v.namespaceID, p,
	).Scan(&isDir, &size, &mimeType, &updatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return FileInfo{}, ErrNotFound
	}
	if err != nil {
		return FileInfo{}, fmt.Errorf("dbvfs stat: %w", err)
	}
	return v.fileInfo(p, isDir, size, mimeType, updatedAt), nil
}

// fileInfo builds the FileInfo for one vfs_db_entries row.
func (v *DBVFS) fileInfo(p string, isDir bool, size int64, mimeType, updatedAt string) FileInfo {
	modTime, _ := time.Parse("2006-01-02 15:04:05", updatedAt)
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
	var (
		isDir   bool
		content []byte
	)
	err := v.db.QueryRowContext(ctx,
		`SELECT is_dir, content FROM vfs_db_entries WHERE namespace=? AND path=?`,
		v.namespaceID, p,
	).Scan(&isDir, &content)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("dbvfs open: %w", err)
	}
	if isDir {
		return nil, ErrIsDirectory
	}
	return bytesFile{bytes.NewReader(content)}, nil
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

	onConflict := `DO UPDATE SET
		     size=excluded.size,
		     mime_type=excluded.mime_type,
		     content=excluded.content,
		     updated_at=excluded.updated_at
		 WHERE is_dir=0`
	if opts.IfNoneMatch == "*" {
		onConflict = `DO NOTHING`
	}
	res, err := v.db.ExecContext(ctx,
		`INSERT INTO vfs_db_entries (namespace, path, is_dir, size, mime_type, content, updated_at)
		 VALUES (?, ?, 0, ?, ?, ?, datetime('now'))
		 ON CONFLICT(namespace, path) `+onConflict,
		v.namespaceID, p, int64(len(content)), opts.ContentType, content,
	)
	if err != nil {
		return fmt.Errorf("dbvfs write: %w", err)
	}
	n, err := res.RowsAffected()
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

	query := `DELETE FROM vfs_db_entries WHERE namespace=? AND (path=? OR substr(path, 1, ?)=?)`
	args := []any{v.namespaceID, p, len(prefix), prefix}
	if !opts.Recursive {
		var childCount int
		err := v.db.QueryRowContext(ctx,
			`SELECT COUNT(1) FROM vfs_db_entries WHERE namespace=? AND substr(path, 1, ?)=? AND path != ?`,
			v.namespaceID, len(prefix), prefix, p,
		).Scan(&childCount)
		if err != nil {
			return fmt.Errorf("dbvfs delete child check: %w", err)
		}
		if childCount > 0 {
			return ErrNotEmpty
		}
		// With no children, the entry itself is all there is to delete.
		query = `DELETE FROM vfs_db_entries WHERE namespace=? AND path=?`
		args = args[:2]
	}

	res, err := v.db.ExecContext(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("dbvfs delete: %w", err)
	}
	n, err := res.RowsAffected()
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
		_, err := v.db.ExecContext(ctx,
			`INSERT OR IGNORE INTO vfs_db_entries (namespace, path, is_dir, size, mime_type, content)
			 VALUES (?, ?, 1, 0, '', NULL)`,
			v.namespaceID, dir,
		)
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
	_, err := v.db.ExecContext(ctx,
		`UPDATE vfs_db_entries
		 SET path = ? || SUBSTR(path, LENGTH(?)+1)
		 WHERE namespace=? AND (path=? OR substr(path, 1, ?)=?)`,
		dst, src, v.namespaceID, src, len(prefix), prefix,
	)
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
// "" for the root. Matched with substr rather than LIKE, so a '%' or '_' in a
// name is not a wildcard.
func childPrefix(dir string) string {
	if dir == "" {
		return ""
	}
	return dir + "/"
}

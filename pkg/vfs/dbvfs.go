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

// List returns direct children of dir (or all descendants if filter.Recursive is true).
func (v *DBVFS) List(ctx context.Context, dir string, filter *ListFilter) ([]FileInfo, error) {
	dir = dbCleanPath(dir)
	if dir != "/" {
		dir = strings.TrimSuffix(dir, "/") + "/"
	}

	var rows *sql.Rows
	var err error

	rows, err = v.db.QueryContext(ctx,
		`SELECT path, is_dir, size, mime_type, updated_at
		 FROM vfs_db_entries
		 WHERE namespace=? AND path LIKE ? AND path != ?
		 ORDER BY path`,
		v.namespaceID, dir+"%", dir,
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

		// For non-recursive: skip entries that aren't direct children.
		if !recursive {
			// A direct child of dir is a path where, after stripping the dir prefix,
			// the remainder has no '/' (except possibly a trailing one for directories).
			rel := strings.TrimPrefix(p, dir)
			rel = strings.TrimSuffix(rel, "/")
			if strings.Contains(rel, "/") {
				continue
			}
		}

		modTime, _ := time.Parse("2006-01-02 15:04:05", updatedAt)
		results = append(results, FileInfo{
			Name:      path.Base(strings.TrimSuffix(p, "/")),
			Path:      p,
			Size:      size,
			IsDir:     isDir,
			MimeType:  mimeType,
			ModTime:   modTime,
			Namespace: v.namespaceID,
		})

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
func (v *DBVFS) Stat(ctx context.Context, p string) (FileInfo, error) {
	p = dbCleanPath(p)
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
	if err == sql.ErrNoRows {
		return FileInfo{}, ErrNotFound
	}
	if err != nil {
		return FileInfo{}, fmt.Errorf("dbvfs stat: %w", err)
	}

	modTime, _ := time.Parse("2006-01-02 15:04:05", updatedAt)
	return FileInfo{
		Name:      path.Base(strings.TrimSuffix(p, "/")),
		Path:      p,
		Size:      size,
		IsDir:     isDir,
		MimeType:  mimeType,
		ModTime:   modTime,
		Namespace: v.namespaceID,
	}, nil
}

// Open returns a ReadCloser for the file content at path.
// Returns ErrNotFound if the path doesn't exist or is a directory.
func (v *DBVFS) Open(ctx context.Context, p string) (File, error) {
	p = dbCleanPath(p)
	var (
		isDir   bool
		content []byte
	)
	err := v.db.QueryRowContext(ctx,
		`SELECT is_dir, content FROM vfs_db_entries WHERE namespace=? AND path=?`,
		v.namespaceID, p,
	).Scan(&isDir, &content)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("dbvfs open: %w", err)
	}
	if isDir {
		return nil, ErrNotFound
	}
	return bytesFile{bytes.NewReader(content)}, nil
}

// Write creates or replaces the file at path with data from r.
// Honors WriteOptions.IfNoneMatch="*" (returns ErrConflict if the entry already exists).
func (v *DBVFS) Write(ctx context.Context, p string, r io.Reader, opts WriteOptions) error {
	p = dbCleanPath(p)

	if opts.IfNoneMatch == "*" {
		var exists int
		err := v.db.QueryRowContext(ctx,
			`SELECT COUNT(1) FROM vfs_db_entries WHERE namespace=? AND path=?`,
			v.namespaceID, p,
		).Scan(&exists)
		if err != nil {
			return fmt.Errorf("dbvfs write existence check: %w", err)
		}
		if exists > 0 {
			return ErrConflict
		}
	}

	content, err := readBounded(r)
	if err != nil {
		if errors.Is(err, ErrTooLarge) {
			return err
		}
		return fmt.Errorf("dbvfs write read: %w", err)
	}

	_, err = v.db.ExecContext(ctx,
		`INSERT INTO vfs_db_entries (namespace, path, is_dir, size, mime_type, content, updated_at)
		 VALUES (?, ?, 0, ?, ?, ?, datetime('now'))
		 ON CONFLICT(namespace, path) DO UPDATE SET
		     size=excluded.size,
		     mime_type=excluded.mime_type,
		     content=excluded.content,
		     updated_at=excluded.updated_at`,
		v.namespaceID, p, int64(len(content)), opts.ContentType, content,
	)
	if err != nil {
		return fmt.Errorf("dbvfs write: %w", err)
	}
	return nil
}

// Delete removes the entry at path.
// Without opts.Recursive, returns ErrNotEmpty if the path has children.
func (v *DBVFS) Delete(ctx context.Context, p string, opts DeleteOptions) error {
	p = dbCleanPath(p)

	if !opts.Recursive {
		// Check for child paths.
		prefix := strings.TrimSuffix(p, "/") + "/"
		var childCount int
		err := v.db.QueryRowContext(ctx,
			`SELECT COUNT(1) FROM vfs_db_entries WHERE namespace=? AND path LIKE ? AND path != ?`,
			v.namespaceID, prefix+"%", p,
		).Scan(&childCount)
		if err != nil {
			return fmt.Errorf("dbvfs delete child check: %w", err)
		}
		if childCount > 0 {
			return ErrNotEmpty
		}

		_, err = v.db.ExecContext(ctx,
			`DELETE FROM vfs_db_entries WHERE namespace=? AND path=?`,
			v.namespaceID, p,
		)
		if err != nil {
			return fmt.Errorf("dbvfs delete: %w", err)
		}
		return nil
	}

	// Recursive: delete the entry and all children.
	prefix := strings.TrimSuffix(p, "/") + "/"
	_, err := v.db.ExecContext(ctx,
		`DELETE FROM vfs_db_entries WHERE namespace=? AND (path=? OR path LIKE ?)`,
		v.namespaceID, p, prefix+"%",
	)
	if err != nil {
		return fmt.Errorf("dbvfs delete recursive: %w", err)
	}
	return nil
}

// MkdirAll ensures that the directory path and all its ancestors exist.
func (v *DBVFS) MkdirAll(ctx context.Context, p string) error {
	p = dbCleanPath(p)
	// Build list of ancestor paths.
	segments := strings.Split(strings.Trim(p, "/"), "/")
	dirs := make([]string, 0, len(segments))
	for i := range segments {
		if segments[i] == "" {
			continue
		}
		dirs = append(dirs, "/"+strings.Join(segments[:i+1], "/")+"/")
	}
	if p == "/" {
		dirs = []string{"/"}
	}

	for _, dir := range dirs {
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
	src = dbCleanPath(src)
	dst = dbCleanPath(dst)

	prefix := strings.TrimSuffix(src, "/") + "/"
	_, err := v.db.ExecContext(ctx,
		`UPDATE vfs_db_entries
		 SET path = ? || SUBSTR(path, LENGTH(?)+1)
		 WHERE namespace=? AND (path=? OR path LIKE ?)`,
		dst, src, v.namespaceID, src, prefix+"%",
	)
	if err != nil {
		return fmt.Errorf("dbvfs move: %w", err)
	}
	return nil
}

// Watch is not supported by DBVFS. Always returns ErrWatchNotSupported.
func (v *DBVFS) Watch(_ context.Context, _ string) (<-chan WatchEvent, error) {
	return nil, ErrWatchNotSupported
}

// dbCleanPath normalizes a VFS path to an absolute slash-prefixed form.
// Always returns a path beginning with '/'. Directories keep their trailing slash
// if provided; files do not. The root is always "/".
func dbCleanPath(p string) string {
	if p == "" || p == "/" {
		return "/"
	}
	return path.Clean("/" + strings.TrimPrefix(p, "/"))
}

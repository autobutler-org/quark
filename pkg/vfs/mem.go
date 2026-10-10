package vfs

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"mime"
	"path/filepath"
	"strings"
	"time"
)

// memEntry holds the data and metadata for a MemVFS entry.
type memEntry struct {
	data []byte
	info FileInfo
}

// cleanPath is the one path form every implementation accepts and returns:
// relative, slash-separated, no leading or trailing slash, "" for the root —
// accessutil.Canonical's form (#2640).
func cleanPath(path string) string {
	p := filepath.ToSlash(filepath.Clean("/" + path))
	p = strings.TrimPrefix(p, "/")
	return p
}

func hashBytes(data []byte) string {
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:])
}

// List returns entries in the given directory.
func (m *MemVFS) List(ctx context.Context, path string, filter *ListFilter) ([]FileInfo, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	dir := cleanPath(path)

	// Check directory exists
	if dir != "" && !m.dirs[dir] {
		return nil, ErrNotFound
	}

	seen := make(map[string]bool)
	var results []FileInfo

	// Collect matching files
	prefix := dir
	if prefix != "" {
		prefix += "/"
	}

	for p, entry := range m.files {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		if !strings.HasPrefix(p, prefix) {
			continue
		}

		rel := strings.TrimPrefix(p, prefix)
		if rel == "" {
			continue
		}

		if !filter.GetRecursive() {
			// Non-recursive: only direct children
			if strings.Contains(rel, "/") {
				continue
			}
		}

		// Apply AfterPath cursor
		if filter != nil && filter.AfterPath != "" && p <= filter.AfterPath {
			continue
		}

		// Apply MimePrefix filter
		if filter != nil && filter.MimePrefix != "" {
			if !strings.HasPrefix(entry.info.MimeType, filter.MimePrefix) {
				continue
			}
		}

		if seen[p] {
			continue
		}
		seen[p] = true
		results = append(results, entry.info)

		if filter != nil && filter.MaxResults > 0 && len(results) >= filter.MaxResults {
			return results, nil
		}
	}

	// Collect matching directories
	for d := range m.dirs {
		if d == "" {
			continue
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}

		if !strings.HasPrefix(d, prefix) {
			continue
		}

		rel := strings.TrimPrefix(d, prefix)
		if rel == "" {
			continue
		}

		if !filter.GetRecursive() {
			// Non-recursive: only direct child dirs
			if strings.Contains(rel, "/") {
				continue
			}
		}

		// Apply AfterPath cursor
		if filter != nil && filter.AfterPath != "" && d <= filter.AfterPath {
			continue
		}

		if seen[d] {
			continue
		}
		seen[d] = true

		parts := strings.Split(d, "/")
		name := parts[len(parts)-1]
		info := FileInfo{
			Name:      name,
			Path:      d,
			IsDir:     true,
			ModTime:   time.Time{},
			Namespace: m.namespaceID,
		}
		results = append(results, info)

		if filter != nil && filter.MaxResults > 0 && len(results) >= filter.MaxResults {
			return results, nil
		}
	}

	return results, nil
}

// GetRecursive is a helper for nil-safe filter access.
func (f *ListFilter) GetRecursive() bool {
	if f == nil {
		return false
	}
	return f.Recursive
}

// Stat returns file metadata for the given path.
func (m *MemVFS) Stat(ctx context.Context, path string) (FileInfo, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	p := cleanPath(path)

	if entry, ok := m.files[p]; ok {
		return entry.info, nil
	}
	if m.dirs[p] {
		parts := strings.Split(p, "/")
		name := parts[len(parts)-1]
		if p == "" {
			name = ""
		}
		return FileInfo{
			Name:      name,
			Path:      p,
			IsDir:     true,
			Namespace: m.namespaceID,
		}, nil
	}
	return FileInfo{}, ErrNotFound
}

// Open opens the file at the given path for reading.
func (m *MemVFS) Open(ctx context.Context, path string) (File, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	p := cleanPath(path)
	entry, ok := m.files[p]
	if !ok {
		if m.dirs[p] {
			return nil, ErrIsDirectory
		}
		return nil, ErrNotFound
	}
	return bytesFile{bytes.NewReader(entry.data)}, nil
}

// Write writes the content of r to the given path.
func (m *MemVFS) Write(ctx context.Context, path string, r io.Reader, opts WriteOptions) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	p := cleanPath(path)

	// Honor IfNoneMatch: "*"
	if opts.IfNoneMatch == "*" {
		if _, ok := m.files[p]; ok {
			return ErrConflict
		}
	}

	data, err := readBounded(r)
	if err != nil {
		return err
	}

	// Ensure all parent directories exist
	parts := strings.Split(p, "/")
	for i := 1; i < len(parts); i++ {
		parentPath := strings.Join(parts[:i], "/")
		m.dirs[parentPath] = true
	}

	mimeType := opts.ContentType
	if mimeType == "" {
		mimeType = mime.TypeByExtension(filepath.Ext(p))
	}

	name := parts[len(parts)-1]
	info := FileInfo{
		Name:        name,
		Path:        p,
		Size:        int64(len(data)),
		IsDir:       false,
		MimeType:    mimeType,
		ModTime:     time.Now(),
		ContentHash: hashBytes(data),
		Namespace:   m.namespaceID,
	}

	m.files[p] = memEntry{data: data, info: info}
	return nil
}

// Delete removes the file or directory at the given path. The root is
// [ErrPermissionDenied].
func (m *MemVFS) Delete(ctx context.Context, path string, opts DeleteOptions) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	p := cleanPath(path)
	if p == "" {
		return ErrPermissionDenied
	}

	// Check if it's a file
	if _, ok := m.files[p]; ok {
		delete(m.files, p)
		return nil
	}

	// Check if it's a directory
	if !m.dirs[p] {
		return ErrNotFound
	}

	prefix := p + "/"

	if opts.Recursive {
		// Remove all children
		for fp := range m.files {
			if strings.HasPrefix(fp, prefix) {
				delete(m.files, fp)
			}
		}
		for dp := range m.dirs {
			if strings.HasPrefix(dp, prefix) {
				delete(m.dirs, dp)
			}
		}
		delete(m.dirs, p)
		return nil
	}

	// Check if directory is empty
	for fp := range m.files {
		if strings.HasPrefix(fp, prefix) {
			return ErrNotEmpty
		}
	}
	for dp := range m.dirs {
		if strings.HasPrefix(dp, prefix) {
			return ErrNotEmpty
		}
	}

	delete(m.dirs, p)
	return nil
}

// MkdirAll creates the directory at the given path, including all parents.
func (m *MemVFS) MkdirAll(ctx context.Context, path string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	p := cleanPath(path)
	parts := strings.Split(p, "/")
	for i := 1; i <= len(parts); i++ {
		dirPath := strings.Join(parts[:i], "/")
		m.dirs[dirPath] = true
	}
	return nil
}

// Move relocates src to dst within the MemVFS.
func (m *MemVFS) Move(_ context.Context, src, dst string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	s := cleanPath(src)
	d := cleanPath(dst)

	// Move a single file.
	if entry, ok := m.files[s]; ok {
		entry.info.Path = d
		entry.info.Name = filepath.Base(d)
		m.files[d] = entry
		delete(m.files, s)
		return nil
	}

	// Move a directory and all its descendants.
	if !m.dirs[s] {
		return ErrNotFound
	}

	prefix := s + "/"
	for fp, entry := range m.files {
		if strings.HasPrefix(fp, prefix) {
			rel := strings.TrimPrefix(fp, prefix)
			newPath := d + "/" + rel
			entry.info.Path = newPath
			entry.info.Name = filepath.Base(newPath)
			m.files[newPath] = entry
			delete(m.files, fp)
		}
	}
	for dp := range m.dirs {
		if strings.HasPrefix(dp, prefix) {
			rel := strings.TrimPrefix(dp, prefix)
			m.dirs[d+"/"+rel] = true
			delete(m.dirs, dp)
		}
	}
	delete(m.dirs, s)
	m.dirs[d] = true
	return nil
}

// Copy copies the file at src to dst through Write. See [VFS.Copy].
func (m *MemVFS) Copy(ctx context.Context, src, dst string, opts CopyOptions) error {
	return copyFile(ctx, m, src, m, dst, opts)
}

// Watch is not supported by MemVFS and always returns ErrWatchNotSupported.
func (m *MemVFS) Watch(ctx context.Context, path string) (<-chan WatchEvent, error) {
	return nil, ErrWatchNotSupported
}

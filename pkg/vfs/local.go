package vfs

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// errListBudgetSpent unwinds a recursive List once MaxResults is reached.
// Returning plain nil from a nested level only stopped that level: the parent
// loop carried on appending, so MaxResults=2 could return 3 entries. Caught by
// the VFS conformance suite added with #1605.
var errListBudgetSpent = errors.New("vfs: list result budget spent")

// abs converts a VFS-relative path to an absolute host path, guarding against
// path traversal attacks. Returns ErrPermissionDenied if the result would
// escape the root.
//
// filepath.Join calls filepath.Clean internally, but we call it explicitly so
// that static analyzers (CodeQL go/path-injection) recognize this function as
// a sanitizer rather than treating the joined result as tainted user data.
func (v *LocalVFS) abs(path string) (string, error) {
	clean := filepath.Clean(filepath.Join(v.root, filepath.FromSlash(path)))
	if clean != v.root && !strings.HasPrefix(clean, v.root+string(os.PathSeparator)) {
		return "", ErrPermissionDenied
	}
	return clean, nil
}

// hashFile computes the sha256 hex digest of the file at the given absolute path.
func hashFile(absPath string) (string, error) {
	f, err := os.Open(absPath)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func mimeForPath(path string) string {
	t := mime.TypeByExtension(filepath.Ext(path))
	return t
}

func (v *LocalVFS) infoFromStat(relPath string, absPath string, fi os.FileInfo) (FileInfo, error) {
	info := FileInfo{
		Name:      fi.Name(),
		Path:      relPath,
		Size:      fi.Size(),
		IsDir:     fi.IsDir(),
		MimeType:  mimeForPath(absPath),
		ModTime:   fi.ModTime(),
		Namespace: v.namespaceID,
	}
	if !fi.IsDir() {
		hash, err := hashFile(absPath)
		if err != nil {
			return FileInfo{}, err
		}
		info.ContentHash = hash
	}
	return info, nil
}

// List returns a list of files in the given directory.
func (v *LocalVFS) List(ctx context.Context, path string, filter *ListFilter) ([]FileInfo, error) {
	absPath, err := v.abs(path)
	if err != nil {
		return nil, err
	}

	var results []FileInfo
	var collect func(dir string, relDir string) error

	collect = func(dir string, relDir string) error {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if os.IsNotExist(err) {
				return ErrNotFound
			}
			return err
		}
		for _, entry := range entries {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if storageutil.IsInternalName(entry.Name()) {
				continue
			}

			absEntry := filepath.Join(dir, entry.Name())
			var relEntry string
			if relDir == "" {
				relEntry = entry.Name()
			} else {
				relEntry = relDir + "/" + entry.Name()
			}

			// Apply AfterPath cursor (skip entries up to and including AfterPath)
			if filter != nil && filter.AfterPath != "" && relEntry <= filter.AfterPath {
				// Still recurse into dirs to find entries after cursor
				if entry.IsDir() && filter != nil && filter.Recursive {
					if err := collect(absEntry, relEntry); err != nil {
						return err
					}
				}
				continue
			}

			fi, err := entry.Info()
			if err != nil {
				return err
			}

			info, err := v.infoFromStat(relEntry, absEntry, fi)
			if err != nil {
				return err
			}

			// Apply MimePrefix filter (dirs always pass)
			if filter != nil && filter.MimePrefix != "" && !info.IsDir {
				if !strings.HasPrefix(info.MimeType, filter.MimePrefix) {
					if entry.IsDir() && filter.Recursive {
						if err := collect(absEntry, relEntry); err != nil {
							return err
						}
					}
					continue
				}
			}

			results = append(results, info)

			// Apply MaxResults. The sentinel unwinds every level of the walk,
			// not just this one.
			if filter != nil && filter.MaxResults > 0 && len(results) >= filter.MaxResults {
				return errListBudgetSpent
			}

			// Recurse into directories
			if entry.IsDir() && filter != nil && filter.Recursive {
				if err := collect(absEntry, relEntry); err != nil {
					return err
				}
			}
		}
		return nil
	}

	if err := collect(absPath, ""); err != nil && !errors.Is(err, errListBudgetSpent) {
		return nil, err
	}

	return results, nil
}

// Stat returns file metadata for the given path.
func (v *LocalVFS) Stat(ctx context.Context, path string) (FileInfo, error) {
	absPath, err := v.abs(path)
	if err != nil {
		return FileInfo{}, err
	}
	fi, err := os.Stat(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return FileInfo{}, ErrNotFound
		}
		return FileInfo{}, err
	}
	return v.infoFromStat(path, absPath, fi)
}

// Open opens the file at the given path for reading.
func (v *LocalVFS) Open(ctx context.Context, path string) (io.ReadCloser, error) {
	absPath, err := v.abs(path)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return f, nil
}

// Write writes the content of r to the given path.
// It uses an atomic write (temp file + rename) to avoid partial writes.
func (v *LocalVFS) Write(ctx context.Context, path string, r io.Reader, opts WriteOptions) error {
	absPath, err := v.abs(path)
	if err != nil {
		return err
	}

	// Honor IfNoneMatch: "*" — fail if file already exists
	if opts.IfNoneMatch == "*" {
		if _, err := os.Stat(absPath); err == nil {
			return ErrConflict
		}
	}

	return writeAtomic(absPath, r)
}

// MoveFileIn places the host file at srcAbs at path, renaming it rather than
// copying it when it can. See [FileMover].
func (v *LocalVFS) MoveFileIn(ctx context.Context, srcAbs string, path string, opts WriteOptions) error {
	absPath, err := v.abs(path)
	if err != nil {
		return err
	}
	return moveFileIn(srcAbs, absPath, opts, func(r io.Reader) error {
		return v.Write(ctx, path, r, opts)
	})
}

// Delete removes the file or directory at the given path.
func (v *LocalVFS) Delete(ctx context.Context, path string, opts DeleteOptions) error {
	absPath, err := v.abs(path)
	if err != nil {
		return err
	}

	fi, err := os.Stat(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return err
	}

	if fi.IsDir() {
		if opts.Recursive {
			return os.RemoveAll(absPath)
		}
		// Check if directory is empty
		entries, err := os.ReadDir(absPath)
		if err != nil {
			return err
		}
		if len(entries) > 0 {
			return ErrNotEmpty
		}
		return os.Remove(absPath)
	}

	if err := os.Remove(absPath); err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return err
	}
	return nil
}

// MkdirAll creates the directory at the given path, including all parents.
func (v *LocalVFS) MkdirAll(ctx context.Context, path string) error {
	absPath, err := v.abs(path)
	if err != nil {
		return err
	}
	return os.MkdirAll(absPath, 0o755)
}

// Move renames src to dst within the VFS root.
func (v *LocalVFS) Move(_ context.Context, src, dst string) error {
	srcAbs, err := v.abs(src)
	if err != nil {
		return err
	}
	dstAbs, err := v.abs(dst)
	if err != nil {
		return err
	}
	// Re-clean so static analyzers (CodeQL go/path-injection) can follow the
	// traversal guard through abs() rather than treating outputs as tainted.
	srcAbs = filepath.Clean(srcAbs)
	dstAbs = filepath.Clean(dstAbs)
	if err := os.MkdirAll(filepath.Dir(dstAbs), 0o755); err != nil {
		return err
	}
	return os.Rename(srcAbs, dstAbs)
}

// Watch is not supported by LocalVFS and always returns ErrWatchNotSupported.
func (v *LocalVFS) Watch(ctx context.Context, path string) (<-chan WatchEvent, error) {
	return nil, ErrWatchNotSupported
}

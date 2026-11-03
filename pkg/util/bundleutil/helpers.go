package bundleutil

import (
	"archive/tar"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// databaseEntry is the bundle's first entry, its database.
const databaseEntry = "quark.db"

// bundledDirs are the directories of the data directory a bundle carries: the
// files, the trash beside them, and profile pictures. Everything else there is
// a cache, staging, this machine's own (its TLS certificate, mount points), or
// state an older Quark kept in files that the database holds now.
var bundledDirs = []string{"files", storageutil.TrashDir, "avatars"}

func export(ctx context.Context, params ExportParams) (ExportResult, error) {
	sqlitePath := filepath.Join(params.DataDir, databaseEntry)
	if params.Database.Backend != db.Postgres {
		if _, err := os.Stat(sqlitePath); err != nil {
			return ExportResult{}, fmt.Errorf("no SQLite database at %s (%w). Run as the user the service runs "+
				"as (quark on a device), or pass the install's data directory with --data-dir; if it runs on "+
				"PostgreSQL, pass --database-url", sqlitePath, err)
		}
	}
	tmp, err := os.MkdirTemp("", "quark-bundle-")
	if err != nil {
		return ExportResult{}, err
	}
	defer os.RemoveAll(tmp)
	dbPath := filepath.Join(tmp, databaseEntry)
	copied, err := db.ExportDatabase(ctx, db.ExportDatabaseParams{
		Source: params.Database, SQLitePath: sqlitePath, Dest: dbPath,
	})
	if err != nil {
		return ExportResult{}, err
	}

	result := ExportResult{Database: copied}
	tw := tar.NewWriter(params.Out)
	if err := addEntry(tw, dbPath, databaseEntry, &result.Files, &result.Bytes); err != nil {
		return ExportResult{}, err
	}
	for _, dir := range bundledDirs {
		root := filepath.Join(params.DataDir, dir)
		// A directory the install never made (no trash yet) is not an error.
		if _, err := os.Lstat(root); errors.Is(err, fs.ErrNotExist) {
			continue
		}
		err := filepath.WalkDir(root, func(file string, _ fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			rel, err := filepath.Rel(params.DataDir, file)
			if err != nil {
				return err
			}
			return addEntry(tw, file, filepath.ToSlash(rel), &result.Files, &result.Bytes)
		})
		if err != nil {
			return ExportResult{}, fmt.Errorf("failed to add %s to the bundle: %w", dir, err)
		}
	}
	if err := tw.Close(); err != nil {
		return ExportResult{}, fmt.Errorf("failed to finish the bundle: %w", err)
	}
	return result, nil
}

// addEntry writes the directory, regular file or symlink at file to tw as
// name, counting a regular file and its bytes. Anything else (a socket, a
// device) is not user content and is skipped.
func addEntry(tw *tar.Writer, file, name string, files, bytes *int64) error {
	info, err := os.Lstat(file)
	if err != nil {
		return err
	}
	var link string
	switch {
	case info.Mode()&fs.ModeSymlink != 0:
		if link, err = os.Readlink(file); err != nil {
			return err
		}
	case !info.IsDir() && !info.Mode().IsRegular():
		return nil
	}
	header, err := tar.FileInfoHeader(info, link)
	if err != nil {
		return err
	}
	header.Name = name
	if info.IsDir() {
		header.Name += "/"
	}
	if err := tw.WriteHeader(header); err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	f, err := os.Open(file)
	if err != nil {
		return err
	}
	defer f.Close()
	written, err := io.Copy(tw, f)
	*files++
	*bytes += written
	return err
}

func importBundle(ctx context.Context, params ImportParams) (ImportResult, error) {
	sqlitePath := filepath.Join(params.DataDir, databaseEntry)
	tr := tar.NewReader(params.Bundle)
	header, err := tr.Next()
	if err != nil || header.Name != databaseEntry {
		return ImportResult{}, fmt.Errorf("not a Quark bundle: it does not start with %s (%v). Take one with "+
			"quark bundle export on the source install", databaseEntry, err)
	}
	if err := db.RequireUninitialized(ctx, params.Database, sqlitePath); err != nil {
		return ImportResult{}, err
	}

	tmp, err := os.MkdirTemp("", "quark-bundle-")
	if err != nil {
		return ImportResult{}, err
	}
	defer os.RemoveAll(tmp)
	dbPath := filepath.Join(tmp, databaseEntry)
	if err := writeFile(dbPath, tr, 0o600); err != nil {
		return ImportResult{}, fmt.Errorf("failed to read the bundle's database: %w", err)
	}

	if err := os.MkdirAll(params.DataDir, 0o755); err != nil {
		return ImportResult{}, err
	}
	// Every entry is placed through root, so a name or a link in the bundle
	// cannot reach outside the data directory.
	root, err := os.OpenRoot(params.DataDir)
	if err != nil {
		return ImportResult{}, err
	}
	defer root.Close()
	var result ImportResult
	for {
		header, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return ImportResult{}, fmt.Errorf("failed to read the bundle: %w", err)
		}
		if err := ctx.Err(); err != nil {
			return ImportResult{}, err
		}
		if err := placeEntry(root, header, tr, &result); err != nil {
			return ImportResult{}, fmt.Errorf("failed to place %s: %w", header.Name, err)
		}
	}

	copied, err := db.ImportDatabase(ctx, db.ImportDatabaseParams{
		BundleDB: dbPath, Target: params.Database, SQLitePath: sqlitePath,
	})
	if err != nil {
		return ImportResult{}, err
	}
	result.Database = copied
	return result, nil
}

// placeEntry writes one bundle entry under root, which must be inside one of
// bundledDirs.
func placeEntry(root *os.Root, header *tar.Header, content io.Reader, result *ImportResult) error {
	name := path.Clean(header.Name)
	top, _, _ := strings.Cut(name, "/")
	if !filepath.IsLocal(name) || !slices.Contains(bundledDirs, top) {
		return fmt.Errorf("not a Quark bundle: it holds an entry outside %s", strings.Join(bundledDirs, ", "))
	}
	if header.Typeflag == tar.TypeDir {
		return root.MkdirAll(name, 0o755)
	}
	if err := root.MkdirAll(path.Dir(name), 0o755); err != nil {
		return err
	}
	switch header.Typeflag {
	case tar.TypeReg:
		f, err := root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, header.FileInfo().Mode().Perm())
		if err != nil {
			return err
		}
		written, err := io.Copy(f, content)
		if err := errors.Join(err, f.Close()); err != nil {
			return err
		}
		result.Files++
		result.Bytes += written
		return root.Chtimes(name, header.ModTime, header.ModTime)
	case tar.TypeSymlink:
		// A rerun finds the link from the last one.
		if err := root.Remove(name); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		return root.Symlink(header.Linkname, name)
	default:
		return fmt.Errorf("not a Quark bundle: entry type %q", header.Typeflag)
	}
}

// writeFile copies r into a new file at path.
func writeFile(path string, r io.Reader, perm fs.FileMode) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, perm)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, r)
	return errors.Join(err, f.Close())
}

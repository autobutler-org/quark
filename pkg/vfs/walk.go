package vfs

import (
	"context"
	"errors"
	"io/fs"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func walk(ctx context.Context, fsys VFS, path string, visit WalkFunc) error {
	path = cleanPath(path)
	if storageutil.IsTrashPath(path) {
		return ErrPermissionDenied
	}
	if w, ok := fsys.(Walker); ok {
		return w.Walk(ctx, path, visit)
	}
	entries, err := fsys.List(ctx, path, nil)
	if err != nil {
		return err
	}
	if err := walkEntries(ctx, fsys, entries, visit); err != nil && !errors.Is(err, fs.SkipAll) {
		return err
	}
	return nil
}

// walkEntries visits one directory's entries in name order, descending into
// each directory as it reaches it. The internal names a disk-backed namespace
// hides from a listing are skipped here too, so every namespace walks alike.
func walkEntries(ctx context.Context, fsys VFS, entries []FileInfo, visit WalkFunc) error {
	slices.SortFunc(entries, func(a, b FileInfo) int { return strings.Compare(a.Name, b.Name) })
	for _, fi := range entries {
		if err := ctx.Err(); err != nil {
			return err
		}
		if storageutil.IsInternalName(fi.Name) {
			continue
		}
		err := visit(fi)
		if errors.Is(err, fs.SkipDir) {
			continue
		}
		if err != nil {
			return err
		}
		if !fi.IsDir {
			continue
		}
		children, err := fsys.List(ctx, fi.Path, nil)
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			// An unreadable subtree is skipped, not fatal.
			continue
		}
		if err := walkEntries(ctx, fsys, children, visit); err != nil {
			return err
		}
	}
	return nil
}

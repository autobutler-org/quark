package searchutil

import (
	"context"
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/vfs"
)

func backfillTree(ctx context.Context, params BackfillTreeParams) (BackfillResult, error) {
	var result BackfillResult
	if params.FS == nil {
		return result, nil
	}
	walkErr := vfs.Walk(ctx, params.FS, "", func(fi vfs.FileInfo) error {
		if fi.IsDir {
			return nil
		}
		result.Scanned++
		if !IsIndexable(fi.Path) {
			return nil
		}
		text, err := extractFile(ctx, params.FS, fi.Path)
		if err != nil {
			result.Failed++
			return nil
		}
		if text == "" {
			return nil
		}
		if err := UpsertContent(ctx, params.DB, params.Serial, fi.Path, text); err != nil {
			result.Failed++
			return nil
		}
		result.Indexed++
		return nil
	})
	switch {
	case walkErr == nil, errors.Is(walkErr, context.Canceled):
		return result, nil
	case errors.Is(walkErr, vfs.ErrNotFound):
		// A device that is not currently mounted is not an error worth
		// failing startup over.
		return result, nil
	}
	return result, fmt.Errorf("backfill walk of serial %q: %w", params.Serial, walkErr)
}

// extractFile opens relPath in fsys and extracts its text.
func extractFile(ctx context.Context, fsys vfs.VFS, relPath string) (string, error) {
	f, err := fsys.Open(ctx, relPath)
	if err != nil {
		return "", err
	}
	defer func() { _ = f.Close() }()
	return ExtractText(relPath, f), nil
}

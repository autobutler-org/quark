package searchutil

import (
	"context"
	"database/sql"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// BackfillTree walks filesDir and indexes the contents of every indexable
// file beneath it, attributing them to serial.
//
// The content index is kept in sync by file events, which only covers files
// written after the indexer starts. This pass is what makes files that were
// already on disk searchable, so it must run at least once per device — at
// startup, or after a change to what ExtractText understands.
//
// Every file is re-extracted rather than skipped by timestamp. That costs a
// re-read of each file per pass, which is cheap at MaxExtractBytes, and it
// means improvements to extraction are picked up on the next run instead of
// silently applying only to newly written files.
//
// The walk is best-effort: unreadable files and failed inserts are counted in
// the result and skipped. An error is returned only when the walk itself
// cannot proceed, and ctx cancellation stops it early.
func BackfillTree(ctx context.Context, db *sql.DB, serial, filesDir string) (BackfillResult, error) {
	var result BackfillResult
	if filesDir == "" {
		return result, nil
	}
	if _, err := os.Stat(filesDir); err != nil {
		// A device that is not currently mounted is not an error worth
		// failing startup over.
		return result, nil
	}

	walkErr := filepath.WalkDir(filesDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// Skip subtrees we cannot read rather than abandoning the walk.
			if d != nil && d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if d.IsDir() {
			// Trashed files stay on disk but must not surface in search.
			if d.Name() == trashDirName {
				return fs.SkipDir
			}
			return nil
		}
		result.Scanned++
		if !IsIndexable(path) {
			return nil
		}
		text := ExtractText(path)
		if text == "" {
			return nil
		}
		relPath, relErr := filepath.Rel(filesDir, path)
		if relErr != nil {
			result.Failed++
			return nil
		}
		// The index stores forward-slash paths so they match the relative
		// paths carried on file events.
		relPath = filepath.ToSlash(relPath)
		if err := UpsertContent(ctx, db, serial, relPath, text); err != nil {
			result.Failed++
			return nil
		}
		result.Indexed++
		return nil
	})
	if walkErr != nil && !strings.Contains(walkErr.Error(), context.Canceled.Error()) {
		return result, fmt.Errorf("backfill walk %s: %w", filesDir, walkErr)
	}
	return result, nil
}

// trashDirName mirrors the name storageutil.IsInternalName reserves inside a
// files directory. The trash itself moved beside FilesDir (#2173); this skips
// an old one that has not been moved out yet. It is duplicated to keep
// searchutil free of a dependency on storageutil, which imports far more than
// this package needs.
const trashDirName = ".trash"

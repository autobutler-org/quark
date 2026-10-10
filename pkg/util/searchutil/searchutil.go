// Package searchutil provides text extraction and full-text search over
// indexed file contents using SQLite FTS5.
//
// Supported for text extraction (in order of fidelity):
//   - Quark documents (.qdoc), spreadsheets (.qsheet) and presentations
//     (.qslide): the prose is pulled out of the JSON envelope so the index
//     holds readable text rather than markup (see extractDelta, extractSheet
//     and extractSlides)
//   - Plaintext files (.txt, .md, .csv, .log, .yaml, .yml, .toml, .json, .xml,
//     .html, .htm, .ini, .cfg, .conf, .sh, .py, .go, .js, .ts, .css, .sql)
//   - All other files: content is not indexed (empty string returned)
//
// EPUB and PDF extraction is not yet implemented — tracked in #1339. Adding
// them only requires extending ExtractText without any schema changes.
package searchutil

import (
	"context"
	"database/sql"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// MaxExtractBytes is the maximum number of bytes read from a file for indexing.
// Files larger than this are truncated at a UTF-8 boundary to avoid storing
// enormous documents in the search index.
const MaxExtractBytes = 512 * 1024 // 512 KB

// DefaultLimit is the maximum number of results returned by Search when the
// caller does not specify a limit.
const DefaultLimit = 50

// MaxLimit is the largest page a caller may ask for. A search that wants more
// hits than this wants a different query.
const MaxLimit = 200

// ParseLimit reads a requested result limit, falling back to DefaultLimit for
// anything missing or unparseable and clamping the page to MaxLimit.
func ParseLimit(raw string) int {
	n, err := strconv.Atoi(raw)
	if err != nil {
		return DefaultLimit
	}
	return clampLimit(n)
}

// BackfillResult reports what a BackfillTree pass did.
type BackfillResult struct {
	// Scanned is the number of files visited, indexable or not.
	Scanned int
	// Indexed is the number of files whose contents were written to the index.
	Indexed int
	// Failed is the number of files that could not be indexed. Individual
	// errors do not abort the walk.
	Failed int
}

// SearchResult is a single FTS5 search hit.
type SearchResult struct {
	// Serial is the storage device serial that holds the file.
	Serial string `json:"serial"`
	// RelPath is the relative path of the file within the device's FilesDir.
	RelPath string `json:"relPath"`
	// Snippet is a highlighted excerpt from the matched content.
	// Matched terms are wrapped in <b>…</b>. The caller is responsible for
	// sanitizing this before rendering in HTML (the excerpt is derived from
	// file contents, not user input, but treat it with care).
	Snippet string `json:"snippet"`
}

// IsIndexable reports whether the file at path is eligible for content
// extraction based on its extension. It does not read the file.
func IsIndexable(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	return extractableExtensions[ext]
}

// UpsertContent indexes the extracted text for a file. If the file was
// previously indexed, its entry is updated. Callers should call ExtractText
// first and skip calling this function when the result is empty.
func UpsertContent(ctx context.Context, sqlDB *sql.DB, serial, relPath, extracted string) error {
	return db.New(sqlDB).UpsertFileContent(ctx, db.UpsertFileContentParams{
		Serial:    serial,
		RelPath:   relPath,
		Extracted: extracted,
	})
}

// DeleteContent removes the index entry for a specific file.
func DeleteContent(ctx context.Context, sqlDB *sql.DB, serial, relPath string) error {
	return db.New(sqlDB).DeleteFileContent(ctx, db.DeleteFileContentParams{
		Serial:  serial,
		RelPath: relPath,
	})
}

// DeleteContentBySerial removes all index entries for a storage device.
// Call this when a device is removed.
func DeleteContentBySerial(ctx context.Context, sqlDB *sql.DB, serial string) error {
	return db.New(sqlDB).DeleteFileContentBySerial(ctx, serial)
}

// IndexFile extracts the text of the file at relPath in fsys, the files
// namespace of the device with serial, and upserts it into the index. A file
// that is not indexable (a non-text format) is never opened, and one in the
// trash is never indexed: both are no-ops.
func IndexFile(ctx context.Context, sqlDB *sql.DB, fsys vfs.VFS, serial, relPath string) error {
	if !IsIndexable(relPath) || storageutil.IsTrashPath(relPath) {
		return nil
	}
	text, err := extractFile(ctx, fsys, relPath)
	if err != nil || text == "" {
		return err
	}
	return UpsertContent(ctx, sqlDB, serial, relPath, text)
}

// IndexFileWithTimeout is like IndexFile but cancels extraction after d.
func IndexFileWithTimeout(sqlDB *sql.DB, fsys vfs.VFS, serial, relPath string, d time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()
	return IndexFile(ctx, sqlDB, fsys, serial, relPath)
}

// BackfillTreeParams names the device whose files BackfillTree indexes.
type BackfillTreeParams struct {
	// DB holds the content index.
	DB *sql.DB
	// Serial is the device's serial, empty for the internal drive.
	Serial string
	// FS is the device's files namespace.
	FS vfs.VFS
}

// BackfillTree walks the device's files namespace and indexes the contents of
// every indexable file in it, attributing them to its serial.
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
// The walk streams through vfs.Walk and is best-effort: an unreadable subtree
// is skipped, and unreadable files and failed inserts are counted in the
// result and skipped. The trash is never walked. An error is returned only
// when the walk itself cannot proceed, and ctx cancellation stops it early.
func BackfillTree(ctx context.Context, params BackfillTreeParams) (BackfillResult, error) {
	return backfillTree(ctx, params)
}

package searchutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/vfs"
	_ "modernc.org/sqlite"
)

// --- schema setup ---

func newTestDB(t *testing.T) *sql.DB {
	t.Helper()
	return dbtest.NewDB(t).Db
}

// --- IsIndexable ---

func TestIsIndexable(t *testing.T) {
	cases := []struct {
		path     string
		expected bool
	}{
		{"readme.md", true},
		{"notes.txt", true},
		{"data.csv", true},
		{"config.yaml", true},
		{"config.yml", true},
		{"config.toml", true},
		{"data.json", true},
		{"index.html", true},
		{"style.css", true},
		{"script.js", true},
		{"script.ts", true},
		{"photo.jpg", false},
		{"video.mp4", false},
		{"binary.exe", false},
		{"archive.zip", false},
		{"image.png", false},
		{"document.pdf", false}, // not yet implemented
	}
	for _, c := range cases {
		got := IsIndexable(c.path)
		if got != c.expected {
			t.Errorf("IsIndexable(%q) = %v, want %v", c.path, got, c.expected)
		}
	}
}

func TestIsIndexable_CaseInsensitive(t *testing.T) {
	if !IsIndexable("README.MD") {
		t.Error("IsIndexable should be case-insensitive for .MD")
	}
	if !IsIndexable("NOTES.TXT") {
		t.Error("IsIndexable should be case-insensitive for .TXT")
	}
}

// --- ExtractText ---

func TestExtractText_PlainText(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "hello.txt")
	if err := os.WriteFile(path, []byte("hello world"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	got := extractTemp(t, path)
	if got != "hello world" {
		t.Errorf("ExtractText = %q, want %q", got, "hello world")
	}
}

func TestExtractText_NonIndexable(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "photo.jpg")
	if err := os.WriteFile(path, []byte("fake jpeg"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	got := extractTemp(t, path)
	if got != "" {
		t.Errorf("ExtractText of non-indexable file should return \"\", got %q", got)
	}
}

// A file of any size costs at most MaxExtractBytes of reading: the reader is
// never drained past the cap.
func TestExtractText_Truncation(t *testing.T) {
	r := &countingReader{}
	got := ExtractText("big.txt", r)
	if len(got) > MaxExtractBytes {
		t.Errorf("ExtractText returned %d bytes, want <= %d", len(got), MaxExtractBytes)
	}
	if r.n > MaxExtractBytes {
		t.Errorf("ExtractText read %d bytes, want <= %d", r.n, MaxExtractBytes)
	}
}

// countingReader is an endless stream of 'a' that counts what was read.
type countingReader struct{ n int }

func (r *countingReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'a'
	}
	r.n += len(p)
	return len(p), nil
}

// --- IndexFile ---

// failOpenVFS is a namespace whose every Open fails, to prove a file is never
// opened.
type failOpenVFS struct{ vfs.VFS }

func (failOpenVFS) Open(context.Context, string) (vfs.File, error) {
	return nil, errors.New("opened")
}

func TestIndexFile(t *testing.T) {
	ctx := context.Background()
	db := newTestDB(t)
	mem := vfs.NewMemVFS("files")
	if err := mem.Write(ctx, "docs/plan.md", strings.NewReader("echo"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := IndexFile(ctx, db, mem, "", "docs/plan.md"); err != nil {
		t.Fatalf("IndexFile: %v", err)
	}
	hits, err := Search(ctx, db, "echo", 10)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(hits) != 1 || hits[0].RelPath != "docs/plan.md" {
		t.Errorf("hits = %+v, want docs/plan.md", hits)
	}

	if err := IndexFile(ctx, db, mem, "", "docs/missing.md"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("IndexFile(missing) = %v, want ErrNotFound", err)
	}
	// Neither a binary file nor anything in the trash is opened.
	for _, p := range []string{"photo.jpg", ".trash/20240101T000000Z_ab_x.md"} {
		if err := IndexFile(ctx, db, failOpenVFS{mem}, "", p); err != nil {
			t.Errorf("IndexFile(%s) = %v, want a no-op", p, err)
		}
	}
}

// --- sanitizeFTSQuery ---

func TestSanitizeFTSQuery_PlainTerm(t *testing.T) {
	got := sanitizeFTSQuery("hello")
	if !strings.HasPrefix(got, `"`) || !strings.HasSuffix(got, `"`) {
		t.Errorf("plain term should be quoted, got %q", got)
	}
}

func TestSanitizeFTSQuery_WithOperator(t *testing.T) {
	q := "hello AND world"
	got := sanitizeFTSQuery(q)
	if got != q {
		t.Errorf("operator query should pass through unchanged, got %q", got)
	}
}

func TestSanitizeFTSQuery_WithPrefix(t *testing.T) {
	q := "hel*"
	got := sanitizeFTSQuery(q)
	if got != q {
		t.Errorf("prefix query should pass through, got %q", got)
	}
}

func TestSanitizeFTSQuery_Empty(t *testing.T) {
	got := sanitizeFTSQuery("")
	if got == "" {
		t.Error("empty query should not return empty string (FTS5 syntax error)")
	}
}

// --- UpsertContent / Search / DeleteContent ---

func TestUpsertAndSearch(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	if err := UpsertContent(ctx, db, "sda1", "notes/hello.txt", "The quick brown fox jumps"); err != nil {
		t.Fatalf("UpsertContent: %v", err)
	}

	results, err := Search(ctx, db, "quick", 10)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(results))
	}
	if results[0].Serial != "sda1" || results[0].RelPath != "notes/hello.txt" {
		t.Errorf("unexpected result: %+v", results[0])
	}
}

func TestSearch_NoResults(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	results, err := Search(ctx, db, "zzznomatch", 10)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("expected 0 results, got %d", len(results))
	}
	// Must return non-nil empty slice, not nil (JSON [] vs null).
	if results == nil {
		t.Error("Search returned nil, want non-nil empty slice")
	}
}

func TestSearch_MultipleFiles(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	if err := UpsertContent(ctx, db, "sda1", "a.txt", "golang programming language"); err != nil {
		t.Fatalf("UpsertContent a: %v", err)
	}
	if err := UpsertContent(ctx, db, "sda1", "b.txt", "python programming language"); err != nil {
		t.Fatalf("UpsertContent b: %v", err)
	}
	if err := UpsertContent(ctx, db, "sda1", "c.txt", "unrelated document"); err != nil {
		t.Fatalf("UpsertContent c: %v", err)
	}

	results, err := Search(ctx, db, "programming", 10)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 2 {
		t.Errorf("expected 2 results for 'programming', got %d", len(results))
	}
}

func TestUpsertContent_UpdatesExisting(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	if err := UpsertContent(ctx, db, "sda1", "doc.txt", "original content here"); err != nil {
		t.Fatalf("first upsert: %v", err)
	}
	if err := UpsertContent(ctx, db, "sda1", "doc.txt", "completely updated content"); err != nil {
		t.Fatalf("second upsert: %v", err)
	}

	res, _ := Search(ctx, db, "original", 10)
	if len(res) != 0 {
		t.Error("old content should not be searchable after update")
	}
	res, _ = Search(ctx, db, "updated", 10)
	if len(res) != 1 {
		t.Errorf("expected 1 result for updated content, got %d", len(res))
	}
}

func TestDeleteContent(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	if err := UpsertContent(ctx, db, "sda1", "todelete.txt", "delete me please"); err != nil {
		t.Fatalf("UpsertContent: %v", err)
	}
	if err := DeleteContent(ctx, db, "sda1", "todelete.txt"); err != nil {
		t.Fatalf("DeleteContent: %v", err)
	}

	results, _ := Search(ctx, db, "delete", 10)
	if len(results) != 0 {
		t.Errorf("expected 0 results after delete, got %d", len(results))
	}
}

func TestDeleteContentBySerial(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	if err := UpsertContent(ctx, db, "sda1", "a.txt", "device alpha content"); err != nil {
		t.Fatalf("UpsertContent sda1/a: %v", err)
	}
	if err := UpsertContent(ctx, db, "sda1", "b.txt", "device alpha second file"); err != nil {
		t.Fatalf("UpsertContent sda1/b: %v", err)
	}
	if err := UpsertContent(ctx, db, "sdb1", "c.txt", "device beta content"); err != nil {
		t.Fatalf("UpsertContent sdb1/c: %v", err)
	}

	if err := DeleteContentBySerial(ctx, db, "sda1"); err != nil {
		t.Fatalf("DeleteContentBySerial: %v", err)
	}

	// sda1 files gone
	res, _ := Search(ctx, db, "alpha", 10)
	if len(res) != 0 {
		t.Errorf("expected no results for sda1 after DeleteContentBySerial, got %d", len(res))
	}
	// sdb1 file still present
	res, _ = Search(ctx, db, "beta", 10)
	if len(res) != 1 {
		t.Errorf("expected sdb1 file to survive, got %d results", len(res))
	}
}

func TestSearch_LimitRespected(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	for i := 0; i < 10; i++ {
		if err := UpsertContent(ctx, db, "dev", strings.Repeat("x", i+1)+".txt",
			"common keyword here"); err != nil {
			t.Fatalf("UpsertContent %d: %v", i, err)
		}
	}

	results, err := Search(ctx, db, "keyword", 3)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) > 3 {
		t.Errorf("expected <= 3 results, got %d", len(results))
	}
}

func TestSearch_LimitClampedToMax(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	for i := 0; i < MaxLimit+5; i++ {
		if err := UpsertContent(ctx, db, "dev", fmt.Sprintf("f%d.txt", i),
			"common keyword here"); err != nil {
			t.Fatalf("UpsertContent %d: %v", i, err)
		}
	}

	results, err := Search(ctx, db, "keyword", math.MaxInt)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != MaxLimit {
		t.Errorf("expected %d results, got %d", MaxLimit, len(results))
	}
}

// --- driver capability guard ---

// TestSQLiteDriverHasFTS5 asserts that the SQLite driver this binary is linked
// against actually provides the fts5 module.
//
// Nothing in this package can work without it: migration 006 creates a virtual
// table USING fts5, so an FTS5-less driver fails at boot with
// "no such module: fts5" rather than at build time.
//
// modernc.org/sqlite (the current driver) compiles FTS5 in unconditionally, so
// this passes today. The point is to catch a driver swap — notably to
// mattn/go-sqlite3, where FTS5 is opt-in behind the `sqlite_fts5` build tag —
// as a red CI run instead of a broken device in the field.
func TestSQLiteDriverHasFTS5(t *testing.T) {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	var enabled bool
	if err := db.QueryRow(
		`SELECT EXISTS(SELECT 1 FROM pragma_compile_options() WHERE compile_options = 'ENABLE_FTS5')`,
	).Scan(&enabled); err != nil {
		t.Fatalf("read compile options: %v", err)
	}
	if !enabled {
		t.Error("ENABLE_FTS5 missing from sqlite compile options")
	}

	// The compile flag is necessary but not sufficient — prove the module
	// registers and the tokenizer used by migration 006 is accepted.
	if _, err := db.Exec(
		`CREATE VIRTUAL TABLE fts_probe USING fts5(body, tokenize='porter unicode61')`,
	); err != nil {
		t.Fatalf("create fts5 table: %v", err)
	}
}

// TestFTS5PorterStemming pins the stemming behavior Search relies on: a query
// for "run" must match stored text containing "running". Without the porter
// tokenizer this silently degrades to exact-token matching, which returns no
// results and looks like an empty index rather than a broken one.
func TestFTS5PorterStemming(t *testing.T) {
	db := newTestDB(t)
	ctx := context.Background()

	if err := UpsertContent(ctx, db, "dev", "notes.txt", "the servers were running fast"); err != nil {
		t.Fatalf("UpsertContent: %v", err)
	}

	results, err := Search(ctx, db, "run", 10)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(results) != 1 {
		t.Fatalf("porter stemming broken: query %q matched %d docs, want 1", "run", len(results))
	}
	if !strings.Contains(results[0].Snippet, "running") {
		t.Errorf("expected snippet to contain the stemmed match, got %q", results[0].Snippet)
	}
}

func TestParseLimit(t *testing.T) {
	cases := []struct {
		raw  string
		want int
	}{
		{"", DefaultLimit},
		{"25", 25},
		{"200", MaxLimit},
		{"1000", MaxLimit},
		{"0", DefaultLimit},
		{"-1", DefaultLimit},
		{"abc", DefaultLimit},
	}
	for _, tc := range cases {
		if got := ParseLimit(tc.raw); got != tc.want {
			t.Errorf("ParseLimit(%q) = %d, want %d", tc.raw, got, tc.want)
		}
	}
}

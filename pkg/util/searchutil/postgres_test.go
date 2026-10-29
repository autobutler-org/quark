package searchutil

import (
	"context"
	"database/sql"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// searchCorpus is the files both engines index for the content search tests,
// the texts the SQLite-only tests in searchutil_test.go search. The last two
// are for ranking: one says "keyword" four times in a few words, the other
// once among many.
var searchCorpus = []struct{ serial, relPath, text string }{
	{"sda1", "notes/hello.txt", "The quick brown fox jumps"},
	{"sda1", "a.txt", "golang programming language"},
	{"sda1", "b.txt", "python programming language"},
	{"sda1", "c.txt", "unrelated document"},
	{"sdb1", "notes.txt", "the servers were running fast"},
	{"sdc1", "dense.txt", "keyword keyword keyword keyword report"},
	{"sdc1", "sparse.txt", "keyword " + strings.Repeat("garden river mountain lantern harbor ", 10)},
}

// searchCases are a query each and the files it finds, best ranked first
// where order is part of the expectation.
var searchCases = []struct {
	query   string
	want    []string
	ordered bool
}{
	{query: "quick", want: []string{"notes/hello.txt"}},
	{query: "zzznomatch", want: []string{}},
	{query: "programming", want: []string{"a.txt", "b.txt"}},
	// Stemming: "run" finds "running" on both.
	{query: "run", want: []string{"notes.txt"}},
	// Plain text is one phrase: in order, side by side.
	{query: "brown fox", want: []string{"notes/hello.txt"}},
	{query: "language programming", want: []string{}},
	{query: `"programming language"`, want: []string{"a.txt", "b.txt"}},
	{query: "golang OR python", want: []string{"a.txt", "b.txt"}},
	{query: "programming NOT python", want: []string{"a.txt"}},
	{query: "fox AND jumps", want: []string{"notes/hello.txt"}},
	{query: "keyword", want: []string{"dense.txt", "sparse.txt"}, ordered: true},
	{query: "", want: []string{}},
}

// indexCorpus writes searchCorpus into sqlDB's content index.
func indexCorpus(t *testing.T, sqlDB *sql.DB) {
	t.Helper()
	for _, f := range searchCorpus {
		if err := UpsertContent(context.Background(), sqlDB, f.serial, f.relPath, f.text); err != nil {
			t.Fatalf("UpsertContent %s: %v", f.relPath, err)
		}
	}
}

// searchPaths runs one search and returns the paths it found, in rank order.
func searchPaths(t *testing.T, sqlDB *sql.DB, query string, limit int) []string {
	t.Helper()
	results, err := Search(context.Background(), sqlDB, query, limit)
	if err != nil {
		t.Fatalf("Search(%q): %v", query, err)
	}
	paths := []string{}
	for _, r := range results {
		paths = append(paths, r.RelPath)
	}
	return paths
}

// Content search finds the same files on both engines for the same query
// (#2958). Ranking is a different formula on each (docs/architecture/data.md),
// so order is held only where both formulas clearly agree, and logged.
func TestContentSearchMatchesOnBothEngines(t *testing.T) {
	postgres, err := db.ConnectToPostgres(dbtest.PostgresURL(t))
	if err != nil {
		t.Fatalf("ConnectToPostgres: %v", err)
	}
	t.Cleanup(func() { postgres.Db.Close() })
	engines := map[string]*sql.DB{"SQLite": newTestDB(t), "PostgreSQL": postgres.Db}
	for _, sqlDB := range engines {
		indexCorpus(t, sqlDB)
	}

	for _, c := range searchCases {
		for name, sqlDB := range engines {
			got := searchPaths(t, sqlDB, c.query, 10)
			sorted := slices.Clone(got)
			if !c.ordered {
				slices.Sort(sorted)
			}
			if !slices.Equal(sorted, c.want) {
				t.Errorf("%s: Search(%q) = %v, want %v", name, c.query, got, c.want)
			}
			t.Logf("%s: Search(%q) ranks %v", name, c.query, got)
		}
	}

	for name, sqlDB := range engines {
		results, err := Search(context.Background(), sqlDB, "running", 10)
		if err != nil || len(results) != 1 || !strings.Contains(results[0].Snippet, "<b>running</b>") {
			t.Errorf("%s: Search(running) = %+v, %v; want one hit with the match in bold", name, results, err)
		}
		if got := searchPaths(t, sqlDB, "programming", 1); len(got) != 1 {
			t.Errorf("%s: Search(programming, limit 1) = %v, want one hit", name, got)
		}
	}
}

// The generated tsvector follows the text through an update and is gone with
// the row, as 006's triggers keep FTS5 in step on SQLite.
func TestContentSearchOnPostgresFollowsWrites(t *testing.T) {
	database, err := db.ConnectToPostgres(dbtest.PostgresURL(t))
	if err != nil {
		t.Fatalf("ConnectToPostgres: %v", err)
	}
	t.Cleanup(func() { database.Db.Close() })
	ctx := context.Background()
	sqlDB := database.Db
	indexCorpus(t, sqlDB)

	if err := UpsertContent(ctx, sqlDB, "sda1", "a.txt", "completely updated content"); err != nil {
		t.Fatalf("UpsertContent: %v", err)
	}
	if got := searchPaths(t, sqlDB, "golang", 10); len(got) != 0 {
		t.Errorf("old text still found after an update: %v", got)
	}
	if got := searchPaths(t, sqlDB, "updated", 10); !slices.Equal(got, []string{"a.txt"}) {
		t.Errorf("Search(updated) = %v, want [a.txt]", got)
	}
	var rows int
	if err := sqlDB.QueryRow(`SELECT COUNT(*) FROM file_content WHERE serial = 'sda1'`).Scan(&rows); err != nil || rows != 4 {
		t.Errorf("sda1 holds %d rows after re-indexing one of four (%v), want 4", rows, err)
	}

	if err := DeleteContent(ctx, sqlDB, "sda1", "notes/hello.txt"); err != nil {
		t.Fatalf("DeleteContent: %v", err)
	}
	if got := searchPaths(t, sqlDB, "quick", 10); len(got) != 0 {
		t.Errorf("Search(quick) after DeleteContent = %v, want none", got)
	}
	if err := DeleteContentBySerial(ctx, sqlDB, "sdb1"); err != nil {
		t.Fatalf("DeleteContentBySerial: %v", err)
	}
	if got := searchPaths(t, sqlDB, "running", 10); len(got) != 0 {
		t.Errorf("Search(running) after DeleteContentBySerial = %v, want none", got)
	}
}

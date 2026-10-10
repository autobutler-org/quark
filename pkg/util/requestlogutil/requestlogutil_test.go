package requestlogutil_test

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/requestlogutil"
)

var decidedAt = time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)

func appendEntry(t *testing.T, queries *db.Queries, entry requestlogutil.Entry) {
	t.Helper()
	if _, err := requestlogutil.Append(context.Background(), requestlogutil.AppendParams{Queries: queries, Entry: entry}); err != nil {
		t.Fatalf("Append(%+v): %v", entry, err)
	}
}

func list(t *testing.T, queries *db.Queries) []requestlogutil.Entry {
	t.Helper()
	result, err := requestlogutil.List(context.Background(), requestlogutil.ListParams{Queries: queries})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	return result.Entries
}

// importFile runs Import against dataDir and returns how many decisions the
// file held.
func importFile(t *testing.T, queries *db.Queries, dataDir string) int {
	t.Helper()
	result, err := requestlogutil.Import(context.Background(), requestlogutil.ImportParams{Queries: queries, DataDir: dataDir})
	if err != nil {
		t.Fatalf("Import: %v", err)
	}
	return result.Entries
}

// TestList_NoDecisionsIsEmpty checks a Quark that has decided nothing lists an
// empty, non-nil history, which goes out as [] rather than null.
func TestList_NoDecisionsIsEmpty(t *testing.T) {
	entries := list(t, dbtest.NewDB(t).Queries)
	if entries == nil || len(entries) != 0 {
		t.Errorf("List with no decisions = %#v, want an empty slice", entries)
	}
}

// TestAppend_ListsNewestFirst checks decisions come back whole and newest
// first.
func TestAppend_ListsNewestFirst(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	approved := requestlogutil.Entry{Username: "waiting", Outcome: requestlogutil.OutcomeApproved, DecidedBy: "admin", DecidedAt: decidedAt}
	denied := requestlogutil.Entry{Username: "asker", Outcome: requestlogutil.OutcomeDenied, DecidedBy: "other-admin", DecidedAt: decidedAt.Add(time.Minute)}
	appendEntry(t, queries, approved)
	appendEntry(t, queries, denied)

	entries := list(t, queries)
	if len(entries) != 2 || entries[0] != denied || entries[1] != approved {
		t.Errorf("List = %+v, want %+v then %+v", entries, denied, approved)
	}
}

// TestAppend_KeepsTheLastMaxEntries checks the history drops its oldest
// decisions once it is full.
func TestAppend_KeepsTheLastMaxEntries(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	const extra = 5
	for i := range requestlogutil.MaxEntries + extra {
		appendEntry(t, queries, requestlogutil.Entry{Username: fmt.Sprintf("user%d", i), Outcome: requestlogutil.OutcomeDenied, DecidedBy: "admin", DecidedAt: decidedAt})
	}

	entries := list(t, queries)
	if len(entries) != requestlogutil.MaxEntries {
		t.Fatalf("kept %d entries, want %d", len(entries), requestlogutil.MaxEntries)
	}
	if got, want := entries[0].Username, fmt.Sprintf("user%d", requestlogutil.MaxEntries+extra-1); got != want {
		t.Errorf("newest = %q, want %q", got, want)
	}
	if got, want := entries[len(entries)-1].Username, fmt.Sprintf("user%d", extra); got != want {
		t.Errorf("oldest kept = %q, want %q", got, want)
	}
}

// TestImport_MovesTheFileIntoTheDatabase checks the legacy file lands oldest
// first with its damaged line skipped, that the file is renamed, that a
// decision already in the database is kept once, and that importing again,
// from the renamed file or from a copy put back, adds nothing.
func TestImport_MovesTheFileIntoTheDatabase(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	dataDir := t.TempDir()
	path := filepath.Join(dataDir, "account-request-history.jsonl")
	const file = `{"username":"first","outcome":"approved","decidedBy":"admin","decidedAt":"2026-10-09T12:00:00Z"}
{not json
{"username":"second","outcome":"denied","decidedBy":"admin","decidedAt":"2026-10-09T12:01:00.5Z"}
`
	if err := os.WriteFile(path, []byte(file), 0o600); err != nil {
		t.Fatal(err)
	}
	// Already recorded by this build: the file's copy of it adds nothing.
	appendEntry(t, queries, requestlogutil.Entry{Username: "first", Outcome: requestlogutil.OutcomeApproved, DecidedBy: "admin", DecidedAt: decidedAt})

	if n := importFile(t, queries, dataDir); n != 2 {
		t.Errorf("Import read %d decisions, want 2", n)
	}
	entries := list(t, queries)
	if len(entries) != 2 || entries[0].Username != "second" || entries[1].Username != "first" {
		t.Fatalf("List after Import = %+v, want second then first", entries)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("the legacy file is still there (stat err %v)", err)
	}
	if _, err := os.Stat(path + ".imported"); err != nil {
		t.Errorf("the legacy file was not renamed: %v", err)
	}

	if n := importFile(t, queries, dataDir); n != 0 {
		t.Errorf("a second Import read %d decisions, want 0", n)
	}
	if err := os.WriteFile(path, []byte(file), 0o600); err != nil {
		t.Fatal(err)
	}
	importFile(t, queries, dataDir)
	if entries := list(t, queries); len(entries) != 2 {
		t.Errorf("List after importing the same file again = %+v, want the same 2", entries)
	}
}

// TestImport_NoFileIsNothingToDo checks a Quark with no legacy file imports
// nothing and is not an error.
func TestImport_NoFileIsNothingToDo(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	if n := importFile(t, queries, t.TempDir()); n != 0 {
		t.Errorf("Import with no file read %d decisions", n)
	}
	if entries := list(t, queries); len(entries) != 0 {
		t.Errorf("List = %+v, want none", entries)
	}
}

// twoInstances returns two handles on one migrated database file, as two
// server instances on one database would hold.
func twoInstances(t *testing.T) (*db.Queries, *db.Queries) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "quark.db")
	open := func() *sql.DB {
		sqlDB, err := sql.Open("sqlite", db.DSN(path))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { sqlDB.Close() })
		return sqlDB
	}
	first, second := open(), open()
	if err := db.ResetDatabase(&db.DatabaseSqlc{Db: first, Queries: db.New(first)}); err != nil {
		t.Fatal(err)
	}
	return db.New(first), db.New(second)
}

// TestAppend_TwoInstancesShareTheHistory checks a decision recorded by one
// instance is listed by the other, and that both count toward one history.
func TestAppend_TwoInstancesShareTheHistory(t *testing.T) {
	first, second := twoInstances(t)
	appendEntry(t, first, requestlogutil.Entry{Username: "waiting", Outcome: requestlogutil.OutcomeApproved, DecidedBy: "admin", DecidedAt: decidedAt})
	appendEntry(t, second, requestlogutil.Entry{Username: "asker", Outcome: requestlogutil.OutcomeDenied, DecidedBy: "other-admin", DecidedAt: decidedAt})

	for name, queries := range map[string]*db.Queries{"first": first, "second": second} {
		entries := list(t, queries)
		if len(entries) != 2 || entries[0].Username != "asker" || entries[1].Username != "waiting" {
			t.Errorf("%s instance lists %+v, want asker then waiting", name, entries)
		}
	}
}

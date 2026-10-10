package requestlogutil_test

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/requestlogutil"
)

var decidedAt = time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)

func appendEntry(t *testing.T, dataDir string, entry requestlogutil.Entry) {
	t.Helper()
	if _, err := requestlogutil.Append(requestlogutil.AppendParams{DataDir: dataDir, Entry: entry}); err != nil {
		t.Fatalf("Append(%+v): %v", entry, err)
	}
}

func list(t *testing.T, dataDir string) []requestlogutil.Entry {
	t.Helper()
	result, err := requestlogutil.List(requestlogutil.ListParams{DataDir: dataDir})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	return result.Entries
}

// TestList_NoFileIsEmpty checks a Quark that has decided nothing lists an
// empty, non-nil history, which goes out as [] rather than null.
func TestList_NoFileIsEmpty(t *testing.T) {
	entries := list(t, t.TempDir())
	if entries == nil || len(entries) != 0 {
		t.Errorf("List with no file = %#v, want an empty slice", entries)
	}
}

// TestAppend_ListsNewestFirst checks decisions come back whole and newest
// first, from a file only its owner can read, in a data directory Append made.
func TestAppend_ListsNewestFirst(t *testing.T) {
	dataDir := t.TempDir() + "/data"
	approved := requestlogutil.Entry{Username: "waiting", Outcome: requestlogutil.OutcomeApproved, DecidedBy: "admin", DecidedAt: decidedAt}
	denied := requestlogutil.Entry{Username: "asker", Outcome: requestlogutil.OutcomeDenied, DecidedBy: "other-admin", DecidedAt: decidedAt.Add(time.Minute)}
	appendEntry(t, dataDir, approved)
	appendEntry(t, dataDir, denied)

	entries := list(t, dataDir)
	if len(entries) != 2 || entries[0] != denied || entries[1] != approved {
		t.Errorf("List = %+v, want %+v then %+v", entries, denied, approved)
	}
	info, err := os.Stat(requestlogutil.Path(dataDir))
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("history file mode = %o, want 600", perm)
	}
}

// TestAppend_KeepsTheLastMaxEntries checks the history drops its oldest
// decisions once it is full.
func TestAppend_KeepsTheLastMaxEntries(t *testing.T) {
	dataDir := t.TempDir()
	const extra = 5
	for i := range requestlogutil.MaxEntries + extra {
		appendEntry(t, dataDir, requestlogutil.Entry{Username: fmt.Sprintf("user%d", i), Outcome: requestlogutil.OutcomeDenied, DecidedBy: "admin", DecidedAt: decidedAt})
	}

	entries := list(t, dataDir)
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

// TestList_SkipsDamagedLines checks one line that does not parse neither hides
// the decisions around it nor stops the next one being recorded.
func TestList_SkipsDamagedLines(t *testing.T) {
	dataDir := t.TempDir()
	appendEntry(t, dataDir, requestlogutil.Entry{Username: "first", Outcome: requestlogutil.OutcomeApproved, DecidedBy: "admin", DecidedAt: decidedAt})
	f, err := os.OpenFile(requestlogutil.Path(dataDir), os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString("{not json\n"); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	appendEntry(t, dataDir, requestlogutil.Entry{Username: "second", Outcome: requestlogutil.OutcomeDenied, DecidedBy: "admin", DecidedAt: decidedAt})

	entries := list(t, dataDir)
	if len(entries) != 2 || entries[0].Username != "second" || entries[1].Username != "first" {
		t.Errorf("List = %+v, want second then first", entries)
	}
}

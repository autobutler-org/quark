package backup

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// lastSnapshot is LastSnapshot, failing the test on an error.
func lastSnapshot(t *testing.T, queries *db.Queries) time.Time {
	t.Helper()
	at, err := LastSnapshot(context.Background(), queries)
	if err != nil {
		t.Fatal(err)
	}
	return at
}

// writeLegacyRecord writes the record file of an older Quark and returns its
// path.
func writeLegacyRecord(t *testing.T, dataDir, content string) string {
	t.Helper()
	path := filepath.Join(dataDir, lastSnapshotFilename)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLastSnapshot_NoRecord(t *testing.T) {
	if at := lastSnapshot(t, dbtest.NewDB(t).Queries); !at.IsZero() {
		t.Errorf("LastSnapshot = %v, want the zero time", at)
	}
}

func TestLastSnapshot_UnreadableRecordIsNoRecord(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	for _, value := range []string{`"not a time"`, `not JSON`, `7`} {
		if err := queries.SetSetting(context.Background(), db.SetSettingParams{Key: lastSnapshotKey, Value: value}); err != nil {
			t.Fatal(err)
		}
		if at := lastSnapshot(t, queries); !at.IsZero() {
			t.Errorf("LastSnapshot of %s = %v, want the zero time", value, at)
		}
	}
}

// TestRecordSnapshot_RoundTrip checks a recorded time is read back, that the
// row holds it as a JSON string like every other setting, and that a later
// record replaces it.
func TestRecordSnapshot_RoundTrip(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	ctx := context.Background()
	want := time.Date(2026, 10, 9, 12, 30, 0, 0, time.UTC)
	if err := RecordSnapshot(ctx, queries, want.In(time.FixedZone("west", -7*60*60))); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, queries); !got.Equal(want) {
		t.Errorf("LastSnapshot = %v, want %v", got, want)
	}
	if value, err := queries.GetSetting(ctx, lastSnapshotKey); err != nil || value != `"2026-10-09T12:30:00Z"` {
		t.Errorf("stored value = %s, %v; want the JSON string of the UTC time", value, err)
	}

	later := want.Add(time.Hour)
	if err := RecordSnapshot(ctx, queries, later); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, queries); !got.Equal(later) {
		t.Errorf("LastSnapshot after a second record = %v, want %v", got, later)
	}
}

func TestSnapshotBackup_RecordsCompletion(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"file.txt": "data"})
	target := makeTarget(t)
	job := newJob("TARGET")
	queries := dbtest.NewDB(t).Queries

	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Queries:            queries,
	}, []SourceDevice{src}, target); err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	// The record keeps whole seconds.
	if got, want := lastSnapshot(t, queries), job.CompletedAt.Truncate(time.Second); !got.Equal(want) {
		t.Errorf("LastSnapshot = %v, want the job's completion time %v", got, want)
	}
}

func TestSnapshotBackup_FailedBackupRecordsNothing(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"file.txt": "data"})
	target := makeTarget(t)
	job := newJob("TARGET")
	queries := dbtest.NewDB(t).Queries

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := SnapshotBackup(ctx, SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Queries:            queries,
	}, []SourceDevice{src}, target); err == nil {
		t.Fatal("SnapshotBackup succeeded with a canceled context")
	}

	if got := lastSnapshot(t, queries); !got.IsZero() {
		t.Errorf("LastSnapshot = %v after a failed backup, want the zero time", got)
	}
}

// TestImportLastSnapshot_MovesTheFileIntoTheDatabase checks the legacy record
// is read back from the database, that the file is renamed, and that
// importing again, with nothing there or with an older file put back, changes
// nothing.
func TestImportLastSnapshot_MovesTheFileIntoTheDatabase(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	ctx := context.Background()
	dataDir := t.TempDir()
	want := time.Date(2026, 10, 9, 12, 30, 0, 0, time.UTC)
	path := writeLegacyRecord(t, dataDir, want.Format(time.RFC3339)+"\n")

	if err := ImportLastSnapshot(ctx, queries, dataDir); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, queries); !got.Equal(want) {
		t.Errorf("LastSnapshot after the import = %v, want %v", got, want)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("the legacy file is still there (stat err %v)", err)
	}
	if _, err := os.Stat(path + ".imported"); err != nil {
		t.Errorf("the legacy file was not renamed: %v", err)
	}

	if err := ImportLastSnapshot(ctx, queries, dataDir); err != nil {
		t.Fatalf("a second import with no file: %v", err)
	}
	writeLegacyRecord(t, dataDir, want.Add(-time.Hour).Format(time.RFC3339))
	if err := ImportLastSnapshot(ctx, queries, dataDir); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, queries); !got.Equal(want) {
		t.Errorf("LastSnapshot after importing again = %v, want it unchanged at %v", got, want)
	}
}

// TestImportLastSnapshot_DatabaseWins checks a time already recorded in the
// database is kept over the legacy file's.
func TestImportLastSnapshot_DatabaseWins(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	ctx := context.Background()
	dataDir := t.TempDir()
	recorded := time.Date(2026, 10, 9, 12, 30, 0, 0, time.UTC)
	if err := RecordSnapshot(ctx, queries, recorded); err != nil {
		t.Fatal(err)
	}
	writeLegacyRecord(t, dataDir, recorded.Add(-24*time.Hour).Format(time.RFC3339))

	if err := ImportLastSnapshot(ctx, queries, dataDir); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, queries); !got.Equal(recorded) {
		t.Errorf("LastSnapshot = %v, want the database's %v", got, recorded)
	}
}

// TestImportLastSnapshot_UnreadableFileImportsNothing checks a legacy file
// that holds no time stays no record, and is retired all the same.
func TestImportLastSnapshot_UnreadableFileImportsNothing(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	dataDir := t.TempDir()
	path := writeLegacyRecord(t, dataDir, "not a time")

	if err := ImportLastSnapshot(context.Background(), queries, dataDir); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, queries); !got.IsZero() {
		t.Errorf("LastSnapshot = %v, want the zero time", got)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("the unreadable legacy file is still there (stat err %v)", err)
	}
}

// TestRecordSnapshot_TwoInstancesShareTheRecord checks a snapshot recorded
// through one handle on a database is read through another, as two server
// instances on one database would.
func TestRecordSnapshot_TwoInstancesShareTheRecord(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	open := func() *sql.DB {
		sqlDB, err := sql.Open("sqlite", db.DSN(path))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { sqlDB.Close() })
		return sqlDB
	}
	firstDB, secondDB := open(), open()
	first, second := db.New(firstDB), db.New(secondDB)
	if err := db.ResetDatabase(&db.DatabaseSqlc{Db: firstDB, Queries: first}); err != nil {
		t.Fatal(err)
	}

	ctx := context.Background()
	want := time.Date(2026, 10, 9, 12, 30, 0, 0, time.UTC)
	if err := RecordSnapshot(ctx, first, want); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, second); !got.Equal(want) {
		t.Errorf("the second instance reads %v, want %v", got, want)
	}
	later := want.Add(time.Hour)
	if err := RecordSnapshot(ctx, second, later); err != nil {
		t.Fatal(err)
	}
	if got := lastSnapshot(t, first); !got.Equal(later) {
		t.Errorf("the first instance reads %v, want %v", got, later)
	}
}

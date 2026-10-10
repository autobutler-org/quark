package resetutil_test

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	_ "modernc.org/sqlite"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/resetutil"
)

// openInstance opens a handle of its own on the database at path. Two of them
// on one file are two instances serving one install, as far as the database
// can tell, until the two-instance harness (#2971) exists.
func openInstance(t *testing.T, path string) *db.DatabaseSqlc {
	t.Helper()
	sqlDB, err := sql.Open("sqlite", db.DSN(path))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	t.Cleanup(func() { sqlDB.Close() })
	return &db.DatabaseSqlc{Db: sqlDB, Queries: db.New(sqlDB)}
}

// twoInstances returns two handles on one freshly migrated database.
func twoInstances(t *testing.T) (resetting, watching *db.DatabaseSqlc) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "quark.db")
	resetting = openInstance(t, path)
	if err := db.ResetDatabase(resetting); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return resetting, openInstance(t, path)
}

// watch starts Watch on database and returns the channel OnReset closes.
func watch(t *testing.T, database *db.DatabaseSqlc) <-chan struct{} {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	reset := make(chan struct{})
	result, err := resetutil.Watch(ctx, resetutil.WatchParams{
		Queries:  database.Queries,
		Interval: 10 * time.Millisecond,
		OnReset:  func() { close(reset) },
	})
	if err != nil {
		t.Fatalf("watch: %v", err)
	}
	if result.InstallID == "" {
		t.Fatal("watch reported no install id")
	}
	return reset
}

func TestWatch_FiresWhenAnotherInstanceResetsTheDatabase(t *testing.T) {
	resetting, watching := twoInstances(t)
	reset := watch(t, watching)

	if err := db.ResetDatabase(resetting); err != nil {
		t.Fatalf("reset: %v", err)
	}
	select {
	case <-reset:
	case <-time.After(10 * time.Second):
		t.Fatal("the other instance was never told the install was reset")
	}
}

// A reset of the files or the devices alone leaves the database standing and
// rotates the id instead.
func TestWatch_FiresWhenAnotherInstanceRotatesTheInstallID(t *testing.T) {
	resetting, watching := twoInstances(t)
	reset := watch(t, watching)

	if err := resetting.Queries.RotateInstallID(t.Context()); err != nil {
		t.Fatalf("rotate: %v", err)
	}
	select {
	case <-reset:
	case <-time.After(10 * time.Second):
		t.Fatal("the other instance was never told the install was reset")
	}
}

func TestWatch_StaysQuietWhileTheInstallStands(t *testing.T) {
	resetting, watching := twoInstances(t)
	reset := watch(t, watching)

	// Ordinary writes from the other instance are not a reset.
	if _, err := resetting.Db.Exec(`UPDATE vault_location SET device_serial = 'abc' WHERE id = 1`); err != nil {
		t.Fatalf("write: %v", err)
	}
	select {
	case <-reset:
		t.Fatal("watch reported a reset that did not happen")
	case <-time.After(200 * time.Millisecond):
	}
}

func TestWatch_RequiresQueriesAndOnReset(t *testing.T) {
	if _, err := resetutil.Watch(t.Context(), resetutil.WatchParams{}); err == nil {
		t.Fatal("watch started with nothing to watch")
	}
}

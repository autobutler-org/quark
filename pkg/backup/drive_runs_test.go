package backup

import (
	"context"
	"errors"
	"path"
	"reflect"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// runsFixture is a backup drive BK holding two complete runs and a partial
// one, the snapshot-backup role, and a database to check the run cache in.
type runsFixture struct {
	queries db.Querier
	drive   *vfs.MemVFS
	reg     vfs.Registry
	older   time.Time
	newer   time.Time
}

func newRunsFixture(t *testing.T) runsFixture {
	t.Helper()
	queries := dbtest.NewDB(t).Queries
	if err := queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{DeviceSerial: "BK", Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	drive := vfs.NewMemVFS(vfs.FilesNamespace("BK"))
	older := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	newer := older.Add(24 * time.Hour)
	putRun(t, drive, "2026-11-01 09.00", older, []ManifestDrive{
		{Folder: builtInFolder, Serial: "", Name: "Pi"},
		{Folder: "Photos (USB PHOTOS)", Serial: "PHOTOS", Name: "Photos"},
	}, map[string]string{builtInFolder + "/a.txt": "aaa", "Photos (USB PHOTOS)/p.jpg": "pp"})
	putRun(t, drive, "2026-11-02 09.00", newer, []ManifestDrive{
		{Folder: builtInFolder, Serial: "", Name: "Pi"},
	}, map[string]string{builtInFolder + "/a.txt": "aaaa"})
	putRun(t, drive, ".2026-11-03 09.00.partial", newer.Add(time.Hour), nil, map[string]string{"x": "x"})
	return runsFixture{queries: queries, drive: drive, reg: backupRegistry(t, "BK", slashVFS{drive}), older: older, newer: newer}
}

// A backup drive's runs are listed newest first with their sizes; a partial
// run is not one, and a drive with none lists none.
func TestListDriveRuns(t *testing.T) {
	f := newRunsFixture(t)
	list := func(serial string) (ListDriveRunsResult, error) {
		return ListDriveRuns(ListDriveRunsParams{Ctx: t.Context(), Queries: f.queries, Registry: f.reg, DeviceSerial: serial})
	}
	result, err := list("BK")
	if err != nil {
		t.Fatal(err)
	}
	var folders []string
	for _, run := range result.Runs {
		folders = append(folders, run.Folder)
	}
	if want := []string{"2026-11-02 09.00", "2026-11-01 09.00"}; !reflect.DeepEqual(folders, want) {
		t.Errorf("runs = %v, want %v", folders, want)
	}
	if result.Runs[0].SizeBytes != 4 || result.Runs[1].SizeBytes != 5 {
		t.Errorf("sizes = %d and %d, want 4 and 5", result.Runs[0].SizeBytes, result.Runs[1].SizeBytes)
	}

	if err := f.queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{DeviceSerial: "", Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	if result, err := list(""); err != nil || result.Runs == nil || len(result.Runs) != 0 {
		t.Errorf("built-in storage with no backups = %+v, %v; want an empty list", result, err)
	}
}

// Only a snapshot-backup drive holds runs, and only an attached one is read.
func TestListDriveRuns_RoleAndAttachment(t *testing.T) {
	f := newRunsFixture(t)
	if _, err := ListDriveRuns(ListDriveRunsParams{Ctx: t.Context(), Queries: f.queries, Registry: f.reg, DeviceSerial: ""}); !errors.Is(err, ErrBackupRoleRequired) {
		t.Errorf("a drive without the role = %v, want ErrBackupRoleRequired", err)
	}
	if err := f.queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{DeviceSerial: "GONE", Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	var notFound *fileutil.NotFoundError
	if _, err := ListDriveRuns(ListDriveRunsParams{Ctx: t.Context(), Queries: f.queries, Registry: f.reg, DeviceSerial: "GONE"}); !errors.As(err, &notFound) {
		t.Errorf("a drive that is not attached = %v, want a fileutil.NotFoundError", err)
	}
}

func deleteRun(t *testing.T, f runsFixture, bus *eventbus.Bus, run string) (DeleteRunResult, error) {
	t.Helper()
	return DeleteRun(DeleteRunParams{Ctx: t.Context(), Queries: f.queries, Registry: f.reg, EventBus: bus, DeviceSerial: "BK", Run: run})
}

// Deleting a run removes its folder, rewrites the drive's run cache so the
// protection status reads without it, and publishes backup_deleted.
func TestDeleteRun(t *testing.T) {
	f := newRunsFixture(t)
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	defer unsubscribe()

	result, err := deleteRun(t, f, bus, "2026-11-01 09.00")
	if err != nil || result.Run.Folder != "2026-11-01 09.00" {
		t.Fatalf("DeleteRun = %+v, %v", result, err)
	}
	if _, err := f.drive.Stat(t.Context(), runDir("2026-11-01 09.00")); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("the run's folder is still there: %v", err)
	}
	if _, err := f.drive.Stat(t.Context(), runDir("2026-11-02 09.00")); err != nil {
		t.Errorf("the other run went too: %v", err)
	}

	// The drive is away now: its copies come from the cache the delete rewrote.
	away := backupRegistry(t, "OTHER", vfs.NewMemVFS(vfs.FilesNamespace("OTHER")))
	want := []RunCopy{{Serial: "", Name: "Pi", CompletedAt: f.newer}}
	if got := driveCopies(t, f.queries, away, "BK"); !reflect.DeepEqual(got, want) {
		t.Errorf("copies after the delete = %+v, want %+v (Photos was only in the deleted run)", got, want)
	}

	select {
	case evt := <-events:
		data, _ := evt.Data.(eventbus.BackupDeleted)
		if evt.Kind != eventbus.EventBackupDeleted || data != (eventbus.BackupDeleted{DeviceSerial: "BK", Run: "2026-11-01 09.00"}) {
			t.Errorf("event = %+v, want backup_deleted for the run", evt)
		}
	case <-time.After(time.Second):
		t.Error("no event published")
	}
}

// Only a run ListRuns lists can be deleted: not a partial one, not a path out
// of backups/, not backups/ itself.
func TestDeleteRun_OnlyAListedRun(t *testing.T) {
	f := newRunsFixture(t)
	for _, run := range []string{"", "nope", ".2026-11-03 09.00.partial", "../backups/2026-11-01 09.00", "..", "2026-11-01 09.00/" + builtInFolder} {
		if _, err := deleteRun(t, f, nil, run); !errors.Is(err, ErrRunNotFound) {
			t.Errorf("delete of %q = %v, want ErrRunNotFound", run, err)
		}
	}
	if _, err := f.drive.Stat(t.Context(), partialDir("2026-11-03 09.00")); err != nil {
		t.Errorf("the partial run was touched: %v", err)
	}
	if runs, err := ListRuns(t.Context(), f.drive); err != nil || len(runs) != 2 {
		t.Errorf("runs after refused deletes = %+v, %v; want both", runs, err)
	}
}

// A run is not deleted while a backup onto the drive is pending or running,
// which may be linking from it, nor while a restore reads it.
func TestDeleteRun_RefusedWhileTheDriveIsBusy(t *testing.T) {
	f := newRunsFixture(t)
	restore, err := f.queries.CreateJob(t.Context(), db.CreateJobParams{
		Kind: RestoreKind, Name: "restore", Params: `{"backupSerial":"BK","run":"2026-11-01 09.00","folders":[]}`,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := deleteRun(t, f, nil, "2026-11-01 09.00"); !errors.Is(err, ErrDriveBusy) {
		t.Errorf("delete of the run a restore reads = %v, want ErrDriveBusy", err)
	}
	if _, err := deleteRun(t, f, nil, "2026-11-02 09.00"); err != nil {
		t.Errorf("delete of a run no restore reads = %v", err)
	}
	if _, err := f.queries.CancelJob(t.Context(), restore.ID); err != nil {
		t.Fatal(err)
	}

	if _, err := f.queries.CreateJob(t.Context(), db.CreateJobParams{
		Kind: Kind, Name: "backup", Params: `{"targetDeviceSerial":"BK"}`,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := deleteRun(t, f, nil, "2026-11-01 09.00"); !errors.Is(err, ErrDriveBusy) {
		t.Errorf("delete during a backup = %v, want ErrDriveBusy", err)
	}
	if _, err := f.drive.Stat(context.Background(), path.Join(runDir("2026-11-01 09.00"), manifestFilename)); err != nil {
		t.Errorf("a refused delete removed the run: %v", err)
	}
}

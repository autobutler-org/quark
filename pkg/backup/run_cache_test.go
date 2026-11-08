package backup

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// driveCopies is DriveCopies, failing the test on an error.
func driveCopies(t *testing.T, queries db.Querier, registry vfs.Registry, serial string) []RunCopy {
	t.Helper()
	copies, err := DriveCopies(context.Background(), queries, registry, serial)
	if err != nil {
		t.Fatal(err)
	}
	return copies
}

// backupRegistry registers fsys as the files namespace of the drive serial,
// beside built-in storage, as the device scan does for an attached drive.
func backupRegistry(t *testing.T, serial string, fsys vfs.VFS) vfs.Registry {
	t.Helper()
	reg := vfs.NewRegistry()
	for s, f := range map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), serial: fsys} {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(s)}, f); err != nil {
			t.Fatal(err)
		}
	}
	return reg
}

// An attached drive's copies come from its runs: per data drive, the newest
// run naming it. A partial run does not count, and deleting a run changes
// the next read (#4037).
func TestDriveCopies_AttachedReadsNewestRunPerDrive(t *testing.T) {
	ctx := context.Background()
	queries := dbtest.NewDB(t).Queries
	drive := vfs.NewMemVFS(vfs.FilesNamespace("BK"))
	reg := backupRegistry(t, "BK", drive)
	older := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	newer := older.Add(48 * time.Hour)
	putRun(t, drive, "2026-11-01 09.00", older, []ManifestDrive{
		{Folder: builtInFolder, Serial: "", Name: "Pi"},
		{Folder: "Photos (USB PHOTOS)", Serial: "PHOTOS", Name: "Photos"},
	}, map[string]string{builtInFolder + "/a.txt": "a"})
	putRun(t, drive, "2026-11-03 09.00", newer, []ManifestDrive{
		{Folder: builtInFolder, Serial: "", Name: "Pi"},
	}, map[string]string{builtInFolder + "/a.txt": "a"})
	// A run still being written names a newer copy of Photos that must not count.
	putFile(t, drive, partialDir("2026-11-04 09.00")+"/"+manifestFilename,
		`{"completedAt":"2026-11-04T09:00:00Z","drives":[{"folder":"P","serial":"PHOTOS","name":"Photos"}]}`)

	want := []RunCopy{
		{Serial: "", Name: "Pi", CompletedAt: newer},
		{Serial: "PHOTOS", Name: "Photos", CompletedAt: older},
	}
	if got := driveCopies(t, queries, reg, "BK"); !reflect.DeepEqual(got, want) {
		t.Fatalf("copies = %+v, want %+v", got, want)
	}

	if err := drive.Delete(ctx, runDir("2026-11-03 09.00"), vfs.DeleteOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	want = []RunCopy{
		{Serial: "", Name: "Pi", CompletedAt: older},
		{Serial: "PHOTOS", Name: "Photos", CompletedAt: older},
	}
	if got := driveCopies(t, queries, reg, "BK"); !reflect.DeepEqual(got, want) {
		t.Fatalf("copies after deleting the newest run = %+v, want %+v", got, want)
	}
}

// A drive that is away answers from its last scan, and every scan rewrites
// that, down to empty once its runs are gone. A drive never scanned has none.
func TestDriveCopies_AwayUsesLastScan(t *testing.T) {
	ctx := context.Background()
	queries := dbtest.NewDB(t).Queries
	away := backupRegistry(t, "OTHER", vfs.NewMemVFS(vfs.FilesNamespace("OTHER")))
	if got := driveCopies(t, queries, away, "BK"); len(got) != 0 {
		t.Fatalf("never-scanned away drive = %+v, want no copies", got)
	}

	drive := vfs.NewMemVFS(vfs.FilesNamespace("BK"))
	at := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	putRun(t, drive, "2026-11-01 09.00", at, []ManifestDrive{{Folder: builtInFolder, Serial: "", Name: "Pi"}}, nil)
	driveCopies(t, queries, backupRegistry(t, "BK", drive), "BK")

	want := []RunCopy{{Serial: "", Name: "Pi", CompletedAt: at}}
	if got := driveCopies(t, queries, away, "BK"); !reflect.DeepEqual(got, want) {
		t.Fatalf("away drive = %+v, want its last scan %+v", got, want)
	}
	value, err := queries.GetSetting(ctx, "backupRuns:BK")
	if err != nil || value != `[{"serial":"","name":"Pi","completedAt":"2026-11-01T09:00:00Z"}]` {
		t.Errorf("cache row = %s, %v", value, err)
	}

	if err := drive.Delete(ctx, BackupsDir, vfs.DeleteOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	if got, err := RefreshRunCache(ctx, queries, "BK", drive); err != nil || len(got) != 0 {
		t.Fatalf("RefreshRunCache of an empty drive = %+v, %v; want none", got, err)
	}
	if got := driveCopies(t, queries, away, "BK"); len(got) != 0 {
		t.Fatalf("away drive after an empty scan = %+v, want no copies", got)
	}
	if value, err := queries.GetSetting(ctx, "backupRuns:BK"); err != nil || value != "[]" {
		t.Errorf("cache row after an empty scan = %s, %v; want []", value, err)
	}
}

// failingBackupsVFS is a drive whose backups/ folder cannot be listed.
type failingBackupsVFS struct{ vfs.VFS }

func (f failingBackupsVFS) List(ctx context.Context, p string, filter *vfs.ListFilter) ([]vfs.FileInfo, error) {
	if p == BackupsDir {
		return nil, errors.New("i/o error")
	}
	return f.VFS.List(ctx, p, filter)
}

// An attached drive whose runs cannot be read answers from its last scan, and
// the failed scan leaves that scan's row as it was.
func TestDriveCopies_FailedScanUsesLastScan(t *testing.T) {
	ctx := context.Background()
	queries := dbtest.NewDB(t).Queries
	drive := vfs.NewMemVFS(vfs.FilesNamespace("BK"))
	at := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	putRun(t, drive, "2026-11-01 09.00", at, []ManifestDrive{{Folder: builtInFolder, Serial: "", Name: "Pi"}}, nil)
	driveCopies(t, queries, backupRegistry(t, "BK", drive), "BK")
	before, err := queries.GetSetting(ctx, "backupRuns:BK")
	if err != nil {
		t.Fatal(err)
	}

	want := []RunCopy{{Serial: "", Name: "Pi", CompletedAt: at}}
	if got := driveCopies(t, queries, backupRegistry(t, "BK", failingBackupsVFS{drive}), "BK"); !reflect.DeepEqual(got, want) {
		t.Fatalf("copies after a failed scan = %+v, want the last scan %+v", got, want)
	}
	if after, err := queries.GetSetting(ctx, "backupRuns:BK"); err != nil || after != before {
		t.Errorf("cache row after a failed scan = %s, %v; want %s untouched", after, err, before)
	}
}

// A completed snapshot rewrites its target's run cache, so the new run counts
// while the drive is away.
func TestSnapshotBackup_RefreshesTheRunCache(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"file.txt": "data"})
	job := newJob("TARGET")
	queries := dbtest.NewDB(t).Queries
	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Queries:            queries,
	}, []SourceDevice{src}, makeTarget(t)); err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}
	copies, err := cachedRunCopies(context.Background(), queries, "TARGET")
	if err != nil || len(copies) != 1 || copies[0].Serial != "SER1" || !copies[0].CompletedAt.Equal(*job.CompletedAt) {
		t.Errorf("cached copies = %+v, %v; want SER1 at the job's completion time %v", copies, err, job.CompletedAt)
	}
}

// A snapshot that fails leaves no run, and so nothing in the cache.
func TestSnapshotBackup_FailedBackupCachesNothing(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"file.txt": "data"})
	queries := dbtest.NewDB(t).Queries
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := SnapshotBackup(ctx, SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                newJob("TARGET"),
		Queries:            queries,
	}, []SourceDevice{src}, makeTarget(t)); err == nil {
		t.Fatal("SnapshotBackup succeeded with a canceled context")
	}
	if copies, err := cachedRunCopies(context.Background(), queries, "TARGET"); err != nil || len(copies) != 0 {
		t.Errorf("cached copies = %+v, %v after a failed backup, want none", copies, err)
	}
}

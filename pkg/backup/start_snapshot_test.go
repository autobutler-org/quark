package backup

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"

	_ "modernc.org/sqlite"
)

// newRolesQueries returns queries over the real schema. StartSnapshotBackup
// reads device_roles and nothing else before it decides whether to go on.
func newRolesQueries(t *testing.T) db.Querier {
	t.Helper()
	return dbtest.NewDB(t).Queries
}

func TestStartSnapshotBackup_RejectsDeviceWithoutRole(t *testing.T) {
	const serial = "USB-001"
	ctx := context.Background()
	queries := newRolesQueries(t)
	if err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         "default-storage",
	}); err != nil {
		t.Fatalf("seed role: %v", err)
	}

	_, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                ctx,
		Queries:            queries,
		TargetDeviceSerial: serial,
	})
	if !errors.Is(err, ErrTargetRoleRequired) {
		t.Fatalf("expected ErrTargetRoleRequired, got %v", err)
	}
}

func TestStartSnapshotBackup_RejectsUnknownDevice(t *testing.T) {
	_, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                context.Background(),
		Queries:            newRolesQueries(t),
		TargetDeviceSerial: "NOT-A-DEVICE",
	})
	if !errors.Is(err, ErrTargetRoleRequired) {
		t.Fatalf("expected ErrTargetRoleRequired, got %v", err)
	}
}

// Built-in storage can be the snapshot target (#3999). The external data
// drive's files land on it, and its own files are not copied onto itself.
func TestStartSnapshotBackup_InternalTargetCopiesOtherDrivesOnly(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	for serial, role := range map[string]string{"": "snapshot-backup", targetSerial: "default-storage"} {
		if err := f.database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
			DeviceSerial: serial,
			Role:         role,
		}); err != nil {
			t.Fatal(err)
		}
	}
	writeTestFile(t, f.internal, "docs/live.txt", "live")
	writeTestFile(t, f.target, "docs/usb.txt", "from-usb")

	inst := f.instance(nil)
	inst.run(t)
	jobID, err := f.start(inst, "")
	if err != nil {
		t.Fatalf("StartSnapshotBackup onto built-in storage: %v", err)
	}
	job := f.waitStatus(t, jobID, BackupStatusCompleted)
	if job.TargetDeviceSerial != "" {
		t.Fatalf("target = %q, want the internal drive", job.TargetDeviceSerial)
	}

	assertFileContent(t, filepath.Join(f.internal, "docs/live.txt"), "live")
	run := onlyRun(t, localFS(t, f.internal))
	for _, d := range run.Drives {
		if d.Serial == "" {
			t.Fatalf("the run holds %+v, want the USB drives and not built-in storage", run.Drives)
		}
	}
	dir := filepath.Join(f.internal, BackupsDir, run.Folder)
	if _, err := os.Stat(filepath.Join(dir, builtInFolder)); !os.IsNotExist(err) {
		t.Fatalf("built-in storage was copied onto itself: %v", err)
	}
	assertFileContent(t, filepath.Join(dir, driveDirName("USB "+targetSerial, targetSerial), "docs/usb.txt"), "from-usb")

	// A second run onto built-in storage does not copy the first into itself.
	if jobID, err = f.start(inst, ""); err != nil {
		t.Fatal(err)
	}
	f.waitStatus(t, jobID, BackupStatusCompleted)
	runs, err := ListRuns(context.Background(), localFS(t, f.internal))
	if err != nil || len(runs) != 2 {
		t.Fatalf("runs = %+v, %v; want two", runs, err)
	}
	for _, run := range runs {
		for _, d := range run.Drives {
			if d.Serial == "" {
				t.Errorf("run %s holds built-in storage", run.Folder)
			}
		}
	}
}

// Backup drives are never sources (#4037): a backup onto one copies every
// data drive and none of the other backup drives, and the job names both
// sides for the progress card.
func TestStartSnapshotBackup_SkipsOtherBackupDrives(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	writeTestFile(t, f.internal, "docs/live.txt", "live")
	writeTestFile(t, f.other, "docs/other-backup.txt", "backup")

	inst := f.instance(nil)
	inst.run(t)
	jobID, err := f.start(inst, targetSerial)
	if err != nil {
		t.Fatalf("StartSnapshotBackup: %v", err)
	}
	job := f.waitStatus(t, jobID, BackupStatusCompleted)

	run := onlyRun(t, localFS(t, f.target))
	dir := filepath.Join(f.target, BackupsDir, run.Folder)
	assertFileContent(t, filepath.Join(dir, builtInFolder, "docs/live.txt"), "live")
	otherDir := filepath.Join(dir, driveDirName("USB "+otherSerial, otherSerial))
	if _, err := os.Stat(otherDir); !os.IsNotExist(err) {
		t.Fatalf("another backup drive was copied onto the target: %v", err)
	}
	if len(job.SourceDevices) != 1 || job.SourceDevices[0].DeviceSerial != "" {
		t.Errorf("sources = %+v, want built-in storage only", job.SourceDevices)
	}
	if job.TargetName != "USB "+targetSerial {
		t.Errorf("target name = %q, want %q", job.TargetName, "USB "+targetSerial)
	}
	if len(job.SourceNames) != 1 || job.SourceNames[0] != "Built-in storage" {
		t.Errorf("source names = %q, want built-in storage only", job.SourceNames)
	}
	if job.CurrentSource != "" {
		t.Errorf("current source = %q after completion, want none", job.CurrentSource)
	}

	copies, err := cachedRunCopies(context.Background(), f.database.Queries, targetSerial)
	if err != nil || len(copies) != 1 || copies[0].Serial != "" {
		t.Errorf("the target's cached copies = %+v, %v; want built-in storage only", copies, err)
	}
}

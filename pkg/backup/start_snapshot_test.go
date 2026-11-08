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

// Built-in storage can be the snapshot target (#3999). The external drive's
// files land on it, and its own files are not copied onto itself.
func TestStartSnapshotBackup_InternalTargetCopiesOtherDrivesOnly(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	if err := f.database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
		DeviceSerial: "",
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
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

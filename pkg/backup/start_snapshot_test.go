package backup

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
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

// A backup given sources copies those drives and no other data drive, and the
// job is named after them alone (#3984).
func TestStartSnapshotBackup_CopiesOnlyTheChosenSources(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	// otherSerial becomes a second data drive beside built-in storage.
	if err := f.database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{
		DeviceSerial: otherSerial,
		Role:         "default-storage",
	}); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, f.internal, "docs/live.txt", "live")
	writeTestFile(t, f.other, "docs/photos.txt", "photos")

	inst := f.instance(nil)
	inst.run(t)
	result, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                t.Context(),
		Queries:            f.database.Queries,
		Registry:           f.registry,
		Queue:              inst.queue,
		TargetDeviceSerial: targetSerial,
		SourceSerials:      []string{otherSerial, otherSerial},
		Storage:            f.storage,
	})
	if err != nil {
		t.Fatalf("StartSnapshotBackup: %v", err)
	}
	row, err := f.database.Queries.GetJob(t.Context(), mustID(t, result.JobID))
	if err != nil {
		t.Fatal(err)
	}
	if want := "Back up USB " + otherSerial + " onto USB " + targetSerial; row.Name != want {
		t.Errorf("job name = %q, want %q", row.Name, want)
	}
	job := f.waitStatus(t, result.JobID, BackupStatusCompleted)
	if len(job.SourceDevices) != 1 || job.SourceDevices[0].DeviceSerial != otherSerial {
		t.Errorf("sources = %+v, want %s only", job.SourceDevices, otherSerial)
	}
	run := onlyRun(t, localFS(t, f.target))
	if len(run.Drives) != 1 || run.Drives[0].Serial != otherSerial {
		t.Errorf("the run holds %+v, want %s only", run.Drives, otherSerial)
	}
	dir := filepath.Join(f.target, BackupsDir, run.Folder)
	assertFileContent(t, filepath.Join(dir, driveDirName("USB "+otherSerial, otherSerial), "docs/photos.txt"), "photos")
	if _, err := os.Stat(filepath.Join(dir, builtInFolder)); !os.IsNotExist(err) {
		t.Fatalf("built-in storage was copied though it was not chosen: %v", err)
	}
}

// A source must be an attached data drive: not the target, not another
// backup drive, and not a drive with no files namespace. Built-in storage is
// the serial "".
func TestStartSnapshotBackup_RejectsASourceThatIsNotADataDrive(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	inst := f.instance(nil)
	for _, tc := range []struct {
		name   string
		source string
		ok     bool
	}{
		{"the target", targetSerial, false},
		{"another backup drive", otherSerial, false},
		{"a drive that is not attached", "GONE-1", false},
		// Last: it queues a job, which holds the target.
		{"built-in storage", "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			result, err := StartSnapshotBackup(StartSnapshotBackupParams{
				Ctx:                t.Context(),
				Queries:            f.database.Queries,
				Registry:           f.registry,
				Queue:              inst.queue,
				TargetDeviceSerial: targetSerial,
				SourceSerials:      []string{tc.source},
			})
			if tc.ok {
				if err != nil || result.JobID == "" {
					t.Fatalf("StartSnapshotBackup = %+v, %v; want it queued", result, err)
				}
				return
			}
			if !errors.Is(err, ErrSourceNotDataDrive) {
				t.Fatalf("StartSnapshotBackup = %v, want ErrSourceNotDataDrive", err)
			}
		})
	}
}

func mustID(t *testing.T, id string) int64 {
	t.Helper()
	n, err := strconv.ParseInt(id, 10, 64)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

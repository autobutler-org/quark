package backup

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const jobTestTimeout = 10 * time.Second

// jobFixture is one database and one set of drives, the internal one and two
// backup targets, that any number of instances share.
type jobFixture struct {
	database *db.DatabaseSqlc
	registry vfs.Registry
	storage  *storageutil.StorageService
	// internal and target are the files directories of the internal drive
	// and of the targetSerial drive.
	internal, target string
}

func newJobFixture(t *testing.T, database *db.DatabaseSqlc) jobFixture {
	t.Helper()
	dirs := map[string]string{}
	var devices drivesDetector
	for _, serial := range []string{"", targetSerial, otherSerial} {
		mountPoint := t.TempDir()
		dirs[serial] = filepath.Join(mountPoint, "quark", "data", "files")
		if err := os.MkdirAll(dirs[serial], 0o755); err != nil {
			t.Fatal(err)
		}
		device := storageutil.Device{Name: "Internal", MountPoint: mountPoint, IsInternal: true}
		if serial != "" {
			device = storageutil.Device{Name: "USB " + serial, MountPoint: mountPoint, UsbInfo: serialUsb{serial: serial}}
			if err := database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
				DeviceSerial: serial,
				Role:         "snapshot-backup",
			}); err != nil {
				t.Fatal(err)
			}
		}
		devices = append(devices, device)
	}
	return jobFixture{
		database: database,
		registry: localNamespaces(t, dirs),
		storage:  storageutil.NewStorageService(devices),
		internal: dirs[""],
		target:   dirs[targetSerial],
	}
}

// instance is one Quark process's job queue over the shared database. A
// non-nil gate holds each backup at its start until the test sends on it, and
// started reports each one that got there.
type instance struct {
	queue   *jobutil.Queue
	started chan struct{}
}

func (f jobFixture) instance(gate chan struct{}) instance {
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: f.database})
	handler := NewHandler(NewHandlerParams{Database: f.database, Storage: f.storage, Registry: f.registry})
	started := make(chan struct{}, 8)
	run := handler.Run
	handler.Run = func(ctx context.Context, params json.RawMessage, report func(float64)) error {
		started <- struct{}{}
		if gate != nil {
			select {
			case <-gate:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		return run(ctx, params, report)
	}
	queue.Register(jobutil.RegisterParams{Kind: Kind, Handler: handler})
	return instance{queue: queue, started: started}
}

// run starts the instance's dispatcher and stops it when the test ends.
func (i instance) run(t *testing.T) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		i.queue.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

func (i instance) waitStarted(t *testing.T) {
	t.Helper()
	select {
	case <-i.started:
	case <-time.After(jobTestTimeout):
		t.Fatal("the backup job did not start")
	}
}

func (f jobFixture) start(i instance, serial string) (string, error) {
	result, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                context.Background(),
		Queries:            f.database.Queries,
		Registry:           f.registry,
		Queue:              i.queue,
		TargetDeviceSerial: serial,
	})
	return result.JobID, err
}

func (f jobFixture) status(t *testing.T, jobID string) BackupJob {
	t.Helper()
	result, err := GetSnapshotBackupStatus(GetSnapshotBackupStatusParams{
		Ctx:     context.Background(),
		Queries: f.database.Queries,
		JobID:   jobID,
	})
	if err != nil {
		t.Fatalf("status of job %s: %v", jobID, err)
	}
	return result.Job
}

func (f jobFixture) waitStatus(t *testing.T, jobID string, want BackupJobStatus) BackupJob {
	t.Helper()
	deadline := time.Now().Add(jobTestTimeout)
	for {
		job := f.status(t, jobID)
		if job.Status == want {
			return job
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %s is %s (%s), want %s", jobID, job.Status, job.ErrorMsg, want)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func assertInProgress(t *testing.T, err error, jobID string) {
	t.Helper()
	var inProgress *BackupInProgressError
	if !errors.As(err, &inProgress) {
		t.Fatalf("expected BackupInProgressError, got %v", err)
	}
	if inProgress.JobID != jobID {
		t.Errorf("the lock names job %q, want %q", inProgress.JobID, jobID)
	}
	if want := "backup already running for this device (job " + jobID + ")"; inProgress.Error() != want {
		t.Errorf("expected %q, got %q", want, inProgress.Error())
	}
}

// The lock on a target holds across instances (#3084, J12): the store the
// "already running" check read used to live in one process's memory.
func TestStartSnapshotBackup_SecondStartIsRefusedOnEveryInstance(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	gate := make(chan struct{})
	a, b := f.instance(gate), f.instance(nil)

	jobID, err := f.start(a, targetSerial)
	if err != nil {
		t.Fatalf("first start: %v", err)
	}
	if got := f.status(t, jobID).Status; got != BackupStatusPending {
		t.Errorf("a queued backup is %s, want PENDING", got)
	}
	_, err = f.start(b, targetSerial)
	assertInProgress(t, err, jobID)

	a.run(t)
	a.waitStarted(t)
	if got := f.status(t, jobID).Status; got != BackupStatusScanning {
		t.Errorf("a backup that just started is %s, want SCANNING", got)
	}
	_, err = f.start(b, targetSerial)
	assertInProgress(t, err, jobID)

	if _, err := f.start(b, otherSerial); err != nil {
		t.Errorf("a backup onto another target was refused: %v", err)
	}

	close(gate)
	f.waitStatus(t, jobID, BackupStatusCompleted)
	if _, err := f.start(b, targetSerial); err != nil {
		t.Errorf("a finished backup still holds the target: %v", err)
	}
}

// The lock is the index, not the check in front of it: two inserts that both
// got past the check cannot both land.
func TestBackupTargetLock_IsADatabaseConstraint(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	enqueue := func(i instance) error {
		_, err := i.queue.Enqueue(context.Background(), jobutil.EnqueueParams{
			Kind:   Kind,
			Name:   "Snapshot backup",
			Params: JobParams{TargetDeviceSerial: targetSerial},
		})
		return err
	}
	if err := enqueue(f.instance(nil)); err != nil {
		t.Fatal(err)
	}
	if err := enqueue(f.instance(nil)); !sqlutil.IsUniqueConstraintErr(err) {
		t.Fatalf("a second backup job for the target = %v, want a unique violation", err)
	}
}

// A backup whose process died has a terminal state once an instance starts
// (#3084, J12): it used to vanish with the process, and the poll with it.
func TestSnapshotBackupStatus_RestartLeavesATerminalState(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	jobID, err := f.start(f.instance(nil), targetSerial)
	if err != nil {
		t.Fatal(err)
	}
	// Claimed by a process that then died: running, with nothing running it.
	id, _ := strconv.ParseInt(jobID, 10, 64)
	if _, err := f.database.Queries.ClaimJob(context.Background(), id); err != nil {
		t.Fatal(err)
	}

	restarted := f.instance(nil)
	restarted.run(t)
	job := f.waitStatus(t, jobID, BackupStatusFailed)
	if job.ErrorMsg == "" {
		t.Error("the interrupted backup carries no error")
	}
	if job.CompletedAt == nil {
		t.Error("the interrupted backup carries no completion time")
	}
	if _, err := f.start(restarted, targetSerial); err != nil {
		t.Errorf("the interrupted backup still holds the target: %v", err)
	}
}

// The counts the storage tab shows come out of the job row, so the instance
// that answers need not be the one copying (#3084, C4).
func TestSnapshotBackupStatus_ReadsCountsFromTheRow(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	writeTestFile(t, f.internal, "docs/a.txt", "aaa")
	writeTestFile(t, f.internal, "b.txt", "bb")
	gate := make(chan struct{})
	a := f.instance(gate)
	jobID, err := f.start(a, targetSerial)
	if err != nil {
		t.Fatal(err)
	}
	a.run(t)
	a.waitStarted(t)

	// What a run saves mid-copy is what a status read returns.
	id, _ := strconv.ParseInt(jobID, 10, 64)
	if err := f.database.Queries.UpdateJobDetail(context.Background(), db.UpdateJobDetailParams{
		ID:     id,
		Detail: `{"status":"COPYING","totalFiles":2,"filesCopied":1,"bytesCopied":3,"totalBytes":5}`,
	}); err != nil {
		t.Fatal(err)
	}
	job := f.status(t, jobID)
	if job.Status != BackupStatusCopying || job.FilesCopied != 1 || job.TotalFiles != 2 || job.TotalBytes != 5 {
		t.Errorf("mid-copy status = %+v", job)
	}
	if job.ID != jobID || job.TargetDeviceSerial != targetSerial {
		t.Errorf("status names job %q on %q", job.ID, job.TargetDeviceSerial)
	}

	close(gate)
	job = f.waitStatus(t, jobID, BackupStatusCompleted)
	if job.FilesCopied != 2 || job.TotalFiles != 2 || job.BytesCopied != 5 || job.Progress != 1 {
		t.Errorf("finished status = %+v", job)
	}
	if job.CompletedAt == nil || len(job.SourceDevices) == 0 {
		t.Errorf("finished status = %+v, want a completion time and the source devices", job)
	}
	assertFileContent(t, filepath.Join(f.target, "internal", "docs/a.txt"), "aaa")
}

func TestGetSnapshotBackupStatus_UnknownJobIsNotFound(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	other := jobutil.NewQueue(jobutil.NewQueueParams{Database: f.database})
	other.Register(jobutil.RegisterParams{Kind: "other", Handler: jobutil.Handler{}})
	queued, err := other.Enqueue(context.Background(), jobutil.EnqueueParams{Kind: "other", Name: "job"})
	if err != nil {
		t.Fatal(err)
	}
	for _, jobID := range []string{"999", "not-a-number", strconv.FormatInt(queued.Job.ID, 10)} {
		_, err := GetSnapshotBackupStatus(GetSnapshotBackupStatusParams{
			Ctx:     context.Background(),
			Queries: f.database.Queries,
			JobID:   jobID,
		})
		if !errors.Is(err, ErrBackupJobNotFound) {
			t.Errorf("status of %q = %v, want ErrBackupJobNotFound", jobID, err)
		}
	}
}

// The job only moves a vault export the request already built, so its params
// hold a file name and no secret (#3084).
func TestSnapshotBackupJob_CommitsTheStagedVaultExport(t *testing.T) {
	const recoveryPassword = "recovery-password-456"
	d, queries, liveKey := setupLiveVaultDB(t, "master-password-123")
	defer vaultcrypto.ZeroKey(liveKey)
	addTestEntry(t, d, liveKey, "GitHub", "alice", "gh-secret")
	f := newJobFixture(t, &db.DatabaseSqlc{Db: d, Queries: queries})

	staged, err := stageVaultExport(context.Background(), queries, liveKey, recoveryPassword, f.target)
	if err != nil {
		t.Fatal(err)
	}
	a := f.instance(nil)
	queued, err := a.queue.Enqueue(context.Background(), jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   "Snapshot backup",
		Params: JobParams{TargetDeviceSerial: targetSerial, VaultExport: staged},
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := `{"targetDeviceSerial":"` + targetSerial + `","vaultExport":"` + staged + `"}`; string(queued.Job.Params) != want {
		t.Errorf("job params = %s, want %s", queued.Job.Params, want)
	}
	a.run(t)
	jobID := strconv.FormatInt(queued.Job.ID, 10)
	f.waitStatus(t, jobID, BackupStatusCompleted)

	assertNoTemps(t, f.target)
	manifest, err := ReadManifest(context.Background(), localFS(t, f.target))
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := manifest.Files[backupVaultFilename]; !ok || len(manifest.Files) != 2 {
		t.Errorf("the manifest covers %v, want the vault and chat exports", manifest.Files)
	}

	// A run removes its staged export however it ends, so a retry is refused
	// up front rather than failing on the missing file.
	if err := NewHandler(NewHandlerParams{}).Validate(queued.Job.Params); err == nil {
		t.Error("a backup with a vault export may be retried")
	}
}

func TestSnapshotBackupJob_MissingStagedVaultExportFailsTheJob(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	a := f.instance(nil)
	queued, err := a.queue.Enqueue(context.Background(), jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   "Snapshot backup",
		Params: JobParams{TargetDeviceSerial: targetSerial, VaultExport: storageutil.WriteTempPrefix + "gone-" + backupVaultFilename},
	})
	if err != nil {
		t.Fatal(err)
	}
	a.run(t)
	job := f.waitStatus(t, strconv.FormatInt(queued.Job.ID, 10), BackupStatusFailed)
	if !strings.Contains(job.ErrorMsg, "start a new backup") {
		t.Errorf("error = %q, want it to say to start a new backup", job.ErrorMsg)
	}
}

// A staged export left by a crashed run is removed by the next backup, and
// one young enough to be another request's is not.
func TestRemoveStaleStagedVaults(t *testing.T) {
	dir := t.TempDir()
	stale := storageutil.WriteTempPrefix + "old-" + backupVaultFilename
	fresh := storageutil.WriteTempPrefix + "new-" + backupVaultFilename
	for _, name := range []string{stale, stale + "-journal", fresh, backupVaultFilename} {
		writeTestFile(t, dir, name, "x")
	}
	old := time.Now().Add(-2 * stagedVaultMaxAge)
	for _, name := range []string{stale, stale + "-journal", backupVaultFilename} {
		if err := os.Chtimes(filepath.Join(dir, name), old, old); err != nil {
			t.Fatal(err)
		}
	}

	removeStaleStagedVaults(dir)

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	if want := []string{fresh, backupVaultFilename}; strings.Join(names, ",") != strings.Join(want, ",") {
		t.Errorf("left %v, want %v", names, want)
	}
}

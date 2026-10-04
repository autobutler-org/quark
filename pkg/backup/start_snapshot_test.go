package backup

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	_ "modernc.org/sqlite"
)

// newRolesQueries returns queries over the real schema. StartSnapshotBackup
// reads device_roles and nothing else before it decides whether to go on.
func newRolesQueries(t *testing.T) *db.Queries {
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
		Store:              NewInMemoryBackupJobStore(),
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
		Store:              NewInMemoryBackupJobStore(),
		TargetDeviceSerial: "NOT-A-DEVICE",
	})
	if !errors.Is(err, ErrTargetRoleRequired) {
		t.Fatalf("expected ErrTargetRoleRequired, got %v", err)
	}
}

func TestStartSnapshotBackup_RejectsSecondBackupForSameTarget(t *testing.T) {
	const serial = "USB-001"
	ctx := context.Background()
	queries := newRolesQueries(t)
	if err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatalf("seed role: %v", err)
	}

	store := NewInMemoryBackupJobStore()
	running := &BackupJob{ID: "job-1", Status: BackupStatusCopying, TargetDeviceSerial: serial}
	if err := store.Create(ctx, running); err != nil {
		t.Fatalf("seed job: %v", err)
	}

	_, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                ctx,
		Queries:            queries,
		Store:              store,
		TargetDeviceSerial: serial,
	})
	var inProgress *BackupInProgressError
	if !errors.As(err, &inProgress) {
		t.Fatalf("expected BackupInProgressError, got %v", err)
	}
	if inProgress.JobID != "job-1" {
		t.Errorf("expected the running job id, got %q", inProgress.JobID)
	}
	if want := "backup already running for this device (job job-1)"; inProgress.Error() != want {
		t.Errorf("expected %q, got %q", want, inProgress.Error())
	}
}

func TestStartSnapshotBackup_FinishedJobDoesNotBlockNewOne(t *testing.T) {
	const serial = "USB-001"
	ctx := context.Background()
	queries := newRolesQueries(t)
	if err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatalf("seed role: %v", err)
	}

	store := NewInMemoryBackupJobStore()
	for _, status := range []BackupJobStatus{BackupStatusCompleted, BackupStatusFailed} {
		if err := store.Create(ctx, &BackupJob{
			ID:                 string(status),
			Status:             status,
			TargetDeviceSerial: serial,
		}); err != nil {
			t.Fatalf("seed job: %v", err)
		}
	}

	// No device is plugged in, so this stops at the device lookup — past the
	// conflict scan, which is the point.
	_, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                ctx,
		Queries:            queries,
		Storage:            storageutil.NewStorageService(noDevices{}),
		Store:              store,
		TargetDeviceSerial: serial,
	})
	if !errors.Is(err, ErrTargetNotManaged) {
		t.Fatalf("a finished job should not block a new backup, got %v", err)
	}
}

// noDevices is a Detector with nothing plugged in.
type noDevices struct{}

func (noDevices) DetectDevices() ([]storageutil.Device, error) { return nil, nil }

// TestPrepareVaultExport_RawPasswordIsAppTooOld checks the re-confirmation in
// front of a vault export passes a raw password's ErrAppTooOld through, so the
// handler answers an old app's 426 rather than invalid credentials (#2430).
func TestPrepareVaultExport_RawPasswordIsAppTooOld(t *testing.T) {
	_, err := prepareVaultExport(StartSnapshotBackupParams{
		Ctx:              context.Background(),
		Queries:          newRolesQueries(t),
		Username:         "admin",
		Password:         "admin-password",
		RecoveryPassword: "recovery-password",
	})
	if !errors.Is(err, authutil.ErrAppTooOld) {
		t.Fatalf("raw password = %v, want ErrAppTooOld", err)
	}
	_, err = prepareVaultExport(StartSnapshotBackupParams{
		Ctx:              context.Background(),
		Queries:          newRolesQueries(t),
		Username:         "admin",
		Password:         dbtest.AuthKey("admin-password"),
		RecoveryPassword: "recovery-password",
	})
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("unknown account's key = %v, want ErrInvalidCredentials", err)
	}
}

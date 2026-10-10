package backup

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"

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

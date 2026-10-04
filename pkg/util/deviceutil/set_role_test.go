package deviceutil

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	_ "modernc.org/sqlite"
)

func newTestDBWithRoles(t *testing.T) *db.Queries {
	t.Helper()
	return dbtest.NewDB(t).Queries
}

func TestUpsertAndGetDeviceRole(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "default-storage",
	})
	if err != nil {
		t.Fatalf("UpsertDeviceRole failed: %v", err)
	}

	role, err := queries.GetDeviceRole(ctx, "USB-001")
	if err != nil {
		t.Fatalf("GetDeviceRole failed: %v", err)
	}
	if role != "default-storage" {
		t.Errorf("expected role 'default-storage', got %q", role)
	}
}

func TestUpsertDeviceRole_OverwritesExisting(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "snapshot-backup",
	})
	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "default-storage",
	})

	role, err := queries.GetDeviceRole(ctx, "USB-001")
	if err != nil {
		t.Fatalf("GetDeviceRole failed: %v", err)
	}
	if role != "default-storage" {
		t.Errorf("expected role 'default-storage' after overwrite, got %q", role)
	}
}

func TestOnlyOneDefaultStorage_PartialUniqueIndex(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "default-storage",
	})
	if err != nil {
		t.Fatalf("first default-storage insert failed: %v", err)
	}

	// Second default-storage should fail due to partial unique index.
	err = queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-002",
		Role:         "default-storage",
	})
	if err == nil {
		t.Error("expected error when inserting second default-storage, got nil")
	}
}

func TestClearDefaultStorageRole(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "default-storage",
	})
	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-002",
		Role:         "snapshot-backup",
	})

	if err := queries.ClearDefaultStorageRole(ctx); err != nil {
		t.Fatalf("ClearDefaultStorageRole failed: %v", err)
	}

	role, _ := queries.GetDeviceRole(ctx, "USB-001")
	if role != "unassigned" {
		t.Errorf("expected cleared default-storage to be 'unassigned', got %q", role)
	}

	// Snapshot-backup should be untouched.
	role, _ = queries.GetDeviceRole(ctx, "USB-002")
	if role != "snapshot-backup" {
		t.Errorf("expected snapshot-backup to remain 'snapshot-backup', got %q", role)
	}
}

func TestClearDefaultStorageThenAssignNew(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "default-storage",
	})

	// Clear then assign a different device as default-storage.
	queries.ClearDefaultStorageRole(ctx)
	err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-002",
		Role:         "default-storage",
	})
	if err != nil {
		t.Fatalf("expected new default-storage after clear to succeed: %v", err)
	}

	role, _ := queries.GetDeviceRole(ctx, "USB-001")
	if role != "unassigned" {
		t.Errorf("expected old default-storage to be 'unassigned', got %q", role)
	}
	role, _ = queries.GetDeviceRole(ctx, "USB-002")
	if role != "default-storage" {
		t.Errorf("expected new default-storage to be 'primary', got %q", role)
	}
}

func TestGetAllDeviceRoles(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: "USB-001", Role: "default-storage"})
	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: "USB-002", Role: "snapshot-backup"})

	roles, err := queries.GetAllDeviceRoles(ctx)
	if err != nil {
		t.Fatalf("GetAllDeviceRoles failed: %v", err)
	}
	if len(roles) != 2 {
		t.Fatalf("expected 2 roles, got %d", len(roles))
	}

	roleMap := make(map[string]string)
	for _, r := range roles {
		roleMap[r.DeviceSerial] = r.Role
	}
	if roleMap["USB-001"] != "default-storage" {
		t.Errorf("expected USB-001 primary, got %q", roleMap["USB-001"])
	}
	if roleMap["USB-002"] != "snapshot-backup" {
		t.Errorf("expected USB-002 backup, got %q", roleMap["USB-002"])
	}
}

func TestDeleteDeviceRole(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: "USB-001", Role: "snapshot-backup"})
	if err := queries.DeleteDeviceRole(ctx, "USB-001"); err != nil {
		t.Fatalf("DeleteDeviceRole failed: %v", err)
	}

	_, err := queries.GetDeviceRole(ctx, "USB-001")
	if err == nil {
		t.Error("expected error after deleting role, got nil")
	}
}

func TestGetDeviceRole_NotFound(t *testing.T) {
	queries := newTestDBWithRoles(t)
	_, err := queries.GetDeviceRole(context.Background(), "NONEXISTENT")
	if err == nil {
		t.Error("expected error for nonexistent serial, got nil")
	}
}

func TestInvalidRoleRejectedByCheckConstraint(t *testing.T) {
	queries := newTestDBWithRoles(t)
	err := queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
		DeviceSerial: "USB-001",
		Role:         "invalid_role",
	})
	if err == nil {
		t.Error("expected CHECK constraint to reject invalid role, got nil")
	}
}

func TestMultipleSnapshotBackupsAllowed(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: "USB-001", Role: "snapshot-backup"})
	if err != nil {
		t.Fatalf("first snapshot-backup failed: %v", err)
	}
	err = queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: "USB-002", Role: "snapshot-backup"})
	if err != nil {
		t.Fatalf("second snapshot-backup failed: %v", err)
	}
}

func TestEmptySerial_InternalDevice(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: "", Role: "default-storage"})
	if err != nil {
		t.Fatalf("empty serial (internal device) should be allowed: %v", err)
	}

	role, err := queries.GetDeviceRole(ctx, "")
	if err != nil {
		t.Fatalf("GetDeviceRole for empty serial failed: %v", err)
	}
	if role != "default-storage" {
		t.Errorf("expected 'primary', got %q", role)
	}
}

func TestValidRoles(t *testing.T) {
	if !ValidRoles["default-storage"] || !ValidRoles["snapshot-backup"] || !ValidRoles["unassigned"] {
		t.Error("ValidRoles map missing expected entries")
	}
	if ValidRoles["admin"] || ValidRoles[""] {
		t.Error("ValidRoles should reject invalid strings")
	}
}

func TestDeviceNames_SerialKey(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	err := queries.UpsertDeviceName(ctx, db.UpsertDeviceNameParams{
		DeviceSerial: "USB-001",
		DisplayName:  "My Drive",
	})
	if err != nil {
		t.Fatalf("UpsertDeviceName failed: %v", err)
	}

	name, err := queries.GetDeviceName(ctx, "USB-001")
	if err != nil {
		t.Fatalf("GetDeviceName failed: %v", err)
	}
	if name != "My Drive" {
		t.Errorf("expected 'My Drive', got %q", name)
	}
}

func TestGetAllDeviceNames(t *testing.T) {
	queries := newTestDBWithRoles(t)
	ctx := context.Background()

	queries.UpsertDeviceName(ctx, db.UpsertDeviceNameParams{DeviceSerial: "USB-001", DisplayName: "Drive A"})
	queries.UpsertDeviceName(ctx, db.UpsertDeviceNameParams{DeviceSerial: "USB-002", DisplayName: "Drive B"})

	names, err := queries.GetAllDeviceNames(ctx)
	if err != nil {
		t.Fatalf("GetAllDeviceNames failed: %v", err)
	}
	if len(names) != 2 {
		t.Fatalf("expected 2 names, got %d", len(names))
	}
}

// TestSetRole_RawPasswordIsAppTooOld checks the re-confirmation passes a raw
// password's ErrAppTooOld through unwrapped, so the handler answers an old app
// with 426 rather than 401 (#2430).
func TestSetRole_RawPasswordIsAppTooOld(t *testing.T) {
	params := SetRoleParams{
		Ctx:      context.Background(),
		Queries:  newTestDBWithRoles(t),
		Role:     RoleUnassigned,
		Username: "admin",
		Password: "admin-password",
	}
	if _, err := SetRole(params); !errors.Is(err, authutil.ErrAppTooOld) {
		t.Fatalf("raw password = %v, want ErrAppTooOld", err)
	}
	params.Password = dbtest.AuthKey("admin-password")
	var unauthorized *UnauthorizedError
	if _, err := SetRole(params); !errors.As(err, &unauthorized) {
		t.Fatalf("unknown account's key = %v, want an UnauthorizedError", err)
	}
}

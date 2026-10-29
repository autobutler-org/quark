package deviceutil

import (
	"context"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

func TestDefaultStorageSerial(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)

	got, err := DefaultStorageSerial(DefaultStorageSerialParams{Ctx: ctx, Database: database})
	if err != nil || got.Serial != "" {
		t.Fatalf("no roles: got %q, %v; want empty", got.Serial, err)
	}

	for serial, role := range map[string]string{"USB-BACKUP": "snapshot-backup", "USB-SSD": "default-storage"} {
		if err := database.Queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: serial, Role: role}); err != nil {
			t.Fatal(err)
		}
	}
	got, err = DefaultStorageSerial(DefaultStorageSerialParams{Ctx: ctx, Database: database})
	if err != nil || got.Serial != "USB-SSD" {
		t.Fatalf("got %q, %v; want USB-SSD", got.Serial, err)
	}
}

func TestDefaultStorageSerial_NoDatabase(t *testing.T) {
	got, err := DefaultStorageSerial(DefaultStorageSerialParams{Ctx: context.Background()})
	if err != nil || got.Serial != "" {
		t.Fatalf("got %q, %v; want empty", got.Serial, err)
	}
}

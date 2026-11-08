package deviceutil

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// tempDeviceMount is a real directory a managed device can own. The status
// list probes that directory in the background, so cleanup retries until the
// probe's file is gone.
func tempDeviceMount(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "quark-device-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		var removeErr error
		for range 50 {
			removeErr = os.RemoveAll(dir)
			if removeErr == nil {
				return
			}
			time.Sleep(100 * time.Millisecond)
		}
		t.Errorf("remove %s: %v", dir, removeErr)
	})
	return dir
}

func unknownHealth(context.Context, storageutil.Device) *storageutil.DiskHealth {
	health := storageutil.UnknownDiskHealth()
	return &health
}

// TestListStatusesRegistersMissingExternalNamespace is the upload 404 in
// #3957: the status list reports an external drive enabled, and the registry
// still has no files namespace for it. The list is what the client reads
// immediately before uploading.
func TestListStatusesRegistersMissingExternalNamespace(t *testing.T) {
	mount := tempDeviceMount(t)
	const serial = "USB-LATE"
	svc := storageutil.NewStorageService(healthDetector{devices: []storageutil.Device{{
		Name:       "Quark",
		MountPoint: mount,
		DevicePath: "/dev/disk12s1",
		UsbInfo:    serialUSB{serial: serial},
	}}})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{
		ID: vfs.FilesNamespace(""),
	}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}

	var invalidations int
	svc.OnDevicesChanged(func() {
		invalidations++
		if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{
			Registry: registry,
			Storage:  svc,
		}); err != nil {
			t.Errorf("SyncDeviceNamespaces: %v", err)
		}
	})

	params := ListStatusesParams{
		Ctx:      context.Background(),
		Storage:  svc,
		Registry: registry,
		Health:   unknownHealth,
	}
	result, err := ListStatuses(params)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Statuses) != 1 || !result.Statuses[0].IsEnabled {
		t.Fatalf("statuses = %+v, want the drive enabled", result.Statuses)
	}
	if _, ok := registry.Get(vfs.FilesNamespace(serial)); !ok {
		t.Fatal("status list left the enabled drive without a files namespace")
	}
	if invalidations != 1 {
		t.Fatalf("invalidations = %d, want 1", invalidations)
	}

	if _, err := ListStatuses(params); err != nil {
		t.Fatal(err)
	}
	if invalidations != 1 {
		t.Fatalf("a second status list invalidated the cache again: %d", invalidations)
	}
}

// TestListStatusesLeavesUnreadyDriveUnregistered checks a mounted serial the
// files directory could not be created for. It stays out of the managed set,
// and the status list does not drop the device cache to adopt it.
func TestListStatusesLeavesUnreadyDriveUnregistered(t *testing.T) {
	const serial = "USB-UNREADY"
	svc := storageutil.NewStorageService(healthDetector{devices: []storageutil.Device{
		healthDevice(serial, "/dev/disk13s1"),
	}})
	registry := vfs.NewRegistry()
	var invalidations int
	svc.OnDevicesChanged(func() { invalidations++ })

	result, err := ListStatuses(ListStatusesParams{
		Ctx:      context.Background(),
		Storage:  svc,
		Registry: registry,
		Health:   unknownHealth,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Statuses) != 1 || result.Statuses[0].IsEnabled {
		t.Fatalf("statuses = %+v, want the drive disabled", result.Statuses)
	}
	if _, ok := registry.Get(vfs.FilesNamespace(serial)); ok {
		t.Fatal("an unready drive was registered")
	}
	if invalidations != 0 {
		t.Fatalf("invalidations = %d, want 0", invalidations)
	}
}

// TestListStatusesReportsActiveBackupJob checks each backup drive reports the
// snapshot backup pending or running onto it, so every tab knows a backup is
// running, and no other drive reports one (#4037).
func TestListStatusesReportsActiveBackupJob(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)
	for serial, role := range map[string]string{"BUSY": "snapshot-backup", "IDLE": "snapshot-backup", "DATA": "default-storage"} {
		if err := database.Queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: serial, Role: role}); err != nil {
			t.Fatal(err)
		}
	}
	job, err := database.Queries.CreateJob(ctx, db.CreateJobParams{
		Kind:   "snapshot-backup",
		Name:   "Back up onto BUSY",
		Params: `{"targetDeviceSerial":"BUSY"}`,
	})
	if err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(healthDetector{devices: []storageutil.Device{
		healthDevice("BUSY", "/dev/sdb1"),
		healthDevice("IDLE", "/dev/sdc1"),
		healthDevice("DATA", "/dev/sdd1"),
	}})

	result, err := ListStatuses(ListStatusesParams{Ctx: ctx, Storage: svc, Database: database, Health: unknownHealth})
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"BUSY": strconv.FormatInt(job.ID, 10), "IDLE": "", "DATA": ""}
	if len(result.Statuses) != len(want) {
		t.Fatalf("statuses = %+v, want %d", result.Statuses, len(want))
	}
	for _, status := range result.Statuses {
		serial := status.UsbInfo.GetSerial()
		if status.ActiveBackupJobID != want[serial] {
			t.Errorf("%s activeBackupJobId = %q, want %q", serial, status.ActiveBackupJobID, want[serial])
		}
	}
}

// cspell:ignore protectionutil sda sdb

package v0_storage_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/protectionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// protectionDevices is the detector the protection handler reads paths from.
type protectionDevices struct {
	devices []storageutil.Device
}

func (d protectionDevices) DetectDevices() ([]storageutil.Device, error) {
	return d.devices, nil
}

// serialUsb is a storage device whose only used method is GetSerial.
type serialUsb struct {
	storageutil.UsbDevice
	serial string
}

func (u serialUsb) GetSerial() string { return u.serial }

func protectionEngine(t *testing.T, database *db.DatabaseSqlc, devices []storageutil.Device) *gin.Engine {
	t.Helper()
	deps := deputil.NewDependencies().
		WithDatabase(database).
		WithStorageService(storageutil.NewStorageService(protectionDevices{devices: devices}))

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_storage.NewRouter())
	return engine
}

func getProtection(t *testing.T, engine *gin.Engine) protectionutil.StatusResult {
	t.Helper()
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/storage/protection", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("GET /storage/protection = %d %s", w.Code, w.Body.String())
	}
	var got protectionutil.StatusResult
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	return got
}

func finishBackup(t *testing.T, database *db.DatabaseSqlc, serial, status string) {
	t.Helper()
	ctx := context.Background()
	params, err := json.Marshal(backup.JobParams{TargetDeviceSerial: serial})
	if err != nil {
		t.Fatal(err)
	}
	created, err := database.Queries.CreateJob(ctx, db.CreateJobParams{
		Kind:   backup.Kind,
		Name:   "Snapshot backup",
		Params: string(params),
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.ClaimJob(ctx, db.ClaimJobParams{
		Owner: "test", ID: created.ID, LaneLimit: 1,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.FinishJob(ctx, db.FinishJobParams{
		Status: status, ID: created.ID, Owner: "test", Progress: 1,
	}); err != nil {
		t.Fatal(err)
	}
}

func TestGetProtectionStatus_NoBackupDrive(t *testing.T) {
	database := dbtest.NewDB(t)
	engine := protectionEngine(t, database, nil)
	got := getProtection(t, engine)
	if got.Level != protectionutil.LevelUnprotected || got.NextStep != protectionutil.NextStepAssignRole {
		t.Fatalf("status = %+v, want unprotected and assign-backup-role", got)
	}
	if len(got.Drives) != 0 {
		t.Fatalf("drives = %+v, want none", got.Drives)
	}
}

func TestGetProtectionStatus_CompletedBackupCounts(t *testing.T) {
	database := dbtest.NewDB(t)
	const serial = "USB-1"
	if err := database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
	}
	mount := t.TempDir()
	engine := protectionEngine(t, database, []storageutil.Device{{
		Name:       "Backup",
		DevicePath: "/dev/sdb1",
		MountPoint: mount,
		UsbInfo:    serialUsb{serial: serial},
	}})

	finishBackup(t, database, serial, "failed")
	got := getProtection(t, engine)
	if got.Level != protectionutil.LevelUnprotected || len(got.Drives) != 1 || got.Drives[0].Counts {
		t.Fatalf("after a failed backup = %+v, want unprotected and not counting", got)
	}
	if got.Drives[0].Reason != protectionutil.ReasonNoCompletedBackup || got.Drives[0].LastBackedUp != nil {
		t.Fatalf("failed drive = %+v", got.Drives[0])
	}

	finishBackup(t, database, serial, "completed")
	got = getProtection(t, engine)
	if got.Level != protectionutil.LevelBasic || len(got.Drives) != 1 || !got.Drives[0].Counts {
		t.Fatalf("after a completed backup = %+v, want basic and counting", got)
	}
	if got.Drives[0].Name != "Backup" || got.Drives[0].Serial != serial || got.Drives[0].LastBackedUp == nil {
		t.Fatalf("drive = %+v", got.Drives[0])
	}
	if time.Since(*got.Drives[0].LastBackedUp) > time.Minute {
		t.Errorf("last backed up = %v, want a moment ago", got.Drives[0].LastBackedUp)
	}
}

// TestGetProtectionStatus_DriveRecordOutlivesJobRow checks a drive whose
// completed job row has been pruned still counts on its own record while the
// record is inside StaleAfter, and stops counting once it is not.
func TestGetProtectionStatus_DriveRecordOutlivesJobRow(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	const serial = "USB-1"
	if err := database.Queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
	}
	engine := protectionEngine(t, database, []storageutil.Device{{
		Name:       "Backup",
		DevicePath: "/dev/sdb1",
		MountPoint: t.TempDir(),
		UsbInfo:    serialUsb{serial: serial},
	}})

	recent := time.Now().Add(-10 * 24 * time.Hour).Truncate(time.Second)
	if err := backup.RecordDriveSnapshot(ctx, database.Queries, serial, recent); err != nil {
		t.Fatal(err)
	}
	got := getProtection(t, engine)
	if got.Level != protectionutil.LevelBasic || len(got.Drives) != 1 || !got.Drives[0].Counts {
		t.Fatalf("with only a drive record = %+v, want basic and counting", got)
	}
	if got.Drives[0].LastBackedUp == nil || !got.Drives[0].LastBackedUp.Equal(recent) {
		t.Fatalf("last backed up = %v, want %v", got.Drives[0].LastBackedUp, recent)
	}

	old := time.Now().Add(-protectionutil.StaleAfter - time.Hour)
	if err := backup.RecordDriveSnapshot(ctx, database.Queries, serial, old); err != nil {
		t.Fatal(err)
	}
	got = getProtection(t, engine)
	if len(got.Drives) != 1 || got.Drives[0].Counts || got.Drives[0].Reason != protectionutil.ReasonStale {
		t.Fatalf("with a stale drive record = %+v, want not counting as stale", got)
	}
}

func TestGetProtectionStatus_TwoPartitionsCountOnce(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	for _, serial := range []string{"part-a", "part-b"} {
		if err := database.Queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
			DeviceSerial: serial,
			Role:         "snapshot-backup",
		}); err != nil {
			t.Fatal(err)
		}
		finishBackup(t, database, serial, "completed")
	}
	engine := protectionEngine(t, database, []storageutil.Device{
		{Name: "A", DevicePath: "/dev/sda1", MountPoint: t.TempDir(), UsbInfo: serialUsb{serial: "part-a"}},
		{Name: "B", DevicePath: "/dev/sda2", MountPoint: t.TempDir(), UsbInfo: serialUsb{serial: "part-b"}},
	})
	got := getProtection(t, engine)
	if got.Level != protectionutil.LevelBasic {
		t.Fatalf("level = %s, want basic (%+v)", got.Level, got)
	}
	var counting int
	for _, drive := range got.Drives {
		if drive.Counts {
			counting++
		}
	}
	if counting != 1 {
		t.Fatalf("counting drives = %d, want 1 (%+v)", counting, got.Drives)
	}
}

// A completed backup onto built-in storage, serial "", is its last backup.
func TestGetProtectionStatus_BuiltInStorageLastBackedUp(t *testing.T) {
	database := dbtest.NewDB(t)
	if err := database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
		DeviceSerial: "",
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatal(err)
	}
	finishBackup(t, database, "", "completed")
	got := getProtection(t, protectionEngine(t, database, nil))
	if len(got.Drives) != 1 || got.Drives[0].LastBackedUp == nil {
		t.Fatalf("drives = %+v, want built-in storage with a last backup", got.Drives)
	}
}

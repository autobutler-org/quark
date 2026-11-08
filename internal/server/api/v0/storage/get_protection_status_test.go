// cspell:ignore protectionutil sda sdb

package v0_storage_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path"
	"strings"
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
	"github.com/autobutler-org/quark/pkg/vfs"
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

// protectionEngine serves the protection route over devices. Each device is
// attached with a files namespace: its drive from drives, or an empty one.
func protectionEngine(t *testing.T, database *db.DatabaseSqlc, devices []storageutil.Device, drives map[string]vfs.VFS) *gin.Engine {
	t.Helper()
	reg := vfs.NewRegistry()
	for _, device := range devices {
		serial := ""
		if device.UsbInfo != nil {
			serial = device.UsbInfo.GetSerial()
		}
		fsys, ok := drives[serial]
		if !ok {
			fsys = vfs.NewMemVFS(vfs.FilesNamespace(serial))
		}
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	deps := deputil.NewDependencies().
		WithDatabase(database).
		WithVFSRegistry(reg).
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

func getProtectionBody(t *testing.T, engine *gin.Engine) []byte {
	t.Helper()
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/storage/protection", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("GET /storage/protection = %d %s", w.Code, w.Body.String())
	}
	return w.Body.Bytes()
}

func getProtection(t *testing.T, engine *gin.Engine) protectionutil.StatusResult {
	t.Helper()
	var got protectionutil.StatusResult
	if err := json.Unmarshal(getProtectionBody(t, engine), &got); err != nil {
		t.Fatal(err)
	}
	return got
}

func setRole(t *testing.T, database *db.DatabaseSqlc, serial, role string) {
	t.Helper()
	if err := database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         role,
	}); err != nil {
		t.Fatal(err)
	}
}

// putCopy puts a complete run on a backup drive, holding a copy of the data
// drive source and completed at at, and returns the run's folder.
func putCopy(t *testing.T, drive vfs.VFS, source string, at time.Time) string {
	t.Helper()
	ctx := context.Background()
	folder := at.Format("2006-01-02 15.04")
	dir := path.Join(backup.BackupsDir, folder)
	if err := drive.MkdirAll(ctx, dir); err != nil {
		t.Fatal(err)
	}
	m, err := backup.GenerateManifest(ctx, drive, dir)
	if err != nil {
		t.Fatal(err)
	}
	m.CompletedAt = at
	m.Drives = []backup.ManifestDrive{{Folder: "drive", Serial: source, Name: "Drive " + source}}
	if err := backup.WriteManifest(ctx, m, drive, dir); err != nil {
		t.Fatal(err)
	}
	return folder
}

// memDrive is an empty files namespace for the drive serial.
func memDrive(serial string) vfs.VFS {
	return vfs.NewMemVFS(vfs.FilesNamespace(serial))
}

// internalDevice is built-in storage. Its detector name is not what the app calls it.
func internalDevice(t *testing.T) storageutil.Device {
	return storageutil.Device{Name: "Macintosh HD", IsInternal: true, MountPoint: t.TempDir()}
}

func usbDevice(t *testing.T, serial, name, path string) storageutil.Device {
	return storageutil.Device{Name: name, DevicePath: path, MountPoint: t.TempDir(), UsbInfo: serialUsb{serial: serial}}
}

func queueBackup(t *testing.T, database *db.DatabaseSqlc, serial string) db.Job {
	t.Helper()
	params, err := json.Marshal(backup.JobParams{TargetDeviceSerial: serial})
	if err != nil {
		t.Fatal(err)
	}
	created, err := database.Queries.CreateJob(context.Background(), db.CreateJobParams{
		Kind:   backup.Kind,
		Name:   "Snapshot backup",
		Params: string(params),
	})
	if err != nil {
		t.Fatal(err)
	}
	return created
}

func finishBackup(t *testing.T, database *db.DatabaseSqlc, serial, status string) {
	t.Helper()
	ctx := context.Background()
	created := queueBackup(t, database, serial)
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
	engine := protectionEngine(t, database, []storageutil.Device{internalDevice(t)}, nil)
	body := getProtectionBody(t, engine)
	var got protectionutil.StatusResult
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if got.Level != protectionutil.LevelUnprotected || got.NextStep != protectionutil.NextStepAssignRole {
		t.Fatalf("status = %+v, want unprotected and assign-backup-role", got)
	}
	if len(got.DataDrives) != 1 || got.DataDrives[0].Serial != "" || got.DataDrives[0].Name != "Built-in storage" {
		t.Fatalf("data drives = %+v, want built-in storage", got.DataDrives)
	}
	for _, want := range []string{`"dataDrives":[`, `"backupDrives":[]`, `"copies":[]`} {
		if !strings.Contains(string(body), want) {
			t.Errorf("body %s lacks %s", body, want)
		}
	}
	if strings.Contains(string(body), `"drives"`) {
		t.Errorf("body %s still carries the old drives list", body)
	}
}

// A backup drive's newest run holding a data drive is its copy, and counts
// until it is older than StaleAfter. The run folders are read on every
// request, so deleting one changes the next answer (#4037).
func TestGetProtectionStatus_CopiesComeFromRuns(t *testing.T) {
	database := dbtest.NewDB(t)
	const serial = "USB-1"
	setRole(t, database, serial, "snapshot-backup")
	drive := memDrive(serial)
	engine := protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, serial, "Backup", "/dev/sdb1"),
	}, map[string]vfs.VFS{serial: drive})

	got := getProtection(t, engine)
	if got.Level != protectionutil.LevelUnprotected || got.NextStep != protectionutil.NextStepStartBackup {
		t.Fatalf("before any backup = %+v, want unprotected and start-backup", got)
	}
	if len(got.BackupDrives) != 1 || got.BackupDrives[0].State != protectionutil.BackupStateNoCopies || got.BackupDrives[0].NewestCopy != nil {
		t.Fatalf("backup drives = %+v, want one with no copies", got.BackupDrives)
	}

	stale := time.Now().Add(-protectionutil.StaleAfter - 24*time.Hour).Truncate(time.Second)
	recent := time.Now().Add(-10 * 24 * time.Hour).Truncate(time.Second)
	putCopy(t, drive, "", stale)
	recentRun := putCopy(t, drive, "", recent)
	got = getProtection(t, engine)
	if got.Level != protectionutil.LevelBasic || len(got.DataDrives) != 1 {
		t.Fatalf("with a run = %+v, want basic", got)
	}
	copies := got.DataDrives[0].Copies
	if len(copies) != 1 || !copies[0].Counts || copies[0].BackupSerial != serial || copies[0].BackupName != "Backup" || !copies[0].CopiedAt.Equal(recent) {
		t.Fatalf("copies = %+v, want Backup's counting copy at %v from the newest run", copies, recent)
	}
	backupDrive := got.BackupDrives[0]
	if backupDrive.State != protectionutil.BackupStateCurrent || len(backupDrive.Holds) != 1 || backupDrive.Holds[0].Name != "Built-in storage" {
		t.Fatalf("backup drive = %+v, want current, holding built-in storage", backupDrive)
	}

	if err := drive.Delete(context.Background(), path.Join(backup.BackupsDir, recentRun), vfs.DeleteOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	got = getProtection(t, engine)
	if got.Level != protectionutil.LevelUnprotected || got.DataDrives[0].Copies[0].Reason != protectionutil.ReasonStale {
		t.Fatalf("with only the stale run left = %+v, want unprotected and stale", got)
	}
	if got.BackupDrives[0].State != protectionutil.BackupStateBehind {
		t.Errorf("backup drive = %+v, want behind", got.BackupDrives[0])
	}
}

// A run still being written is not a copy.
func TestGetProtectionStatus_PartialRunDoesNotCount(t *testing.T) {
	database := dbtest.NewDB(t)
	const serial = "USB-1"
	setRole(t, database, serial, "snapshot-backup")
	drive := memDrive(serial)
	run := putCopy(t, drive, "", time.Now().Add(-time.Hour))
	partial := path.Join(backup.BackupsDir, "."+run+".partial")
	if err := drive.Move(context.Background(), path.Join(backup.BackupsDir, run), partial); err != nil {
		t.Fatal(err)
	}
	got := getProtection(t, protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, serial, "Backup", "/dev/sdb1"),
	}, map[string]vfs.VFS{serial: drive}))
	if got.Level != protectionutil.LevelUnprotected || got.BackupDrives[0].State != protectionutil.BackupStateNoCopies {
		t.Fatalf("status = %+v, want unprotected with no copies", got)
	}
}

// The per-target record and the job rows do not say which drives were
// copied, so neither counts on its own (#4037).
func TestGetProtectionStatus_PerTargetRecordAloneDoesNotCount(t *testing.T) {
	database := dbtest.NewDB(t)
	const serial = "USB-1"
	setRole(t, database, serial, "snapshot-backup")
	if err := backup.RecordDriveSnapshot(context.Background(), database.Queries, serial, time.Now()); err != nil {
		t.Fatal(err)
	}
	finishBackup(t, database, serial, "completed")
	got := getProtection(t, protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, serial, "Backup", "/dev/sdb1"),
	}, nil))
	if got.Level != protectionutil.LevelUnprotected || got.BackupDrives[0].State != protectionutil.BackupStateNoCopies {
		t.Fatalf("status = %+v, want unprotected with no copies", got)
	}
}

// A pending backup onto a drive is receiving. An unplugged backup drive is
// away, keeps the name it was given, and its copies from the scan made while
// it was attached still count. One never scanned has none.
func TestGetProtectionStatus_ReceivingAndAway(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	for _, serial := range []string{"BUSY", "AWAY", "NEVER"} {
		setRole(t, database, serial, "snapshot-backup")
	}
	if err := database.Queries.UpsertDeviceName(ctx, db.UpsertDeviceNameParams{DeviceSerial: "AWAY", DisplayName: "Offsite"}); err != nil {
		t.Fatal(err)
	}
	queueBackup(t, database, "BUSY")

	// AWAY is scanned while it is attached, then unplugged.
	away := memDrive("AWAY")
	putCopy(t, away, "", time.Now().Add(-time.Hour))
	getProtection(t, protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, "AWAY", "Away", "/dev/sdc1"),
	}, map[string]vfs.VFS{"AWAY": away}))

	got := getProtection(t, protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, "BUSY", "Busy", "/dev/sdb1"),
	}, nil))
	states := map[string]protectionutil.BackupDrive{}
	for _, drive := range got.BackupDrives {
		states[drive.Serial] = drive
	}
	if states["BUSY"].State != protectionutil.BackupStateReceiving {
		t.Errorf("BUSY = %+v, want receiving", states["BUSY"])
	}
	if states["AWAY"].State != protectionutil.BackupStateAway || states["AWAY"].Name != "Offsite" || len(states["AWAY"].Holds) != 1 {
		t.Errorf("AWAY = %+v, want away, named Offsite, holding its cached copy", states["AWAY"])
	}
	if states["NEVER"].State != protectionutil.BackupStateAway || len(states["NEVER"].Holds) != 0 {
		t.Errorf("NEVER = %+v, want away with no copies", states["NEVER"])
	}
	if got.Level != protectionutil.LevelBasic {
		t.Errorf("level = %s, want basic from the away drive's cached copy", got.Level)
	}
}

// A copy on built-in storage protects a USB main-storage drive.
func TestGetProtectionStatus_BuiltInStorageAsBackupDrive(t *testing.T) {
	database := dbtest.NewDB(t)
	setRole(t, database, "", "snapshot-backup")
	setRole(t, database, "MAIN", "default-storage")
	builtIn := memDrive("")
	putCopy(t, builtIn, "MAIN", time.Now().Add(-time.Hour))
	got := getProtection(t, protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, "MAIN", "Main", "/dev/sdb1"),
	}, map[string]vfs.VFS{"": builtIn}))
	if len(got.DataDrives) != 1 || got.DataDrives[0].Serial != "MAIN" || got.DataDrives[0].Level != protectionutil.LevelBasic {
		t.Fatalf("data drives = %+v, want only Main, basic", got.DataDrives)
	}
	if c := got.DataDrives[0].Copies[0]; c.BackupSerial != "" || c.BackupName != "Built-in storage" || !c.Counts {
		t.Errorf("copy = %+v, want a counting copy on built-in storage", c)
	}
}

func TestGetProtectionStatus_TwoPartitionsCountOnce(t *testing.T) {
	database := dbtest.NewDB(t)
	drives := map[string]vfs.VFS{}
	for _, serial := range []string{"part-a", "part-b"} {
		setRole(t, database, serial, "snapshot-backup")
		drives[serial] = memDrive(serial)
		putCopy(t, drives[serial], "", time.Now().Add(-time.Hour))
	}
	got := getProtection(t, protectionEngine(t, database, []storageutil.Device{
		internalDevice(t),
		usbDevice(t, "part-a", "A", "/dev/sda1"),
		usbDevice(t, "part-b", "B", "/dev/sda2"),
	}, drives))
	if got.Level != protectionutil.LevelBasic {
		t.Fatalf("level = %s, want basic (%+v)", got.Level, got)
	}
	var counting int
	for _, c := range got.DataDrives[0].Copies {
		if c.Counts {
			counting++
		}
	}
	if counting != 1 {
		t.Fatalf("counting copies = %d, want 1 (%+v)", counting, got.DataDrives[0].Copies)
	}
}

package authutil_test

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	_ "modernc.org/sqlite"
)

// deleteAccountFixture is a self-contained appliance on disk: a real database
// carrying the real migration set, a data directory with files and a mount
// point under it, and one external device data directory standing in for an
// attached drive.
type deleteAccountFixture struct {
	database      *db.DatabaseSqlc
	userID        int64
	dataDir       string
	filesDir      string
	mountsDir     string
	deviceDataDir string
}

func newDeleteAccountFixture(t *testing.T) deleteAccountFixture {
	t.Helper()

	root := t.TempDir()
	dataDir := filepath.Join(root, "data")
	filesDir := filepath.Join(dataDir, "files")
	mountsDir := filepath.Join(dataDir, "mounts")
	// Stands in for <mount>/quark/data on an attached drive.
	deviceDataDir := filepath.Join(root, "external", "quark", "data")

	for _, dir := range []string{filesDir, mountsDir, deviceDataDir} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
	}
	for _, file := range []string{
		filepath.Join(filesDir, "local.txt"),
		filepath.Join(deviceDataDir, "on-device.txt"),
	} {
		if err := os.WriteFile(file, []byte("data"), 0644); err != nil {
			t.Fatalf("write %s: %v", file, err)
		}
	}

	database := dbtest.NewDB(t)

	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: "testuser",
		Password: "TestPassword123!",
	}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	user, err := database.Queries.GetUserByUsername(context.Background(), "testuser")
	if err != nil {
		t.Fatalf("GetUserByUsername: %v", err)
	}

	return deleteAccountFixture{
		database:      database,
		userID:        user.ID,
		dataDir:       dataDir,
		filesDir:      filesDir,
		mountsDir:     mountsDir,
		deviceDataDir: deviceDataDir,
	}
}

func (f deleteAccountFixture) params() authutil.DeleteAccountParams {
	return authutil.DeleteAccountParams{
		Database:       f.database,
		Queries:        f.database.Queries,
		DataDir:        f.dataDir,
		DeviceDataDirs: []string{f.deviceDataDir},
		Username:       "testuser",
		UserID:         f.userID,
	}
}

func assertExists(t *testing.T, path, why string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Errorf("%s: %v", why, err)
	}
}

func assertGone(t *testing.T, path, why string) {
	t.Helper()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("%s: stat returned %v", why, err)
	}
}

// TestDeleteAccount_LeavesDevicesAloneWithoutOptIn is the safety property the
// devices parameter exists for: a database-and-files reset must not reach
// external device data, however much it wipes locally.
func TestDeleteAccount_LeavesDevicesAloneWithoutOptIn(t *testing.T) {
	fixture := newDeleteAccountFixture(t)
	params := fixture.params()
	params.DeleteDatabase = true
	params.DeleteFiles = true

	result, err := authutil.DeleteAccount(context.Background(), params)
	if err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}
	if result.DevicesDeleted {
		t.Error("DevicesDeleted should be false when devices was not selected")
	}

	assertGone(t, fixture.filesDir, "local files should be gone")
	assertExists(t, filepath.Join(fixture.deviceDataDir, "on-device.txt"),
		"external device data must survive a reset that did not opt into devices")
}

// TestDeleteAccount_DevicesOptInRemovesDeviceData verifies devices=true reaches
// the Quark data directory on an attached drive.
func TestDeleteAccount_DevicesOptInRemovesDeviceData(t *testing.T) {
	fixture := newDeleteAccountFixture(t)
	params := fixture.params()
	params.DeleteDevices = true

	result, err := authutil.DeleteAccount(context.Background(), params)
	if err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}
	if !result.DevicesDeleted {
		t.Error("expected DevicesDeleted=true")
	}

	assertGone(t, fixture.deviceDataDir, "device data directory should be gone")
	// devices alone: the appliance's own files are not in scope.
	assertExists(t, filepath.Join(fixture.filesDir, "local.txt"),
		"local files must survive a devices-only reset")
}

// TestDeleteAccount_DevicesOptInSparesTheRestOfTheDrive verifies the reset stops
// at the Quark subtree: a user's own files elsewhere on the drive are not ours
// to delete.
func TestDeleteAccount_DevicesOptInSparesTheRestOfTheDrive(t *testing.T) {
	fixture := newDeleteAccountFixture(t)
	// <mount>/holiday-photos, a sibling of <mount>/quark.
	mountRoot := filepath.Dir(filepath.Dir(fixture.deviceDataDir))
	unrelated := filepath.Join(mountRoot, "holiday-photos")
	if err := os.MkdirAll(unrelated, 0755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(unrelated, "beach.jpg"), []byte("photo"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}

	params := fixture.params()
	params.DeleteDevices = true
	if _, err := authutil.DeleteAccount(context.Background(), params); err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}

	assertGone(t, fixture.deviceDataDir, "device data directory should be gone")
	assertExists(t, filepath.Join(unrelated, "beach.jpg"),
		"non-Quark files on the drive must survive")
}

// TestDeleteAccount_DoesNotRecurseIntoMountPoints verifies a populated mount
// target survives a files reset. Recursing into it would delete through a live
// mount into the user's external drive.
func TestDeleteAccount_DoesNotRecurseIntoMountPoints(t *testing.T) {
	fixture := newDeleteAccountFixture(t)

	// A populated mount target stands in for a mounted drive: os.Remove refuses
	// a non-empty directory exactly as it refuses a mount point.
	mounted := filepath.Join(fixture.mountsDir, "SERIAL123")
	if err := os.MkdirAll(mounted, 0755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(mounted, "drive-contents.txt"), []byte("data"), 0644); err != nil {
		t.Fatalf("write: %v", err)
	}
	stale := filepath.Join(fixture.mountsDir, "SERIAL456")
	if err := os.MkdirAll(stale, 0755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	params := fixture.params()
	params.DeleteFiles = true
	if _, err := authutil.DeleteAccount(context.Background(), params); err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}

	assertExists(t, filepath.Join(mounted, "drive-contents.txt"),
		"a populated mount target must not be recursed into")
	assertGone(t, stale, "an empty mount target should be pruned")
}

// TestDeleteAccount_NoAspectSelected verifies the guard is on the service, not
// only the handler.
func TestDeleteAccount_NoAspectSelected(t *testing.T) {
	fixture := newDeleteAccountFixture(t)

	if _, err := authutil.DeleteAccount(context.Background(), fixture.params()); err == nil {
		t.Fatal("expected an error when no aspect is selected")
	}
	assertExists(t, filepath.Join(fixture.filesDir, "local.txt"), "nothing should have been touched")
	assertExists(t, filepath.Join(fixture.deviceDataDir, "on-device.txt"), "nothing should have been touched")
}

// TestDeleteAccount_ResetsHealthDatabase verifies the health database is emptied
// alongside the main one, through the live handle rather than by unlinking.
func TestDeleteAccount_ResetsHealthDatabase(t *testing.T) {
	fixture := newDeleteAccountFixture(t)

	healthDB, err := sql.Open("sqlite", db.DSN(filepath.Join(fixture.dataDir, "quark.health.db")))
	if err != nil {
		t.Fatalf("open health db: %v", err)
	}
	t.Cleanup(func() { healthDB.Close() })
	if _, err := healthDB.Exec(`CREATE TABLE traces (id INTEGER PRIMARY KEY, payload TEXT)`); err != nil {
		t.Fatalf("create traces: %v", err)
	}
	if _, err := healthDB.Exec(`INSERT INTO traces (payload) VALUES ('span')`); err != nil {
		t.Fatalf("seed traces: %v", err)
	}

	params := fixture.params()
	params.DeleteDatabase = true
	params.HealthDatabase = &db.DatabaseRaw{Db: healthDB}
	if _, err := authutil.DeleteAccount(context.Background(), params); err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}

	var tables int
	if err := healthDB.QueryRow(
		`SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'`,
	).Scan(&tables); err != nil {
		t.Fatalf("count health tables: %v", err)
	}
	if tables != 0 {
		t.Errorf("expected the health database emptied, %d tables remain", tables)
	}
}

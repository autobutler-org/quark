package backup

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// bindFixture is a Quark that took a snapshot of alice's vault onto the
// BACKUP-1 drive, and the restore params of a second database that reads it.
type bindFixture struct {
	source   *db.DatabaseSqlc
	driveDir string
	live     *db.DatabaseSqlc
	params   RestoreVaultParams
}

// newBindFixture snapshots the source onto the drive, binding the chat and
// vault files to it, and makes an empty live database with alice's account and
// the drive registered as the snapshot drive. The live database has its own
// salt secret, as another Quark would, until shareSecret gives it the source's.
func newBindFixture(t *testing.T) bindFixture {
	t.Helper()
	source := dbtest.NewDB(t)
	addChatUsers(t, source.Db, "alice")
	seedVault(t, source.Db, vaultOwner{"alice", randomBytes(t, 32), []string{"a", "b"}})
	target := makeTarget(t)
	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "BACKUP-1",
		Job:                newJob("BACKUP-1"),
		LiveDB:             source.Db,
		Queries:            source.Queries,
	}, nil, target.VFS); err != nil {
		t.Fatalf("SnapshotBackup: %v", err)
	}

	reg := vfs.NewRegistry()
	drive, err := vfs.NewLocalVFS(target.FilesDir, vfs.FilesNamespace("BACKUP-1"))
	if err != nil {
		t.Fatal(err)
	}
	if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace("BACKUP-1")}, drive); err != nil {
		t.Fatal(err)
	}
	live := dbtest.NewDB(t)
	addChatUsers(t, live.Db, "alice")
	chatExec(t, live.Db, `INSERT INTO device_roles (device_serial, role) VALUES ('BACKUP-1', 'snapshot-backup')`)
	return bindFixture{
		source:   source,
		driveDir: target.FilesDir,
		live:     live,
		params: RestoreVaultParams{
			Ctx: context.Background(), LiveDB: live.Db, Queries: live.Queries,
			Registry: reg, DeviceSerial: "BACKUP-1",
		},
	}
}

// shareSecret makes the live database the Quark that wrote the snapshot: the
// same salt secret, and the record that it binds what it writes to the drive.
func (f bindFixture) shareSecret(t *testing.T) {
	t.Helper()
	for _, key := range []string{"authSaltSecret", boundDriveKeyPrefix + "BACKUP-1"} {
		value, err := f.source.Queries.GetSetting(context.Background(), key)
		if err != nil {
			t.Fatalf("read %s: %v", key, err)
		}
		if err := f.live.Queries.SetSetting(context.Background(), db.SetSettingParams{Key: key, Value: value}); err != nil {
			t.Fatal(err)
		}
	}
}

// refused asserts RestoreVault turns the drive down as not written here, and
// that nothing reached the live vault.
func (f bindFixture) refused(t *testing.T, why string) {
	t.Helper()
	if _, err := RestoreVault(f.params); !errors.Is(err, ErrBackupNotFromThisQuark) {
		t.Errorf("RestoreVault of %s = %v, want ErrBackupNotFromThisQuark", why, err)
	}
	assertRows(t, f.live.Db, `SELECT COUNT(*) FROM vault_keys`, "[0]")
}

// A snapshot binds both files to the Quark that wrote it, and that Quark
// restores them (#4010).
func TestSnapshotBackup_BindsChatAndVaultToThisQuark(t *testing.T) {
	f := newBindFixture(t)
	for _, name := range []string{backupChatFilename, backupVaultFilename} {
		if _, err := os.Stat(filepath.Join(f.driveDir, name+bindingSuffix)); err != nil {
			t.Errorf("the snapshot wrote no binding for %s: %v", name, err)
		}
	}
	f.shareSecret(t)
	result, err := RestoreVault(f.params)
	if err != nil {
		t.Fatalf("RestoreVault: %v", err)
	}
	if result.Items != 2 {
		t.Errorf("restored %d items, want 2", result.Items)
	}
}

// Another Quark's snapshot is refused, with the binding beside it.
func TestRestoreVault_RefusesAnotherQuarksSnapshot(t *testing.T) {
	f := newBindFixture(t)
	// The live Quark has a secret of its own.
	if _, err := settingsutil.AuthSaltSecretIn(context.Background(), f.live.Queries); err != nil {
		t.Fatal(err)
	}
	f.refused(t, "another Quark's snapshot")
}

// A file changed after the snapshot wrote it is refused.
func TestRestoreVault_RefusesAChangedFile(t *testing.T) {
	f := newBindFixture(t)
	f.shareSecret(t)
	planted := dbtest.NewDB(t).Db
	addChatUsers(t, planted, "alice")
	seedVault(t, planted, vaultOwner{"alice", randomBytes(t, 32), []string{"planted"}})
	// Overwrite the bound file with another, keeping the binding beside it.
	other := exportVault(t, planted)
	data, err := os.ReadFile(filepath.Join(other, backupVaultFilename))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.driveDir, backupVaultFilename), data, 0o600); err != nil {
		t.Fatal(err)
	}
	f.refused(t, "a file swapped after the snapshot")
}

// Removing the binding does not turn a bound drive's file into an old,
// unbound one: this Quark knows it binds what it writes there.
func TestRestoreVault_RefusesAStrippedBinding(t *testing.T) {
	f := newBindFixture(t)
	f.shareSecret(t)
	if err := os.Remove(filepath.Join(f.driveDir, backupVaultFilename+bindingSuffix)); err != nil {
		t.Fatal(err)
	}
	f.refused(t, "a bound drive's file with its binding removed")
}

// A snapshot taken before binding still restores, from a drive this Quark
// has not bound a snapshot to.
func TestRestoreVault_RestoresASnapshotFromBeforeBinding(t *testing.T) {
	f := newBindFixture(t)
	for _, name := range []string{backupChatFilename, backupVaultFilename} {
		if err := os.Remove(filepath.Join(f.driveDir, name+bindingSuffix)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := RestoreVault(f.params); err != nil {
		t.Fatalf("RestoreVault of a snapshot from before binding: %v", err)
	}
}

// An unbound export leaves no stale binding behind to refuse it.
func TestExportVault_UnboundRemovesAStaleBinding(t *testing.T) {
	f := newBindFixture(t)
	if _, err := ExportVault(context.Background(), f.source.Db, f.driveDir); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(f.driveDir, backupVaultFilename+bindingSuffix)); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("an unbound export left the old binding: %v", err)
	}
}

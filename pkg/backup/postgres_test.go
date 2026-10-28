package backup

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// postgresDatabase is an empty, migrated PostgreSQL database of the test's
// own, opened the way the server opens one.
func postgresDatabase(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database, err := db.ConnectToPostgres(dbtest.PostgresURL(t))
	if err != nil {
		t.Fatalf("ConnectToPostgres: %v", err)
	}
	t.Cleanup(func() { database.Db.Close() })
	return database
}

// expectBackedUpSeparately fails unless err is the refusal the chat and vault
// backups give on PostgreSQL, where the database's own backups carry them.
func expectBackedUpSeparately(t *testing.T, what string, err error) {
	t.Helper()
	if !errors.Is(err, ErrDatabaseBackedUpSeparately) {
		t.Errorf("%s = %v, want ErrDatabaseBackedUpSeparately", what, err)
	}
}

// The chat and vault backups attach a SQLite file to the live connection. On
// PostgreSQL the operator's database backups carry those rows, so each says
// so and writes nothing, and a snapshot is not refused for it: it gets as far
// as it does on SQLite.
func TestChatAndVaultBackupOnPostgresAreRefused(t *testing.T) {
	database := postgresDatabase(t)
	ctx := context.Background()
	dir := t.TempDir()

	_, err := ExportChat(ctx, database.Db, dir)
	expectBackedUpSeparately(t, "ExportChat", err)
	_, err = ImportChat(ctx, database.Db, dir)
	expectBackedUpSeparately(t, "ImportChat", err)
	_, err = ExportVault(ctx, database.Db, dir)
	expectBackedUpSeparately(t, "ExportVault", err)
	_, err = ImportVault(ctx, database.Db, dir)
	expectBackedUpSeparately(t, "ImportVault", err)
	if left, err := os.ReadDir(dir); err != nil || len(left) != 0 {
		t.Errorf("the refused backups left %v in the target directory (%v)", left, err)
	}

	for backend, d := range map[string]*db.DatabaseSqlc{"PostgreSQL": database, "SQLite": dbtest.NewDB(t)} {
		if _, err := StartSnapshotBackup(StartSnapshotBackupParams{
			Ctx: ctx, Queries: d.Queries, TargetDeviceSerial: "SER1",
		}); !errors.Is(err, ErrTargetRoleRequired) {
			t.Errorf("StartSnapshotBackup on %s = %v, want ErrTargetRoleRequired", backend, err)
		}
	}
}

// A snapshot of a PostgreSQL-backed Quark is the files and the manifest: no
// chat or vault file is written beside them, and the ones an earlier SQLite
// snapshot left at the root are removed rather than listed in the manifest. A
// source file of the same name inside a device directory stays.
func TestSnapshotBackupOnPostgresHoldsFilesOnly(t *testing.T) {
	database := postgresDatabase(t)
	src := makeSource(t, "Drive A", "SERIAL-A", map[string]string{"a.txt": "a", backupChatFilename: "mine"})
	target := makeTarget(t)
	for _, name := range []string{backupChatFilename, backupVaultFilename} {
		if err := os.WriteFile(filepath.Join(target.FilesDir, name), []byte("stale"), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                newJob("TARGET"),
		LiveDB:             database.Db,
	}, []SourceDevice{src}, target.VFS); err != nil {
		t.Fatalf("SnapshotBackup: %v", err)
	}

	for _, name := range []string{backupChatFilename, backupVaultFilename} {
		if _, err := os.Stat(filepath.Join(target.FilesDir, name)); !os.IsNotExist(err) {
			t.Errorf("the snapshot wrote %s (%v)", name, err)
		}
	}
	manifest, err := ReadManifest(context.Background(), target)
	if err != nil {
		t.Fatal(err)
	}
	if len(manifest.Files) != 2 {
		t.Errorf("the manifest covers %v, want the two source files", manifest.Files)
	}
	for _, name := range []string{backupChatFilename, backupVaultFilename} {
		if _, ok := manifest.Files[name]; ok {
			t.Errorf("the manifest lists %s", name)
		}
	}
	if _, err := os.Stat(filepath.Join(target.FilesDir, deviceDirName(src.Name, src.Serial), backupChatFilename)); err != nil {
		t.Errorf("the device directory's %s is gone: %v", backupChatFilename, err)
	}
}

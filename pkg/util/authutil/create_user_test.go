package authutil_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

type internalDevice struct{ mountPoint string }

func (d internalDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: d.mountPoint, IsInternal: true}}, nil
}

// createUserFixture is a set-up Quark with one internal device whose files
// namespace the created folders land in. filesDir is that namespace's
// directory on disk, for a test to look at or put something in the way.
type createUserFixture struct {
	database *db.DatabaseSqlc
	storage  *storageutil.StorageService
	files    vfs.VFS
	filesDir string
}

func newCreateUserFixture(t *testing.T) createUserFixture {
	t.Helper()
	return newCreateUserFixtureWith(t, nil)
}

// newCreateUserFixtureWith runs beforeSetup on the files directory before the
// founder is set up, so a test can put something there first.
func newCreateUserFixtureWith(t *testing.T, beforeSetup func(filesDir string)) createUserFixture {
	t.Helper()
	mountPoint := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mountPoint, "quark", "data", "files"), 0o755); err != nil {
		t.Fatal(err)
	}
	storage := storageutil.NewStorageService(internalDevice{mountPoint: mountPoint})
	devices, err := storage.GetManagedDevices()
	if err != nil || len(devices) != 1 {
		t.Fatalf("GetManagedDevices = %v, %v", devices, err)
	}
	if beforeSetup != nil {
		beforeSetup(devices[0].FilesDir)
	}
	database := dbtest.NewDB(t)
	files := vfs.NewStorageServiceVFS(storage, vfs.FilesNamespace(""))
	setupFounder(t, database, files)
	return createUserFixture{database: database, storage: storage, files: files, filesDir: devices[0].FilesDir}
}

func (f createUserFixture) create(username string) (authutil.CreateUserResult, error) {
	return authutil.CreateUser(context.Background(), authutil.CreateUserParams{
		Database: f.database,
		Username: username,
		AuthKey:  dbtest.AuthKey("initial-password"), SaltSecret: dbtest.SaltSecret,
		Files: f.files,
	})
}

func (f createUserFixture) userCount(t *testing.T) int {
	t.Helper()
	var count int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	return count
}

// TestCreateUser_RecoveryKeyFromFirstLogin checks an admin-created account is
// active with no recovery credential, cannot recover until its client gives it
// a recovery key, is told so at every sign-in until then, and is handed no
// phrase by the Quark (#2430).
func TestCreateUser_RecoveryKeyFromFirstLogin(t *testing.T) {
	f := newCreateUserFixture(t)
	ctx := context.Background()
	q := f.database.Queries

	result, err := f.create("bob")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	user, err := q.GetUserByID(ctx, result.UserID)
	if err != nil {
		t.Fatal(err)
	}
	if user.Status != authutil.StatusActive || user.IsAdmin != 0 || user.RecoveryPhraseHash != "" || user.RecoveryKeyHash != "" {
		t.Errorf("created account status=%q admin=%d, want active, non-admin, no recovery credential", user.Status, user.IsAdmin)
	}
	if result.FolderPath != "users/bob" {
		t.Errorf("FolderPath = %q, want users/bob", result.FolderPath)
	}

	recoverBob := func() error {
		_, err := authutil.Recover(ctx, f.database, authutil.RecoverParams{Username: "bob", RecoveryKey: dbtest.AuthKey("bob-phrase"), NewAuthKey: dbtest.AuthKey("another-password"), SaltSecret: dbtest.SaltSecret})
		return err
	}
	if err := recoverBob(); err == nil || err.Error() != "invalid recovery phrase" {
		t.Errorf("recover before a recovery key = %v, want invalid recovery phrase", err)
	}
	for range 2 {
		login, err := authutil.Login(ctx, q, authutil.LoginParams{Username: "bob", AuthKey: dbtest.AuthKey("initial-password")})
		if err != nil || !login.LegacyRecovery {
			t.Fatalf("login before a recovery key = %+v, %v; want legacyRecovery", login, err)
		}
	}
	if _, err := authutil.SetRecoveryKey(ctx, f.database, authutil.SetRecoveryKeyParams{UserID: result.UserID, RecoveryKey: dbtest.AuthKey("bob-phrase")}); err != nil {
		t.Fatal(err)
	}
	if err := recoverBob(); err != nil {
		t.Errorf("recover with the key: %v", err)
	}
}

// TestCreateUser_PrivateFolder checks the home is made at users/<username> and
// owned by the new account through the access layer, and nobody else's. A
// top-level folder of the same name is a different namespace now (#2016), so it
// neither blocks the account nor becomes readable.
func TestCreateUser_PrivateFolder(t *testing.T) {
	f := newCreateUserFixture(t)
	ctx := context.Background()

	if err := os.Mkdir(filepath.Join(f.filesDir, "bob"), 0o755); err != nil {
		t.Fatal(err)
	}

	result, err := f.create("bob")
	if err != nil {
		t.Fatalf("CreateUser with a top-level folder of the same name: %v", err)
	}
	if result.FolderPath != "users/bob" {
		t.Errorf("FolderPath = %q, want users/bob", result.FolderPath)
	}
	if info, err := os.Stat(filepath.Join(f.filesDir, "users", "bob")); err != nil || !info.IsDir() {
		t.Fatalf("private folder: %v", err)
	}
	loaded, err := accessutil.Load(accessutil.LoadParams{
		Ctx:       ctx,
		Database:  f.database,
		Storage:   f.storage,
		Principal: accessutil.Principal{UserID: result.UserID},
	})
	if err != nil {
		t.Fatal(err)
	}
	if check := loaded.Access.Check("", "users/bob/notes.txt", accessutil.Owner); !check.Allowed {
		t.Errorf("new account's access to its home = %+v, want owner", check)
	}
	if check := loaded.Access.Check("", "bob", accessutil.Read); check.Readable {
		t.Error("new account can read the top-level folder that shares its name")
	}
	if check := loaded.Access.Check("", "users/carol", accessutil.Read); check.Readable {
		t.Error("new account can read another account's home")
	}
	// Each home is the only grant it carries: users/ itself gets none, and
	// breadcrumb visibility is what shows the path to someone granted beneath
	// it. The founder's home is there too, because every account gets one.
	var granted string
	if err := f.database.Db.QueryRow(`SELECT GROUP_CONCAT(rel_path) FROM path_access ORDER BY rel_path`).Scan(&granted); err != nil {
		t.Fatal(err)
	}
	if granted != "users/admin,users/bob" {
		t.Errorf("path_access holds %q, want only the two homes", granted)
	}
}

// TestCreateUser_RefusalsLeaveNothing checks a taken name and an invalid name
// are refused with no account row.
func TestCreateUser_RefusalsLeaveNothing(t *testing.T) {
	f := newCreateUserFixture(t)
	before := f.userCount(t)

	if _, err := f.create("admin"); !errors.Is(err, authutil.ErrUsernameTaken) {
		t.Errorf("taken name = %v, want ErrUsernameTaken", err)
	}
	for _, name := range []string{"../x", "a/b", ".trash"} {
		if _, err := f.create(name); !errors.Is(err, authutil.ErrInvalidUsername) {
			t.Errorf("create %q = %v, want ErrInvalidUsername", name, err)
		}
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(f.filesDir), "x")); !os.IsNotExist(err) {
		t.Errorf("../x made a folder outside the files directory: %v", err)
	}
	if after := f.userCount(t); after != before {
		t.Errorf("refusals left %d account rows, want %d", after, before)
	}
	// Only the founder's own home, made when the Quark was set up.
	var granted string
	if err := f.database.Db.QueryRow(`SELECT GROUP_CONCAT(rel_path) FROM path_access`).Scan(&granted); err != nil {
		t.Fatal(err)
	}
	if granted != "users/admin" {
		t.Errorf("refusals left path_access holding %q, want only users/admin", granted)
	}
}

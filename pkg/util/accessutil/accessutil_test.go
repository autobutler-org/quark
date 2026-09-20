package accessutil_test

import (
	"context"
	"database/sql"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// keys lists every row as "serial|rel_path".
func (f fixture) keys(t *testing.T) map[string]bool {
	t.Helper()
	rows, err := f.database.Db.Query(`SELECT device_serial, rel_path FROM path_access`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	keys := map[string]bool{}
	for rows.Next() {
		var serial, rel string
		if err := rows.Scan(&serial, &rel); err != nil {
			t.Fatal(err)
		}
		keys[serial+"|"+rel] = true
	}
	return keys
}

func TestMoveRowsCarriesTheTree(t *testing.T) {
	f := newFixture(t)
	for _, rel := range []string{"a", "a/b", "a/b/c.txt", "ab", "a_b", "A", "other"} {
		f.grant(t, f.userID, "", rel, accessutil.Read)
	}
	bus := eventbus.New()
	events, unsub := bus.Subscribe("move-rows-test")
	defer unsub()

	result, err := accessutil.MoveRows(accessutil.MoveRowsParams{
		Ctx: context.Background(), Database: f.database, EventBus: bus,
		OldPath: "a/", NewSerial: "USB-1", NewPath: "/moved/a",
	})
	if err != nil || result.Moved != 3 {
		t.Fatalf("MoveRows = %+v, %v; want 3 rows moved", result, err)
	}
	want := map[string]bool{
		"|ab": true, "|a_b": true, "|A": true, "|other": true,
		"USB-1|moved/a": true, "USB-1|moved/a/b": true, "USB-1|moved/a/b/c.txt": true,
	}
	if got := f.keys(t); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
	select {
	case evt := <-events:
		if evt.Kind != eventbus.EventAccessChanged || evt.Path != "moved/a" || evt.DeviceSerial != "USB-1" {
			t.Errorf("event = %+v, want access_changed at USB-1 moved/a", evt)
		}
	default:
		t.Error("MoveRows published no access_changed event")
	}
}

func TestMoveRowsReplacesTheDestination(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "src/x.txt", accessutil.Write)
	f.grant(t, f.userID, "", "dst", accessutil.Read)
	f.grant(t, f.userID, "", "dst/old.txt", accessutil.Owner)

	if _, err := accessutil.MoveRows(accessutil.MoveRowsParams{
		Ctx: context.Background(), Database: f.database, OldPath: "src", NewPath: "dst",
	}); err != nil {
		t.Fatalf("MoveRows: %v", err)
	}
	if got, want := f.keys(t), map[string]bool{"|dst/x.txt": true}; !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestMoveRowsRefusesAMoveIntoItself(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "a/b", accessutil.Read)
	for _, tc := range [][2]string{{"a", "a/b/c"}, {"a/b", "a"}} {
		_, err := accessutil.MoveRows(accessutil.MoveRowsParams{
			Ctx: context.Background(), Database: f.database, OldPath: tc[0], NewPath: tc[1],
		})
		if !errors.Is(err, accessutil.ErrMoveIntoItself) {
			t.Errorf("MoveRows(%q → %q) = %v, want ErrMoveIntoItself", tc[0], tc[1], err)
		}
	}
	if got, want := f.keys(t), map[string]bool{"|a/b": true}; !maps.Equal(got, want) {
		t.Errorf("a refused move changed rows: %v", got)
	}
}

func TestDeleteRowsTakesTheTree(t *testing.T) {
	f := newFixture(t)
	for _, rel := range []string{"", "a", "a/b", "ab"} {
		f.grant(t, f.userID, "", rel, accessutil.Read)
	}
	f.grant(t, f.userID, "USB-1", "a", accessutil.Read)

	result, err := accessutil.DeleteRows(accessutil.DeleteRowsParams{
		Ctx: context.Background(), Database: f.database, Paths: []string{"a", "/", ""},
	})
	if err != nil || result.Deleted != 2 {
		t.Fatalf("DeleteRows = %+v, %v; want 2 rows deleted", result, err)
	}
	if got, want := f.keys(t), map[string]bool{"|": true, "|ab": true, "USB-1|a": true}; !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestTrashVisibility(t *testing.T) {
	f := newFixture(t)
	eve := createUser(t, f.database, "eve")
	f.grant(t, f.userID, "", "shared", accessutil.Read)
	f.grant(t, f.userID, "", "writable", accessutil.Write)
	f.grant(t, f.userID, "", storageutil.TrashPath("T-rows", ""), accessutil.Owner)
	bob := f.load(t, accessutil.Principal{UserID: f.userID})
	admin := f.load(t, accessutil.System)

	for _, tc := range []struct {
		name, trashName, original string
		trashedBy                 int64
		see, del                  bool
	}{
		{"bob's own item", "T1", "private/x.txt", f.userID, true, true},
		{"eve's item from a read share", "T2", "shared/y.txt", eve, true, false},
		{"eve's item from a write share", "T3", "writable/z.txt", eve, true, true},
		{"eve's private item", "T4", "private/w.txt", eve, false, false},
		{"eve's item whose rows name bob", "T-rows", "private/v.txt", eve, true, false},
		{"a legacy item in a read share", "T5", "shared/old.txt", 0, false, false},
	} {
		if got := bob.CanSeeTrash("", tc.trashName, tc.original, tc.trashedBy); got != tc.see {
			t.Errorf("%s: CanSeeTrash = %v, want %v", tc.name, got, tc.see)
		}
		if got := bob.CanDeleteTrash("", tc.original, tc.trashedBy); got != tc.del {
			t.Errorf("%s: CanDeleteTrash = %v, want %v", tc.name, got, tc.del)
		}
		if !admin.CanSeeTrash("", tc.trashName, tc.original, tc.trashedBy) || !admin.CanDeleteTrash("", tc.original, tc.trashedBy) {
			t.Errorf("%s: an admin cannot see or delete it", tc.name)
		}
	}
}

func TestRowChangesWithoutADatabaseDoNothing(t *testing.T) {
	ctx := context.Background()
	if result, err := accessutil.MoveRows(accessutil.MoveRowsParams{Ctx: ctx, OldPath: "a", NewPath: "b"}); err != nil || result.Moved != 0 {
		t.Errorf("MoveRows without a database = %+v, %v", result, err)
	}
	if result, err := accessutil.DeleteRows(accessutil.DeleteRowsParams{Ctx: ctx, Paths: []string{"a"}}); err != nil || result.Deleted != 0 {
		t.Errorf("DeleteRows without a database = %+v, %v", result, err)
	}
}

type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

// fixture is a migrated database, one internal device and one non-admin user.
type fixture struct {
	database *db.DatabaseSqlc
	storage  *storageutil.StorageService
	filesDir string
	userID   int64
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	mountPoint := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mountPoint, "quark", "data", "files"), 0o755); err != nil {
		t.Fatal(err)
	}
	storage := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	devices, err := storage.GetManagedDevices()
	if err != nil || len(devices) != 1 {
		t.Fatalf("GetManagedDevices = %v, %v", devices, err)
	}
	database := dbtest.NewDB(t)
	return fixture{
		database: database,
		storage:  storage,
		filesDir: devices[0].FilesDir,
		userID:   createUser(t, database, "bob"),
	}
}

func createUser(t *testing.T, database *db.DatabaseSqlc, username string) int64 {
	t.Helper()
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: username, PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	return user.ID
}

func (f fixture) grant(t *testing.T, userID int64, serial, rel string, level accessutil.Level) {
	t.Helper()
	if err := f.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		DeviceSerial: serial,
		RelPath:      accessutil.Canonical(rel),
		UserID:       sql.NullInt64{Int64: userID, Valid: true},
		Level:        level.String(),
	}); err != nil {
		t.Fatalf("SetUserPathAccess: %v", err)
	}
}

func (f fixture) load(t *testing.T, principal accessutil.Principal) accessutil.Access {
	t.Helper()
	result, err := accessutil.Load(accessutil.LoadParams{
		Ctx: context.Background(), Database: f.database, Storage: f.storage, Principal: principal,
	})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	return result.Access
}

func (f fixture) mkdir(t *testing.T, rel string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(f.filesDir, filepath.FromSlash(rel)), 0o755); err != nil {
		t.Fatal(err)
	}
}

func (f fixture) rowCount(t *testing.T) int {
	t.Helper()
	var n int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestLevelIsTheUnionOverAncestors(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "a", accessutil.Read)
	f.grant(t, f.userID, "", "a/b", accessutil.Write)
	access := f.load(t, accessutil.Principal{UserID: f.userID})

	for p, want := range map[string]accessutil.Level{
		"":        accessutil.None,
		"a":       accessutil.Read,
		"a/x":     accessutil.Read,
		"a/b":     accessutil.Write,
		"a/b/c/d": accessutil.Write,
		"other":   accessutil.None,
	} {
		if got := access.Level("", p); got != want {
			t.Errorf("Level(%q) = %v, want %v", p, got, want)
		}
	}
}

func TestLevelComesFromGroupsAndEveryone(t *testing.T) {
	f := newFixture(t)
	res, err := f.database.Db.Exec(`INSERT INTO groups (name) VALUES ('family')`)
	if err != nil {
		t.Fatal(err)
	}
	familyID, _ := res.LastInsertId()
	if _, err := f.database.Db.Exec(`INSERT INTO group_members (group_id, user_id) VALUES (?, ?)`, familyID, f.userID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.database.Db.Exec(
		`INSERT INTO path_access (rel_path, group_id, level) VALUES ('family', ?, 'write'),
		 ('public', (SELECT id FROM groups WHERE name = 'everyone'), 'read')`, familyID); err != nil {
		t.Fatal(err)
	}
	stranger := createUser(t, f.database, "stranger")

	member := f.load(t, accessutil.Principal{UserID: f.userID})
	if got := member.Level("", "family/photo.jpg"); got != accessutil.Write {
		t.Errorf("member Level(family/photo.jpg) = %v, want write", got)
	}
	if got := member.Level("", "public"); got != accessutil.Read {
		t.Errorf("member Level(public) = %v, want read", got)
	}

	other := f.load(t, accessutil.Principal{UserID: stranger})
	if got := other.Level("", "family"); got != accessutil.None {
		t.Errorf("non-member Level(family) = %v, want none", got)
	}
	if got := other.Level("", "public/doc.txt"); got != accessutil.Read {
		t.Errorf("everyone Level(public/doc.txt) = %v, want read", got)
	}
}

func TestAdminIsAllowedWithoutADatabase(t *testing.T) {
	result, err := accessutil.Load(accessutil.LoadParams{Ctx: context.Background(), Principal: accessutil.System})
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	check := result.Access.Check("any-serial", "anything/at/all", accessutil.Owner)
	if !check.Readable || !check.Allowed || check.Level != accessutil.Owner {
		t.Errorf("admin Check = %+v, want owner", check)
	}
}

func TestNonAdminIsDeniedWithoutADatabaseOrPrincipal(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "", accessutil.Owner)

	noDB, err := accessutil.Load(accessutil.LoadParams{
		Ctx: context.Background(), Storage: f.storage, Principal: accessutil.Principal{UserID: f.userID},
	})
	if err != nil {
		t.Fatal(err)
	}
	if check := noDB.Access.Check("", "x", accessutil.Read); check.Readable {
		t.Errorf("nil database Check = %+v, want denied", check)
	}

	nobody := f.load(t, accessutil.Principal{})
	if check := nobody.Check("", "x", accessutil.Read); check.Readable {
		t.Errorf("zero principal Check = %+v, want denied", check)
	}
}

func TestCanonicalPathsMatch(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "Photos/", accessutil.Read)
	f.grant(t, f.userID, "", "foo", accessutil.Read)
	access := f.load(t, accessutil.Principal{UserID: f.userID})

	if got := access.Level("", "/Photos"); got != accessutil.Read {
		t.Errorf(`Level("/Photos") = %v, want read`, got)
	}
	if got := access.Level("", "foobar"); got != accessutil.None {
		t.Errorf(`"foo" granted "foobar": Level = %v`, got)
	}
	if access.HasBeneath("", "fo") {
		t.Error(`HasBeneath("fo") is true for a grant at "foo"`)
	}
	if got := access.Level("", "foo/../secret"); got != accessutil.None {
		t.Errorf(`Level("foo/../secret") = %v, want none`, got)
	}
}

func TestUnknownSerialIsUnreadable(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "USB-GONE", "", accessutil.Owner)
	access := f.load(t, accessutil.Principal{UserID: f.userID})

	if check := access.Check("USB-GONE", "file.txt", accessutil.Read); check.Readable {
		t.Errorf("detached device Check = %+v, want unreadable", check)
	}
	if access.Visible("USB-GONE", "") {
		t.Error("detached device root is visible")
	}
}

func TestSymlinkOutOfASharedFolderIsDenied(t *testing.T) {
	f := newFixture(t)
	f.mkdir(t, "shared/sub")
	f.mkdir(t, "private")
	outside := t.TempDir()
	for link, target := range map[string]string{
		"shared/to-private": filepath.Join(f.filesDir, "private"),
		"shared/to-outside": outside,
		"shared/to-sub":     filepath.Join(f.filesDir, "shared", "sub"),
		"shared/dangling":   filepath.Join(f.filesDir, "nowhere"),
	} {
		if err := os.Symlink(target, filepath.Join(f.filesDir, filepath.FromSlash(link))); err != nil {
			t.Fatal(err)
		}
	}
	f.grant(t, f.userID, "", "shared", accessutil.Write)
	access := f.load(t, accessutil.Principal{UserID: f.userID})

	for p, readable := range map[string]bool{
		"shared/sub/new.txt":       true,
		"shared/to-sub/new.txt":    true,
		"shared/to-private":        false,
		"shared/to-private/x.txt":  false,
		"shared/to-outside/x.txt":  false,
		"shared/dangling":          false,
		"shared/not-yet/deep/file": true,
	} {
		if got := access.Check("", p, accessutil.Write); got.Readable != readable || got.Allowed != readable {
			t.Errorf("Check(%q) = %+v, want readable=%v", p, got, readable)
		}
	}
}

func TestBreadcrumbsLeadToADeepShare(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "Family/Bob", accessutil.Read)
	access := f.load(t, accessutil.Principal{UserID: f.userID})

	if access.Check("", "Family", accessutil.Read).Readable {
		t.Error("the breadcrumb itself is readable")
	}
	type child struct{ path string }
	result := accessutil.VisibleChildren(accessutil.VisibleChildrenParams[child]{
		Access:   access,
		Children: []child{{"Family"}, {"Work"}, {"Family/Bob"}, {"Family/Alice"}},
		Locate:   func(c child) (string, string) { return "", c.path },
	})
	got := make([]string, 0, len(result.Children))
	for _, c := range result.Children {
		got = append(got, c.path)
	}
	if len(got) != 2 || got[0] != "Family" || got[1] != "Family/Bob" {
		t.Errorf("VisibleChildren = %v, want [Family Family/Bob]", got)
	}
}

func TestGrantOwnerIfNeeded(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	grant := func(access accessutil.Access, p string) bool {
		t.Helper()
		result, err := accessutil.GrantOwnerIfNeeded(accessutil.GrantOwnerIfNeededParams{
			Ctx: ctx, Database: f.database, Access: access, Path: p,
		})
		if err != nil {
			t.Fatalf("GrantOwnerIfNeeded(%q): %v", p, err)
		}
		return result.Granted
	}

	if grant(f.load(t, accessutil.System), "admin-upload.txt") || f.rowCount(t) != 0 {
		t.Fatalf("an admin upload wrote a row: %d rows", f.rowCount(t))
	}

	f.grant(t, f.userID, "", "mine", accessutil.Owner)
	f.grant(t, f.userID, "", "shared", accessutil.Write)
	access := f.load(t, accessutil.Principal{UserID: f.userID})
	if grant(access, "mine/photo.jpg") {
		t.Error("an upload into an owned folder wrote a row")
	}
	if !grant(access, "shared/photo.jpg/") {
		t.Error("an upload into a write share wrote no row")
	}
	if got := f.load(t, accessutil.Principal{UserID: f.userID}).Level("", "shared/photo.jpg"); got != accessutil.Owner {
		t.Errorf("Level after grant = %v, want owner", got)
	}
	if n := f.rowCount(t); n != 3 {
		t.Errorf("rows = %d, want 3", n)
	}
}

func TestIsHomeRoot(t *testing.T) {
	for _, tc := range []struct {
		serial, path string
		want         bool
	}{
		{"", "users/bob", true},
		{"", "/users/bob/", true},
		{"", "users/./bob", true},
		{"", "users", false},
		{"", "users/bob/notes.txt", false},
		{"", "users/bob/sub", false},
		{"", "bob", false},
		{"", "shared/users/bob", false},
		{"USB1", "users/bob", false},
	} {
		if got := accessutil.IsHomeRoot(tc.serial, tc.path); got != tc.want {
			t.Errorf("IsHomeRoot(%q, %q) = %v, want %v", tc.serial, tc.path, got, tc.want)
		}
	}
}

// The same cases as TestIsHomeRoot, under groups/, and the Dart mirror's
// isGroupRoot test uses them too.
func TestIsGroupRoot(t *testing.T) {
	for _, tc := range []struct {
		serial, path string
		want         bool
	}{
		{"", "groups/Family", true},
		{"", "/groups/Family/", true},
		{"", "groups/./Family", true},
		{"", "groups", false},
		{"", "groups/Family/notes.txt", false},
		{"", "groups/Family/sub", false},
		{"", "Family", false},
		{"", "shared/groups/Family", false},
		{"", "users/Family", false},
		{"USB1", "groups/Family", false},
	} {
		if got := accessutil.IsGroupRoot(tc.serial, tc.path); got != tc.want {
			t.Errorf("IsGroupRoot(%q, %q) = %v, want %v", tc.serial, tc.path, got, tc.want)
		}
	}
}

package grouputil_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func everyoneID(t *testing.T, database *db.DatabaseSqlc) int64 {
	t.Helper()
	var id int64
	if err := database.Db.QueryRow(`SELECT id FROM groups WHERE builtin = 1`).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

// filesDirs remembers each test database's files directory, so create and
// rename helpers agree on it without threading it through every call.
var filesDirs = map[*db.DatabaseSqlc]string{}

// filesDirFor is the files directory the groups of database live under.
func filesDirFor(t *testing.T, database *db.DatabaseSqlc) string {
	t.Helper()
	if dir, ok := filesDirs[database]; ok {
		return dir
	}
	dir := t.TempDir()
	filesDirs[database] = dir
	t.Cleanup(func() { delete(filesDirs, database) })
	return dir
}

// renameParams renames a group through a local files VFS over the test's
// files directory, as the server's files namespace does.
func renameParams(t *testing.T, database *db.DatabaseSqlc, groupID int64, name string) grouputil.RenameGroupParams {
	t.Helper()
	dir := filesDirFor(t, database)
	local, err := vfs.NewLocalVFS(dir, "files")
	if err != nil {
		t.Fatal(err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, local); err != nil {
		t.Fatal(err)
	}
	return grouputil.RenameGroupParams{
		Database: database, Registry: registry, EventBus: eventbus.New(),
		FilesDir: dir, GroupID: groupID, Name: name,
	}
}

func createParams(t *testing.T, database *db.DatabaseSqlc, name string) grouputil.CreateGroupParams {
	t.Helper()
	return grouputil.CreateGroupParams{Database: database, FilesDir: filesDirFor(t, database), Name: name}
}

func create(t *testing.T, database *db.DatabaseSqlc, name string) grouputil.Group {
	t.Helper()
	result, err := grouputil.CreateGroup(context.Background(), createParams(t, database, name))
	if err != nil {
		t.Fatalf("CreateGroup(%q): %v", name, err)
	}
	return result.Group
}

func TestCreateGroupValidatesTheName(t *testing.T) {
	database := dbtest.NewDB(t)
	for _, tc := range []struct {
		name string
		want string
		err  error
	}{
		{name: "  Family  ", want: "Family"},
		{name: strings.Repeat("é", 64), want: strings.Repeat("é", 64)},
		{name: "Book club"},
		{name: "", err: grouputil.ErrInvalidGroupName},
		{name: "   ", err: grouputil.ErrInvalidGroupName},
		{name: strings.Repeat("a", 65), err: grouputil.ErrInvalidGroupName},
		{name: "two\nlines", err: grouputil.ErrInvalidGroupName},
		{name: "tab\there", err: grouputil.ErrInvalidGroupName},
		{name: "bad \xff byte", err: grouputil.ErrInvalidGroupName},
		{name: "a/b", err: grouputil.ErrInvalidGroupName},
		{name: "../escape", err: grouputil.ErrInvalidGroupName},
		{name: `a\b`, err: grouputil.ErrInvalidGroupName},
		{name: ".", err: grouputil.ErrInvalidGroupName},
		{name: " .. ", err: grouputil.ErrInvalidGroupName},
		{name: "...", want: "..."},
	} {
		result, err := grouputil.CreateGroup(context.Background(), createParams(t, database, tc.name))
		if !errors.Is(err, tc.err) {
			t.Errorf("CreateGroup(%q) error = %v, want %v", tc.name, err, tc.err)
			continue
		}
		if tc.want != "" && result.Group.Name != tc.want {
			t.Errorf("CreateGroup(%q) name = %q, want %q", tc.name, result.Group.Name, tc.want)
		}
	}
}

func TestGroupNamesAreUniqueIgnoringCase(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	family := create(t, database, "Family")
	friends := create(t, database, "Friends")

	for _, name := range []string{"family", "FAMILY", "Everyone"} {
		if _, err := grouputil.CreateGroup(ctx, createParams(t, database, name)); !errors.Is(err, grouputil.ErrGroupNameTaken) {
			t.Errorf("CreateGroup(%q) = %v, want ErrGroupNameTaken", name, err)
		}
	}
	if _, err := grouputil.RenameGroup(ctx, renameParams(t, database, friends.ID, "fAmIlY")); !errors.Is(err, grouputil.ErrGroupNameTaken) {
		t.Errorf("rename onto another group's name = %v, want ErrGroupNameTaken", err)
	}
	renamed, err := grouputil.RenameGroup(ctx, renameParams(t, database, family.ID, "family"))
	if err != nil || renamed.Group.Name != "family" {
		t.Errorf("rename to its own name in another case = %+v, %v", renamed, err)
	}
}

func TestEveryoneCannotBeChanged(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	id := everyoneID(t, database)

	if _, err := grouputil.RenameGroup(ctx, renameParams(t, database, id, "all")); !errors.Is(err, grouputil.ErrBuiltinGroup) {
		t.Errorf("rename everyone = %v, want ErrBuiltinGroup", err)
	}
	if _, err := grouputil.DeleteGroup(ctx, grouputil.DeleteGroupParams{Database: database, GroupID: id}); !errors.Is(err, grouputil.ErrBuiltinGroup) {
		t.Errorf("delete everyone = %v, want ErrBuiltinGroup", err)
	}
	result, err := grouputil.ListGroups(ctx, grouputil.ListGroupsParams{Database: database})
	if err != nil || len(result.Groups) != 1 || result.Groups[0].Name != "everyone" || !result.Groups[0].Builtin || result.Groups[0].Members == nil {
		t.Errorf("ListGroups = %+v, %v; want everyone alone, builtin, with members []", result, err)
	}
}

func TestMissingGroupIsNotFound(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	if _, err := grouputil.RenameGroup(ctx, renameParams(t, database, 999, "x")); !errors.Is(err, grouputil.ErrGroupNotFound) {
		t.Errorf("rename = %v, want ErrGroupNotFound", err)
	}
	if _, err := grouputil.DeleteGroup(ctx, grouputil.DeleteGroupParams{Database: database, GroupID: 999}); !errors.Is(err, grouputil.ErrGroupNotFound) {
		t.Errorf("delete = %v, want ErrGroupNotFound", err)
	}
}

func TestDeleteGroupCascades(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	family := create(t, database, "Family")
	kept := create(t, database, "Kept")
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range []int64{family.ID, kept.ID} {
		if _, err := database.Db.Exec(`INSERT INTO group_members (group_id, user_id) VALUES (?, ?)`, id, user.ID); err != nil {
			t.Fatal(err)
		}
		if _, err := database.Db.Exec(`INSERT INTO path_access (rel_path, group_id, level) VALUES ('shared', ?, 'read')`, id); err != nil {
			t.Fatal(err)
		}
	}

	listed, err := grouputil.ListGroups(ctx, grouputil.ListGroupsParams{Database: database})
	if err != nil || len(listed.Groups) != 3 || len(listed.Groups[1].Members) != 1 || listed.Groups[1].Members[0] != (grouputil.Member{ID: user.ID, Username: "bob"}) {
		t.Fatalf("ListGroups = %+v, %v; want Family listing bob", listed, err)
	}
	if _, err := grouputil.DeleteGroup(ctx, grouputil.DeleteGroupParams{Database: database, GroupID: family.ID}); err != nil {
		t.Fatalf("DeleteGroup: %v", err)
	}
	// Kept keeps its share and the grant on its own folder.
	for table, want := range map[string]int{"group_members": 1, "path_access": 2, "groups": 2} {
		var n int
		if err := database.Db.QueryRow(`SELECT COUNT(*) FROM ` + table).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != want {
			t.Errorf("%s rows = %d, want %d", table, n, want)
		}
	}
}

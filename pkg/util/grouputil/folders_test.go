package grouputil_test

import (
	"context"
	"errors"
	"maps"
	"path"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// groupRows maps "<rel_path> <group_id>" to the level of every group row on
// the internal device.
func groupRows(t *testing.T, database *db.DatabaseSqlc) map[string]string {
	t.Helper()
	rows, err := database.Db.Query(`SELECT rel_path, group_id, level FROM path_access WHERE group_id IS NOT NULL AND device_serial = ''`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	got := map[string]string{}
	for rows.Next() {
		var rel, level string
		var id int64
		if err := rows.Scan(&rel, &id, &level); err != nil {
			t.Fatal(err)
		}
		got[rel+" "+itoa(id)] = level
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return got
}

func itoa(id int64) string { return strconv.FormatInt(id, 10) }

func isDir(t *testing.T, files vfs.VFS, rel string) bool {
	t.Helper()
	info, err := files.Stat(context.Background(), rel)
	return err == nil && info.IsDir
}

func exists(t *testing.T, files vfs.VFS, rel string) bool {
	t.Helper()
	_, err := files.Stat(context.Background(), rel)
	if err != nil && !errors.Is(err, vfs.ErrNotFound) {
		t.Fatal(err)
	}
	return err == nil
}

func writeFile(t *testing.T, files vfs.VFS, rel string) {
	t.Helper()
	if err := files.Write(context.Background(), rel, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
}

func mkdir(t *testing.T, files vfs.VFS, rel string) {
	t.Helper()
	if err := files.MkdirAll(context.Background(), rel); err != nil {
		t.Fatal(err)
	}
}

func TestCreateGroupMakesItsFolderAndOneGrant(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)

	result, err := grouputil.CreateGroup(context.Background(), createParams(t, database, " Family "))
	if err != nil {
		t.Fatal(err)
	}
	if result.FolderPath != "groups/Family" {
		t.Errorf("FolderPath = %q, want groups/Family", result.FolderPath)
	}
	if !isDir(t, files, "groups/Family") {
		t.Error("groups/Family was not made")
	}
	want := map[string]string{"groups/Family " + itoa(result.Group.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestCreateGroupAdoptsAnExistingFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	writeFile(t, files, "groups/Family/kept.txt")
	create(t, database, "Family")
	if !exists(t, files, "groups/Family/kept.txt") {
		t.Error("adopted folder lost its content")
	}
}

func TestCreateGroupRefusedLeavesNoFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	create(t, database, "Family")
	if _, err := grouputil.CreateGroup(context.Background(), createParams(t, database, "Friends")); err != nil {
		t.Fatal(err)
	}
	if _, err := grouputil.CreateGroup(context.Background(), createParams(t, database, "FRIENDS")); !errors.Is(err, grouputil.ErrGroupNameTaken) {
		t.Fatalf("duplicate = %v, want ErrGroupNameTaken", err)
	}
	if _, err := grouputil.CreateGroup(context.Background(), createParams(t, database, "../escape")); !errors.Is(err, grouputil.ErrInvalidGroupName) {
		t.Fatalf("traversal = %v, want ErrInvalidGroupName", err)
	}
	if exists(t, files, "escape") {
		t.Error("a traversal name made a folder outside groups/")
	}
}

func TestRenameGroupMovesItsFolderAndGrant(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	family := create(t, database, "Family")
	writeFile(t, files, "groups/Family/notes.txt")

	result, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "Household"))
	if err != nil {
		t.Fatal(err)
	}
	if result.Group.Name != "Household" || result.OldFolderPath != "groups/Family" || result.FolderPath != "groups/Household" {
		t.Errorf("result = %+v", result)
	}
	if !exists(t, files, "groups/Household/notes.txt") {
		t.Error("content did not move")
	}
	if isDir(t, files, "groups/Family") {
		t.Error("groups/Family is still there")
	}
	want := map[string]string{"groups/Household " + itoa(family.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestRenameGroupOnlyChangingCase(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	family := create(t, database, "Family")

	if _, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "family")); err != nil {
		t.Fatal(err)
	}
	entries, err := files.List(context.Background(), "groups", nil)
	if err != nil || len(entries) != 1 || entries[0].Name != "family" {
		t.Errorf("groups/ = %v, %v; want only family", entries, err)
	}
	want := map[string]string{"groups/family " + itoa(family.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

// caseInsensitiveFiles is a files namespace on a case-insensitive disk: a
// path finds an entry whose name differs only in case, as on macOS.
type caseInsensitiveFiles struct {
	*vfs.MemVFS
}

func (f caseInsensitiveFiles) Stat(ctx context.Context, rel string) (vfs.FileInfo, error) {
	info, err := f.MemVFS.Stat(ctx, rel)
	if !errors.Is(err, vfs.ErrNotFound) {
		return info, err
	}
	siblings, listErr := f.List(ctx, path.Dir(rel), nil)
	if listErr != nil {
		return vfs.FileInfo{}, err
	}
	for _, sibling := range siblings {
		if strings.EqualFold(sibling.Name, path.Base(rel)) {
			return sibling, nil
		}
	}
	return vfs.FileInfo{}, err
}

// TestRenameGroupOnlyChangingCaseOnACaseInsensitiveDisk checks a rename that
// only changes case is not refused for finding the group's own folder at the
// new name, which is what a case-insensitive disk answers.
func TestRenameGroupOnlyChangingCaseOnACaseInsensitiveDisk(t *testing.T) {
	database := dbtest.NewDB(t)
	files := caseInsensitiveFiles{vfs.NewMemVFS("files")}
	useFiles(t, database, files)
	family := create(t, database, "Family")
	if !exists(t, files, "groups/family") {
		t.Fatal("the fake disk is case-sensitive")
	}

	if _, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "family")); err != nil {
		t.Fatalf("a case-only rename was refused: %v", err)
	}
	entries, err := files.List(context.Background(), "groups", nil)
	if err != nil || len(entries) != 1 || entries[0].Name != "family" {
		t.Errorf("groups/ = %v, %v; want only family", entries, err)
	}
}

// TestRenameGroupOnlyChangingCaseOntoAnotherFolderIsRefused checks that on a
// case-sensitive disk a folder spelled like the new name in another case is
// someone else's, not the group's own.
func TestRenameGroupOnlyChangingCaseOntoAnotherFolderIsRefused(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	family := create(t, database, "Family")
	writeFile(t, files, "groups/family/theirs.txt")

	_, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "family"))
	if !errors.Is(err, grouputil.ErrGroupFolderTaken) {
		t.Fatalf("rename = %v, want ErrGroupFolderTaken", err)
	}
	if !isDir(t, files, "groups/Family") || !exists(t, files, "groups/family/theirs.txt") {
		t.Error("a refused rename moved a folder")
	}
}

func TestCreateGroupWithAFileInTheWayIsRefused(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	writeFile(t, files, "groups/Family")

	if _, err := grouputil.CreateGroup(context.Background(), createParams(t, database, "Family")); err == nil {
		t.Fatal("a file where the folder goes passed as the folder")
	}
	if isDir(t, files, "groups/Family") || !exists(t, files, "groups/Family") {
		t.Error("the file in the way was touched")
	}
	var groups int
	if err := database.Db.QueryRow(`SELECT COUNT(*) FROM groups WHERE name = 'Family'`).Scan(&groups); err != nil || groups != 0 {
		t.Errorf("groups named Family = %d, %v; want the creation rolled back", groups, err)
	}
}

func TestRenameGroupOntoAnotherFolderIsRefused(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	family := create(t, database, "Family")
	mkdir(t, files, "groups/Household")

	_, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "Household"))
	if !errors.Is(err, grouputil.ErrGroupFolderTaken) {
		t.Fatalf("rename = %v, want ErrGroupFolderTaken", err)
	}
	group, err := database.Queries.GetGroup(context.Background(), family.ID)
	if err != nil || group.Name != "Family" {
		t.Errorf("group after a refused rename = %+v, %v; want Family", group, err)
	}
	if !isDir(t, files, "groups/Family") {
		t.Error("groups/Family moved on a refused rename")
	}
}

func TestRenameGroupRecreatesAMissingFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	family := create(t, database, "Family")
	if err := files.Delete(context.Background(), "groups/Family", vfs.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}

	if _, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "Household")); err != nil {
		t.Fatal(err)
	}
	if !isDir(t, files, "groups/Household") {
		t.Error("groups/Household was not made")
	}
	want := map[string]string{"groups/Household " + itoa(family.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestDeleteGroupKeepsItsFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	family := create(t, database, "Family")
	writeFile(t, files, "groups/Family/notes.txt")

	if _, err := grouputil.DeleteGroup(context.Background(), grouputil.DeleteGroupParams{Database: database, GroupID: family.ID}); err != nil {
		t.Fatal(err)
	}
	if !exists(t, files, "groups/Family/notes.txt") {
		t.Error("the folder's content went with the group")
	}
	if got := groupRows(t, database); len(got) != 0 {
		t.Errorf("rows = %v, want the grant gone", got)
	}
}

func TestRepairGroupFolders(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	files := vfs.NewMemVFS("files")
	everyone := everyoneID(t, database)
	// Groups made before groups had folders: no directory, no row. One of
	// them already has a hand-made folder, which is adopted.
	legacy, err := database.Queries.CreateGroup(ctx, "Family")
	if err != nil {
		t.Fatal(err)
	}
	handMade, err := database.Queries.CreateGroup(ctx, "Friends")
	if err != nil {
		t.Fatal(err)
	}
	mkdir(t, files, "groups/Friends")
	// A name from before names had to be one path segment gets nothing.
	if _, err := database.Queries.CreateGroup(ctx, "a/b"); err != nil {
		t.Fatal(err)
	}

	params := grouputil.RepairGroupFoldersParams{Database: database, Files: files}
	result, err := grouputil.RepairGroupFolders(ctx, params)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Repaired) != 3 {
		t.Errorf("Repaired = %v, want everyone, Family and Friends", result.Repaired)
	}
	for _, rel := range []string{"groups/everyone", "groups/Family", "groups/Friends"} {
		if !isDir(t, files, rel) {
			t.Errorf("%s was not made", rel)
		}
	}
	if isDir(t, files, "groups/a") {
		t.Error("a slashed name was given a folder")
	}
	want := map[string]string{
		"groups/everyone " + itoa(everyone):   "write",
		"groups/Family " + itoa(legacy.ID):    "write",
		"groups/Friends " + itoa(handMade.ID): "write",
	}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}

	again, err := grouputil.RepairGroupFolders(ctx, params)
	if err != nil || len(again.Repaired) != 0 {
		t.Errorf("second run = %+v, %v; want nothing repaired", again, err)
	}
}

// refuseGroupGrants makes every group grant fail, as a full disk would, so a
// creation fails after its folder is made.
func refuseGroupGrants(t *testing.T, database *db.DatabaseSqlc) {
	t.Helper()
	if _, err := database.Db.Exec(`CREATE TRIGGER refuse_group_grant BEFORE INSERT ON path_access
		WHEN NEW.group_id IS NOT NULL BEGIN SELECT RAISE(ABORT, 'disk full'); END`); err != nil {
		t.Fatal(err)
	}
}

func TestCreateGroupFailedGrantRemovesItsFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	refuseGroupGrants(t, database)

	if _, err := grouputil.CreateGroup(context.Background(), createParams(t, database, "Family")); err == nil {
		t.Fatal("CreateGroup succeeded though its grant was refused")
	}
	if isDir(t, files, "groups/Family") {
		t.Error("a failed creation left the folder it made")
	}
	if rows := groupRows(t, database); len(rows) != 0 {
		t.Errorf("rows = %v, want none", rows)
	}
	var groups int
	if err := database.Db.QueryRow(`SELECT COUNT(*) FROM groups WHERE name = 'Family'`).Scan(&groups); err != nil || groups != 0 {
		t.Errorf("groups named Family = %d, %v; want the creation rolled back", groups, err)
	}
}

func TestCreateGroupFailedGrantKeepsAnAdoptedFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	files := filesFor(t, database)
	writeFile(t, files, "groups/Family/photo.jpg")
	refuseGroupGrants(t, database)

	if _, err := grouputil.CreateGroup(context.Background(), createParams(t, database, "Family")); err == nil {
		t.Fatal("CreateGroup succeeded though its grant was refused")
	}
	if !exists(t, files, "groups/Family/photo.jpg") {
		t.Error("a failed creation touched a folder it adopted")
	}
}

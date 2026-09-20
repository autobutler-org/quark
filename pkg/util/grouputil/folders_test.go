package grouputil_test

import (
	"context"
	"errors"
	"maps"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
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

func isDir(t *testing.T, dir, rel string) bool {
	t.Helper()
	info, err := os.Stat(filepath.Join(dir, filepath.FromSlash(rel)))
	return err == nil && info.IsDir()
}

func TestCreateGroupMakesItsFolderAndOneGrant(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)

	result, err := grouputil.CreateGroup(context.Background(), createParams(t, database, " Family "))
	if err != nil {
		t.Fatal(err)
	}
	if result.FolderPath != "groups/Family" {
		t.Errorf("FolderPath = %q, want groups/Family", result.FolderPath)
	}
	if !isDir(t, dir, "groups/Family") {
		t.Error("groups/Family was not made")
	}
	want := map[string]string{"groups/Family " + itoa(result.Group.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestCreateGroupAdoptsAnExistingFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
	if err := os.MkdirAll(filepath.Join(dir, "groups", "Family"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "groups", "Family", "kept.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	create(t, database, "Family")
	if _, err := os.Stat(filepath.Join(dir, "groups", "Family", "kept.txt")); err != nil {
		t.Errorf("adopted folder lost its content: %v", err)
	}
}

func TestCreateGroupRefusedLeavesNoFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
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
	if _, err := os.Stat(filepath.Join(dir, "escape")); !os.IsNotExist(err) {
		t.Errorf("a traversal name made a folder outside groups/: %v", err)
	}
}

func TestRenameGroupMovesItsFolderAndGrant(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
	family := create(t, database, "Family")
	if err := os.WriteFile(filepath.Join(dir, "groups", "Family", "notes.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "Household"))
	if err != nil {
		t.Fatal(err)
	}
	if result.Group.Name != "Household" || result.OldFolderPath != "groups/Family" || result.FolderPath != "groups/Household" {
		t.Errorf("result = %+v", result)
	}
	if _, err := os.Stat(filepath.Join(dir, "groups", "Household", "notes.txt")); err != nil {
		t.Errorf("content did not move: %v", err)
	}
	if isDir(t, dir, "groups/Family") {
		t.Error("groups/Family is still there")
	}
	want := map[string]string{"groups/Household " + itoa(family.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestRenameGroupOnlyChangingCase(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
	family := create(t, database, "Family")

	if _, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "family")); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(filepath.Join(dir, "groups"))
	if err != nil || len(entries) != 1 || entries[0].Name() != "family" {
		t.Errorf("groups/ = %v, %v; want only family", entries, err)
	}
	want := map[string]string{"groups/family " + itoa(family.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestRenameGroupOntoAnotherFolderIsRefused(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
	family := create(t, database, "Family")
	if err := os.MkdirAll(filepath.Join(dir, "groups", "Household"), 0o755); err != nil {
		t.Fatal(err)
	}

	_, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "Household"))
	if !errors.Is(err, grouputil.ErrGroupFolderTaken) {
		t.Fatalf("rename = %v, want ErrGroupFolderTaken", err)
	}
	group, err := database.Queries.GetGroup(context.Background(), family.ID)
	if err != nil || group.Name != "Family" {
		t.Errorf("group after a refused rename = %+v, %v; want Family", group, err)
	}
	if !isDir(t, dir, "groups/Family") {
		t.Error("groups/Family moved on a refused rename")
	}
}

func TestRenameGroupRecreatesAMissingFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
	family := create(t, database, "Family")
	if err := os.Remove(filepath.Join(dir, "groups", "Family")); err != nil {
		t.Fatal(err)
	}

	if _, err := grouputil.RenameGroup(context.Background(), renameParams(t, database, family.ID, "Household")); err != nil {
		t.Fatal(err)
	}
	if !isDir(t, dir, "groups/Household") {
		t.Error("groups/Household was not made")
	}
	want := map[string]string{"groups/Household " + itoa(family.ID): "write"}
	if got := groupRows(t, database); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestDeleteGroupKeepsItsFolder(t *testing.T) {
	database := dbtest.NewDB(t)
	dir := filesDirFor(t, database)
	family := create(t, database, "Family")
	if err := os.WriteFile(filepath.Join(dir, "groups", "Family", "notes.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := grouputil.DeleteGroup(context.Background(), grouputil.DeleteGroupParams{Database: database, GroupID: family.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "groups", "Family", "notes.txt")); err != nil {
		t.Errorf("the folder's content went with the group: %v", err)
	}
	if got := groupRows(t, database); len(got) != 0 {
		t.Errorf("rows = %v, want the grant gone", got)
	}
}

func TestRepairGroupFolders(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	dir := t.TempDir()
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
	if err := os.MkdirAll(filepath.Join(dir, "groups", "Friends"), 0o755); err != nil {
		t.Fatal(err)
	}
	// A name from before names had to be one path segment gets nothing.
	if _, err := database.Queries.CreateGroup(ctx, "a/b"); err != nil {
		t.Fatal(err)
	}

	params := grouputil.RepairGroupFoldersParams{Database: database, FilesDir: dir}
	result, err := grouputil.RepairGroupFolders(ctx, params)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Repaired) != 3 {
		t.Errorf("Repaired = %v, want everyone, Family and Friends", result.Repaired)
	}
	for _, rel := range []string{"groups/everyone", "groups/Family", "groups/Friends"} {
		if !isDir(t, dir, rel) {
			t.Errorf("%s was not made", rel)
		}
	}
	if isDir(t, dir, "groups/a") {
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

package storageutil_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func writeFile(t *testing.T, filesDir, rel, content string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	require.NoError(t, os.MkdirAll(filepath.Dir(full), 0o700))
	require.NoError(t, os.WriteFile(full, []byte(content), 0o600))
}

func trash(t *testing.T, filesDir, rootDir string, paths ...string) {
	t.Helper()
	_, err := storageutil.TrashFilesImpl(storageutil.TrashFilesParams{RootDir: rootDir, FilePaths: paths}, filesDir)
	require.NoError(t, err)
}

func listTrash(t *testing.T, filesDir string) []storageutil.TrashItem {
	t.Helper()
	items, err := storageutil.ListTrashImpl(filesDir)
	require.NoError(t, err)
	return items
}

// trashNameFor finds the trash name of the item trashed from originalPath.
func trashNameFor(t *testing.T, filesDir, originalPath string) string {
	t.Helper()
	for _, item := range listTrash(t, filesDir) {
		if item.OriginalPath == originalPath {
			return item.TrashName
		}
	}
	t.Fatalf("no trash item for %s", originalPath)
	return ""
}

// refs addresses whole trashed items by name.
func refs(names ...string) []storageutil.TrashRef {
	out := make([]storageutil.TrashRef, len(names))
	for i, name := range names {
		out[i] = storageutil.TrashRef{TrashName: name}
	}
	return out
}

func TestTrashFilesImpl_MovesFileToTrash(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "docs/notes.txt", "hello")

	result, err := storageutil.TrashFilesImpl(storageutil.TrashFilesParams{
		RootDir:   "docs",
		FilePaths: []string{"notes.txt"},
	}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, "docs", result.RootDir)

	_, err = os.Stat(filepath.Join(filesDir, "docs", "notes.txt"))
	assert.True(t, os.IsNotExist(err), "original file should no longer exist")

	// One item + one metadata sidecar.
	entries, err := os.ReadDir(filepath.Join(filesDir, storageutil.TrashDir))
	require.NoError(t, err)
	assert.Len(t, entries, 2)

	items := listTrash(t, filesDir)
	require.Len(t, items, 1)
	assert.Equal(t, "docs/notes.txt", items[0].OriginalPath)
	assert.Equal(t, "notes.txt", items[0].Name)
	assert.Equal(t, int64(5), items[0].Size)
	assert.False(t, items[0].IsDir)
	assert.Equal(t, items[0].TrashedAt.AddDate(0, 0, storageutil.TrashRetentionDays), items[0].ExpiresAt)
}

// Two files sharing a base name, trashed within the same second, used to map
// to the same trash name, and the second rename overwrote the first.
func TestTrashFilesImpl_SameBaseNameDoesNotCollide(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a/x.txt", "from a")
	writeFile(t, filesDir, "b/x.txt", "from b")

	trash(t, filesDir, "", "a/x.txt", "b/x.txt")

	items := listTrash(t, filesDir)
	require.Len(t, items, 2)
	assert.NotEqual(t, items[0].TrashName, items[1].TrashName)
	for _, item := range items {
		assert.Equal(t, "x.txt", item.Name)
		assert.True(t, strings.HasSuffix(item.TrashName, "_x.txt"), item.TrashName)
	}
}

func TestTrashFilesImpl_MissingPathIsSkipped(t *testing.T) {
	filesDir := t.TempDir()
	trash(t, filesDir, "", "never-existed.txt")
	assert.Empty(t, listTrash(t, filesDir))
}

func TestTrashFilesImpl_RefusesTheTrashAndTheRoot(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a.txt", "x")
	trash(t, filesDir, "", "a.txt")

	for _, p := range []string{".trash", ".trash/" + trashNameFor(t, filesDir, "a.txt"), "", ".", "../escape"} {
		_, err := storageutil.TrashFilesImpl(storageutil.TrashFilesParams{FilePaths: []string{p}}, filesDir)
		assert.Error(t, err, "path %q", p)
	}
}

func TestTrashFilesImpl_LongNameFits(t *testing.T) {
	filesDir := t.TempDir()
	long := strings.Repeat("é", 120) + ".txt" // 244 bytes
	writeFile(t, filesDir, long, "x")

	trash(t, filesDir, "", long)

	items := listTrash(t, filesDir)
	require.Len(t, items, 1)
	assert.Equal(t, long, items[0].Name)
	assert.LessOrEqual(t, len(items[0].TrashName+".meta.json"), 255)
}

// ListTrash used to skip every entry ending in .json, hiding trashed JSON files.
func TestListTrashImpl_ListsTrashedJSONFiles(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "config.json", "{}")
	writeFile(t, filesDir, "x.meta.json", "{}")

	trash(t, filesDir, "", "config.json", "x.meta.json")

	items := listTrash(t, filesDir)
	require.Len(t, items, 2)
	names := []string{items[0].Name, items[1].Name}
	assert.ElementsMatch(t, []string{"config.json", "x.meta.json"}, names)
}

func TestListTrashImpl_ItemWithoutSidecar(t *testing.T) {
	filesDir := t.TempDir()
	trashRoot := filepath.Join(filesDir, storageutil.TrashDir)
	require.NoError(t, os.MkdirAll(filepath.Join(trashRoot, "20240102T030405Z_abcd_folder"), 0o700))
	writeFile(t, trashRoot, "20240102T030405Z_abcd_folder/inner.txt", "12345")
	// A .meta.json with no item beside it is not a sidecar; it is listed.
	writeFile(t, trashRoot, "orphan.meta.json", "{}")

	items := listTrash(t, filesDir)
	require.Len(t, items, 2)
	byName := map[string]storageutil.TrashItem{}
	for _, item := range items {
		byName[item.TrashName] = item
	}
	folder := byName["20240102T030405Z_abcd_folder"]
	assert.True(t, folder.IsDir)
	assert.Equal(t, int64(5), folder.Size)
	assert.Empty(t, folder.OriginalPath)
	assert.Equal(t, time.Date(2024, 1, 2, 3, 4, 5, 0, time.UTC), folder.TrashedAt)
	assert.Contains(t, byName, "orphan.meta.json")
}

func TestListTrashImpl_EmptyIsNotNil(t *testing.T) {
	items, err := storageutil.ListTrashImpl(t.TempDir())
	require.NoError(t, err)
	assert.NotNil(t, items)
	assert.Empty(t, items)
}

func TestRestoreTrashImpl_RestoresFileAndFolder(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "media/photo.jpg", "img")
	writeFile(t, filesDir, "album/one.jpg", "1")

	trash(t, filesDir, "media", "photo.jpg")
	trash(t, filesDir, "", "album")
	// The folder the file lived in is gone too; restore recreates it.
	require.NoError(t, os.Remove(filepath.Join(filesDir, "media")))

	result, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: refs(trashNameFor(t, filesDir, "media/photo.jpg"), trashNameFor(t, filesDir, "album")),
	}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, []storageutil.RestoredItem{
		{Path: "media/photo.jpg", IsDir: false},
		{Path: "album", IsDir: true},
	}, result.Restored)

	_, err = os.Stat(filepath.Join(filesDir, "media", "photo.jpg"))
	assert.NoError(t, err)
	_, err = os.Stat(filepath.Join(filesDir, "album", "one.jpg"))
	assert.NoError(t, err)

	// Items and sidecars are both gone.
	entries, err := os.ReadDir(filepath.Join(filesDir, storageutil.TrashDir))
	require.NoError(t, err)
	assert.Empty(t, entries)
}

func TestRestoreTrashImpl_OccupiedPathConflicts(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a.txt", "old")
	trash(t, filesDir, "", "a.txt")
	writeFile(t, filesDir, "a.txt", "new")
	name := trashNameFor(t, filesDir, "a.txt")

	_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{Items: refs(name)}, filesDir)
	require.ErrorIs(t, err, storageutil.ErrRestoreConflict)

	got, err := os.ReadFile(filepath.Join(filesDir, "a.txt"))
	require.NoError(t, err)
	assert.Equal(t, "new", string(got), "restore must never overwrite")
	assert.Len(t, listTrash(t, filesDir), 1)
}

func TestRestoreTrashImpl_SameTargetTwiceConflictsAndRestoresNothing(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a.txt", "first")
	trash(t, filesDir, "", "a.txt")
	writeFile(t, filesDir, "a.txt", "second")
	trash(t, filesDir, "", "a.txt")

	items := listTrash(t, filesDir)
	require.Len(t, items, 2)

	_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: refs(items[0].TrashName, items[1].TrashName),
	}, filesDir)
	require.ErrorIs(t, err, storageutil.ErrRestoreConflict)
	_, err = os.Stat(filepath.Join(filesDir, "a.txt"))
	assert.True(t, os.IsNotExist(err), "a conflicting batch restores nothing")
}

func TestRestoreTrashImpl_WithoutSidecarConflicts(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, ".trash/20240102T030405Z_abcd_lost.txt", "x")

	_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: refs("20240102T030405Z_abcd_lost.txt"),
	}, filesDir)
	require.ErrorIs(t, err, storageutil.ErrRestoreConflict)
}

func TestRestoreTrashImpl_SidecarPointingOutsideIsRefused(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, ".trash/evil", "x")
	for _, original := range []string{"../outside", ".trash/nested", ""} {
		meta, _ := json.Marshal(storageutil.TrashEntry{OriginalPath: original, TrashedAt: time.Now()})
		require.NoError(t, os.WriteFile(filepath.Join(filesDir, ".trash", "evil.meta.json"), meta, 0o600))

		_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{Items: refs("evil")}, filesDir)
		require.ErrorIs(t, err, storageutil.ErrRestoreConflict, "original %q", original)
	}
}

func TestTrashNames_AreValidated(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a.txt", "x")
	writeFile(t, filesDir, "secret.txt", "keep me")
	trash(t, filesDir, "", "a.txt")
	sidecar := trashNameFor(t, filesDir, "a.txt") + ".meta.json"

	cases := map[string]error{
		"":                 storageutil.ErrInvalidTrashName,
		".":                storageutil.ErrInvalidTrashName,
		"..":               storageutil.ErrInvalidTrashName,
		"../secret.txt":    storageutil.ErrInvalidTrashName,
		"sub/name":         storageutil.ErrInvalidTrashName,
		"does-not-exist":   storageutil.ErrTrashItemNotFound,
		sidecar:            storageutil.ErrTrashItemNotFound,
		"secret.txt":       storageutil.ErrTrashItemNotFound,
		"/etc/passwd":      storageutil.ErrInvalidTrashName,
		"..\\secret.txt\\": storageutil.ErrTrashItemNotFound, // backslash is an ordinary character here
	}
	for name, want := range cases {
		_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{Items: refs(name)}, filesDir)
		assert.ErrorIs(t, err, want, "restore %q", name)
		_, err = storageutil.DeleteTrashImpl(storageutil.DeleteTrashParams{Items: refs(name)}, filesDir)
		assert.ErrorIs(t, err, want, "delete %q", name)
	}

	_, err := os.Stat(filepath.Join(filesDir, "secret.txt"))
	assert.NoError(t, err)
	assert.Len(t, listTrash(t, filesDir), 1, "nothing was touched")
}

func TestDeleteTrashImpl_DeletesNamedItemsOnly(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a.txt", "a")
	writeFile(t, filesDir, "b.txt", "b")
	writeFile(t, filesDir, "c.txt", "c")
	trash(t, filesDir, "", "a.txt", "b.txt", "c.txt")

	result, err := storageutil.DeleteTrashImpl(storageutil.DeleteTrashParams{
		Items: refs(trashNameFor(t, filesDir, "a.txt"), trashNameFor(t, filesDir, "b.txt")),
	}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, 2, result.Deleted)

	items := listTrash(t, filesDir)
	require.Len(t, items, 1)
	assert.Equal(t, "c.txt", items[0].OriginalPath)
	entries, err := os.ReadDir(filepath.Join(filesDir, storageutil.TrashDir))
	require.NoError(t, err)
	assert.Len(t, entries, 2, "the deleted items' sidecars are gone too")
}

func TestEmptyTrashImpl_DeletesEverything(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a.txt", "a")
	writeFile(t, filesDir, "dir/b.txt", "b")
	trash(t, filesDir, "", "a.txt", "dir")

	deleted, err := storageutil.EmptyTrashImpl(filesDir)
	require.NoError(t, err)
	assert.Equal(t, 2, deleted)

	entries, err := os.ReadDir(filepath.Join(filesDir, storageutil.TrashDir))
	require.NoError(t, err)
	assert.Empty(t, entries)

	deleted, err = storageutil.EmptyTrashImpl(t.TempDir())
	require.NoError(t, err)
	assert.Zero(t, deleted, "a device with no trash yet is already empty")
}

func TestPurgeExpiredTrashImpl_DeletesOldItems(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "old.txt", "old")
	writeFile(t, filesDir, "new.txt", "new")
	trash(t, filesDir, "", "old.txt", "new.txt")

	// Backdate the old item's sidecar past the retention period.
	oldName := trashNameFor(t, filesDir, "old.txt")
	meta, _ := json.Marshal(storageutil.TrashEntry{
		OriginalPath: "old.txt",
		TrashedAt:    time.Now().UTC().AddDate(0, 0, -(storageutil.TrashRetentionDays + 1)),
	})
	require.NoError(t, os.WriteFile(filepath.Join(filesDir, storageutil.TrashDir, oldName+".meta.json"), meta, 0o600))

	// A sidecar-less item falls back to its trash-name stamp, not its mtime.
	stamped := filepath.Join(filesDir, storageutil.TrashDir, "20200101T000000Z_abcd_ancient.txt")
	require.NoError(t, os.WriteFile(stamped, []byte("x"), 0o600))
	recentMtimeButOldStamp := time.Now()
	require.NoError(t, os.Chtimes(stamped, recentMtimeButOldStamp, recentMtimeButOldStamp))

	purged, err := storageutil.PurgeExpiredTrashImpl(filesDir, time.Now().UTC())
	require.NoError(t, err)
	assert.Equal(t, 2, purged)

	items := listTrash(t, filesDir)
	require.Len(t, items, 1)
	assert.Equal(t, "new.txt", items[0].OriginalPath)
	_, err = os.Stat(filepath.Join(filesDir, storageutil.TrashDir, oldName+".meta.json"))
	assert.True(t, os.IsNotExist(err), "the purged item's sidecar is gone")
}

func TestIsTrashPath(t *testing.T) {
	assert.True(t, storageutil.IsTrashPath(".trash"))
	assert.True(t, storageutil.IsTrashPath(".trash/x"))
	assert.True(t, storageutil.IsTrashPath("./.trash/x/"))
	assert.False(t, storageutil.IsTrashPath(".trashy"))
	assert.False(t, storageutil.IsTrashPath("docs/.trash"))
}

// trashAlbum trashes a folder with a file at its root and one in a subfolder,
// returning its trash name.
func trashAlbum(t *testing.T, filesDir string) string {
	t.Helper()
	writeFile(t, filesDir, "pics/album/cover.jpg", "cover")
	writeFile(t, filesDir, "pics/album/2024/one.jpg", "1")
	writeFile(t, filesDir, "pics/album/2024/two.jpg", "22")
	trash(t, filesDir, "pics", "album")
	return trashNameFor(t, filesDir, "pics/album")
}

func TestListTrashContentsImpl_RootAndSubfolder(t *testing.T) {
	filesDir := t.TempDir()
	name := trashAlbum(t, filesDir)
	expires := listTrash(t, filesDir)[0].ExpiresAt

	root, err := storageutil.ListTrashContentsImpl(storageutil.ListTrashContentsParams{TrashName: name}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, "pics/album", root.OriginalPath)
	assert.Equal(t, expires, root.ExpiresAt)
	require.Len(t, root.Items, 2)
	assert.Equal(t, "2024", root.Items[0].Name)
	assert.Equal(t, "2024", root.Items[0].Path)
	assert.True(t, root.Items[0].IsDir)
	assert.Equal(t, int64(3), root.Items[0].Size, "a folder's size sums its files")
	assert.Equal(t, "cover.jpg", root.Items[1].Path)
	assert.Equal(t, int64(5), root.Items[1].Size)
	assert.False(t, root.Items[1].ModifiedAt.IsZero())

	sub, err := storageutil.ListTrashContentsImpl(storageutil.ListTrashContentsParams{TrashName: name, Path: "2024"}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, "pics/album/2024", sub.OriginalPath)
	assert.Equal(t, expires, sub.ExpiresAt, "a nested folder expires with its trashed item")
	require.Len(t, sub.Items, 2)
	assert.Equal(t, "2024/one.jpg", sub.Items[0].Path)
	assert.Equal(t, "2024/two.jpg", sub.Items[1].Path)
}

func TestListTrashContentsImpl_Rejects(t *testing.T) {
	filesDir := t.TempDir()
	name := trashAlbum(t, filesDir)
	writeFile(t, filesDir, "secret/key.txt", "keep")
	writeFile(t, filesDir, "note.txt", "x")
	trash(t, filesDir, "", "note.txt")
	fileItem := trashNameFor(t, filesDir, "note.txt")
	// A symlink inside the trashed folder that leads out of it.
	require.NoError(t, os.Symlink(filepath.Join(filesDir, "secret"), filepath.Join(filesDir, storageutil.TrashDir, name, "escape")))

	cases := []struct {
		name, path string
		want       error
	}{
		{name, "..", storageutil.ErrInvalidTrashPath},
		{name, "2024/../../..", storageutil.ErrInvalidTrashPath},
		{name, "/etc", storageutil.ErrInvalidTrashPath},
		{name, "escape", storageutil.ErrNotATrashFolder},
		{name, "escape/inner", storageutil.ErrInvalidTrashPath},
		{name, "cover.jpg", storageutil.ErrNotATrashFolder},
		{name, "missing", storageutil.ErrTrashItemNotFound},
		{fileItem, "", storageutil.ErrNotATrashFolder},
		{fileItem, "x", storageutil.ErrTrashItemNotFound},
		{"unknown", "", storageutil.ErrTrashItemNotFound},
		{"../secret", "", storageutil.ErrInvalidTrashName},
	}
	for _, tc := range cases {
		_, err := storageutil.ListTrashContentsImpl(storageutil.ListTrashContentsParams{TrashName: tc.name, Path: tc.path}, filesDir)
		assert.ErrorIs(t, err, tc.want, "%s %q", tc.name, tc.path)
	}

	// Restore and delete refuse the same escape.
	escape := []storageutil.TrashRef{{TrashName: name, Path: "escape/key.txt"}}
	_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{Items: escape}, filesDir)
	assert.ErrorIs(t, err, storageutil.ErrInvalidTrashPath)
	_, err = storageutil.DeleteTrashImpl(storageutil.DeleteTrashParams{Items: escape}, filesDir)
	assert.ErrorIs(t, err, storageutil.ErrInvalidTrashPath)
	_, err = os.Stat(filepath.Join(filesDir, "secret", "key.txt"))
	assert.NoError(t, err, "nothing outside the trash was touched")
}

func TestRestoreTrashImpl_NestedItemRecreatesParents(t *testing.T) {
	filesDir := t.TempDir()
	name := trashAlbum(t, filesDir)
	require.NoError(t, os.Remove(filepath.Join(filesDir, "pics")))

	result, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: name, Path: "2024/one.jpg"}, {TrashName: name, Path: "cover.jpg"}},
	}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, []storageutil.RestoredItem{
		{Path: "pics/album/2024/one.jpg"},
		{Path: "pics/album/cover.jpg"},
	}, result.Restored)
	got, err := os.ReadFile(filepath.Join(filesDir, "pics", "album", "2024", "one.jpg"))
	require.NoError(t, err)
	assert.Equal(t, "1", string(got))

	// The trashed folder stays, with its sidecar and the rest of its contents.
	items := listTrash(t, filesDir)
	require.Len(t, items, 1)
	assert.Equal(t, "pics/album", items[0].OriginalPath)
	rest, err := storageutil.ListTrashContentsImpl(storageutil.ListTrashContentsParams{TrashName: name, Path: "2024"}, filesDir)
	require.NoError(t, err)
	require.Len(t, rest.Items, 1)
	assert.Equal(t, "2024/two.jpg", rest.Items[0].Path)

	// The rest of the folder can still go back, next to what already did.
	result, err = storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: name, Path: "2024/two.jpg"}},
	}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, "pics/album/2024/two.jpg", result.Restored[0].Path)
}

func TestRestoreTrashImpl_NestedConflicts(t *testing.T) {
	filesDir := t.TempDir()
	name := trashAlbum(t, filesDir)
	writeFile(t, filesDir, "pics/album/cover.jpg", "new cover")

	cases := map[string][]storageutil.TrashRef{
		"occupied":         {{TrashName: name, Path: "2024/one.jpg"}, {TrashName: name, Path: "cover.jpg"}},
		"same path twice":  {{TrashName: name, Path: "2024"}, {TrashName: name, Path: "2024/"}},
		"one inside other": {{TrashName: name, Path: "2024/one.jpg"}, {TrashName: name, Path: "2024"}},
		"whole and nested": {{TrashName: name}, {TrashName: name, Path: "2024"}},
	}
	for label, items := range cases {
		_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{Items: items}, filesDir)
		assert.ErrorIs(t, err, storageutil.ErrRestoreConflict, label)
	}
	_, err := os.Stat(filepath.Join(filesDir, "pics", "album", "2024"))
	assert.True(t, os.IsNotExist(err), "a conflicting batch restores nothing")

	// A file now where a parent folder was is a conflict, not a failed mkdir.
	require.NoError(t, os.RemoveAll(filepath.Join(filesDir, "pics")))
	writeFile(t, filesDir, "pics", "a file")
	_, err = storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: name, Path: "cover.jpg"}},
	}, filesDir)
	assert.ErrorIs(t, err, storageutil.ErrRestoreConflict)
}

func TestDeleteTrashImpl_NestedItem(t *testing.T) {
	filesDir := t.TempDir()
	name := trashAlbum(t, filesDir)

	result, err := storageutil.DeleteTrashImpl(storageutil.DeleteTrashParams{
		Items: []storageutil.TrashRef{{TrashName: name, Path: "2024"}},
	}, filesDir)
	require.NoError(t, err)
	assert.Equal(t, 1, result.Deleted)

	rest, err := storageutil.ListTrashContentsImpl(storageutil.ListTrashContentsParams{TrashName: name}, filesDir)
	require.NoError(t, err)
	require.Len(t, rest.Items, 1)
	assert.Equal(t, "cover.jpg", rest.Items[0].Path)
	assert.Equal(t, "pics/album", rest.OriginalPath, "the sidecar stays with the folder")
}

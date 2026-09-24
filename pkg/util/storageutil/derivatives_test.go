package storageutil_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Derivatives are plain files in a hidden sibling directory, so these tests
// plant them by hand rather than through derivativeutil.Store.
func plantDerivative(t *testing.T, source string) {
	t.Helper()
	p := derivativeutil.Path(source, derivativeutil.KindThumbnail)
	require.NoError(t, os.MkdirAll(filepath.Dir(p), 0o755))
	require.NoError(t, os.WriteFile(p, []byte("jpeg"), 0o600))
}

func hasDerivative(source string) bool {
	_, err := os.Stat(derivativeutil.Path(source, derivativeutil.KindThumbnail))
	return err == nil
}

func TestIsInternalNameReservesDerivativeDir(t *testing.T) {
	assert.True(t, storageutil.IsInternalName(derivativeutil.DirName))
}

func TestMoveFileCarriesDerivatives(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a/clip.mov", "x")
	plantDerivative(t, filepath.Join(filesDir, "a", "clip.mov"))

	_, err := storageutil.MoveFileImpl(storageutil.MoveFileParams{
		OldFilePath: "a/clip.mov", NewFilePath: "b/renamed.mov",
	}, nil, nil, filesDir)
	require.NoError(t, err)

	assert.True(t, hasDerivative(filepath.Join(filesDir, "b", "renamed.mov")))
	assert.False(t, hasDerivative(filepath.Join(filesDir, "a", "clip.mov")))
}

func TestMoveFileAcrossDevicesCarriesDerivatives(t *testing.T) {
	oldDir, newDir := t.TempDir(), t.TempDir()
	writeFile(t, oldDir, "clip.mov", "x")
	plantDerivative(t, filepath.Join(oldDir, "clip.mov"))

	_, err := storageutil.MoveFileImpl(storageutil.MoveFileParams{
		OldFilePath: "clip.mov", NewFilePath: "clip.mov", NewDeviceSerial: "usb",
	}, nil, &storageutil.ManagedDevice{FilesDir: newDir}, oldDir)
	require.NoError(t, err)

	assert.True(t, hasDerivative(filepath.Join(newDir, "clip.mov")))
	assert.False(t, hasDerivative(filepath.Join(oldDir, "clip.mov")))
}

func TestCopyFileCopiesDerivatives(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "clip.mov", "x")
	plantDerivative(t, filepath.Join(filesDir, "clip.mov"))

	result, err := storageutil.CopyFileImpl(storageutil.CopyFileParams{RelPath: "clip.mov"}, nil, filesDir)
	require.NoError(t, err)

	assert.True(t, hasDerivative(filepath.Join(filesDir, "clip.mov")))
	assert.True(t, hasDerivative(filepath.Join(filesDir, result.NewRelPath)))
}

func TestTrashAndRestoreCarryDerivatives(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "a/clip.mov", "x")
	source := filepath.Join(filesDir, "a", "clip.mov")
	plantDerivative(t, source)

	trash(t, filesDir, "", "a/clip.mov")
	assert.False(t, hasDerivative(source))
	items := listTrash(t, filesDir)
	require.Len(t, items, 1, "the derivative directory is not a trash item")
	assert.True(t, hasDerivative(filepath.Join(storageutil.TrashRoot(filesDir), items[0].TrashName)))

	_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: items[0].TrashName}},
	}, filesDir)
	require.NoError(t, err)
	assert.True(t, hasDerivative(source))
	_, err = os.Stat(filepath.Join(storageutil.TrashRoot(filesDir), derivativeutil.DirName))
	assert.True(t, os.IsNotExist(err), "the trash's derivative directory is gone once empty")
}

func TestRestoreFromTrashedFolderCarriesDerivatives(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "album/clip.mov", "x")
	source := filepath.Join(filesDir, "album", "clip.mov")
	plantDerivative(t, source)

	trash(t, filesDir, "", "album")
	name := trashNameFor(t, filesDir, "album")
	_, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: name, Path: "clip.mov"}},
	}, filesDir)
	require.NoError(t, err)
	assert.True(t, hasDerivative(source))
}

func TestDeleteTrashRemovesDerivatives(t *testing.T) {
	filesDir := t.TempDir()
	writeFile(t, filesDir, "clip.mov", "x")
	writeFile(t, filesDir, "other.mov", "x")
	plantDerivative(t, filepath.Join(filesDir, "clip.mov"))
	plantDerivative(t, filepath.Join(filesDir, "other.mov"))
	trash(t, filesDir, "", "clip.mov", "other.mov")
	trashRoot := storageutil.TrashRoot(filesDir)
	clip := trashNameFor(t, filesDir, "clip.mov")

	_, err := storageutil.DeleteTrashImpl(storageutil.DeleteTrashParams{
		Items: []storageutil.TrashRef{{TrashName: clip}},
	}, filesDir)
	require.NoError(t, err)
	assert.False(t, hasDerivative(filepath.Join(trashRoot, clip)))

	_, err = storageutil.EmptyTrashImpl(filesDir)
	require.NoError(t, err)
	entries, err := os.ReadDir(trashRoot)
	require.NoError(t, err)
	assert.Empty(t, entries, "emptying the trash leaves no derivatives behind")
}

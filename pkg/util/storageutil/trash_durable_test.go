package storageutil_test

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestTrashFilesImpl_SidecarIsWrittenWhole checks the sidecar recording an
// item's original location is a whole, private file with no temp beside it.
func TestTrashFilesImpl_SidecarIsWrittenWhole(t *testing.T) {
	filesDir := filepath.Join(t.TempDir(), "files")
	writeFile(t, filesDir, "docs/notes.txt", "hello")

	trash(t, filesDir, "", "docs/notes.txt")

	name := trashNameFor(t, filesDir, "docs/notes.txt")
	info, err := os.Stat(filepath.Join(storageutil.TrashRoot(filesDir), name+".meta.json"))
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm())
	assertNoWriteTemps(t, storageutil.TrashRoot(filesDir))
}

// TestTrashFilesImpl_FailedSidecarPutsTheItemBack stands in for a crash
// between flushing the sidecar and renaming it into place (#2611): the item
// goes back where it was, and the trash holds neither a sidecar nor its temp.
func TestTrashFilesImpl_FailedSidecarPutsTheItemBack(t *testing.T) {
	errCut := errors.New("power cut")
	storageutil.FailAtomicRenameForTesting(t, errCut)
	filesDir := filepath.Join(t.TempDir(), "files")
	writeFile(t, filesDir, "docs/notes.txt", "hello")

	_, err := storageutil.TrashFilesImpl(storageutil.TrashFilesParams{FilePaths: []string{"docs/notes.txt"}}, filesDir)

	require.ErrorIs(t, err, errCut)
	got, err := os.ReadFile(filepath.Join(filesDir, "docs", "notes.txt"))
	require.NoError(t, err)
	assert.Equal(t, "hello", string(got))
	entries, err := os.ReadDir(storageutil.TrashRoot(filesDir))
	require.NoError(t, err)
	assert.Empty(t, entries)
}

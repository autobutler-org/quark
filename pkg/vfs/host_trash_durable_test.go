package vfs

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHostTrash_SidecarIsWrittenWhole checks the sidecar recording an
// item's original location is a whole, private file with no temp beside it.
func TestHostTrash_SidecarIsWrittenWhole(t *testing.T) {
	filesDir := filepath.Join(t.TempDir(), "files")
	writeFile(t, filesDir, "docs/notes.txt", "hello")

	trash(t, filesDir, "", "docs/notes.txt")

	name := trashNameFor(t, filesDir, "docs/notes.txt")
	info, err := os.Stat(filepath.Join(storageutil.TrashRoot(filesDir), name+".meta.json"))
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm())
	assertNoWriteTemps(t, storageutil.TrashRoot(filesDir))
}

// TestHostTrash_FailedSidecarPutsTheItemBack stands in for a crash
// between flushing the sidecar and renaming it into place (#2611): the item
// goes back where it was, and the trash holds no sidecar.
func TestHostTrash_FailedSidecarPutsTheItemBack(t *testing.T) {
	errCut := errors.New("power cut")
	saved := writeTrashSidecar
	t.Cleanup(func() { writeTrashSidecar = saved })
	writeTrashSidecar = func(string, io.Reader, os.FileMode) error { return errCut }
	filesDir := filepath.Join(t.TempDir(), "files")
	writeFile(t, filesDir, "docs/notes.txt", "hello")

	_, err := hostTrash(filesDir, []string{"docs/notes.txt"}, TrashOptions{})

	require.ErrorIs(t, err, errCut)
	got, err := os.ReadFile(filepath.Join(filesDir, "docs", "notes.txt"))
	require.NoError(t, err)
	assert.Equal(t, "hello", string(got))
	entries, err := os.ReadDir(storageutil.TrashRoot(filesDir))
	require.NoError(t, err)
	assert.Empty(t, entries)
}

// assertNoWriteTemps fails when a write left its temp in dir.
func assertNoWriteTemps(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), storageutil.WriteTempPrefix) {
			t.Fatalf("temp %s left behind", e.Name())
		}
	}
}

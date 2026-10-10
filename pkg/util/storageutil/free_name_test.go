package storageutil

import (
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Copies of one file made at the same moment each get a name of their own
// (#2767). Picking a free name with a stat and then calling os.Create let two
// copies take the same name, the second truncating the first.
func TestCopyFileImpl_ConcurrentCopiesTakeDistinctNames(t *testing.T) {
	filesDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(filesDir, "a.txt"), []byte("hello"), 0o644))

	const workers = 16
	start := make(chan struct{})
	got := make([]string, workers)
	errs := make([]error, workers)
	var wg sync.WaitGroup
	for i := range workers {
		wg.Go(func() {
			<-start
			res, err := CopyFileImpl(CopyFileParams{RelPath: "a.txt"}, nil, filesDir)
			errs[i] = err
			if err == nil {
				got[i] = res.NewRelPath
			}
		})
	}
	close(start)
	wg.Wait()

	seen := map[string]bool{}
	for i := range workers {
		require.NoError(t, errs[i])
		assert.False(t, seen[got[i]], "two copies both took %s", got[i])
		seen[got[i]] = true
		data, err := os.ReadFile(filepath.Join(filesDir, got[i]))
		require.NoError(t, err)
		assert.Equal(t, "hello", string(data))
	}
}

func TestCreateFree_NeverOpensATakenName(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "a.txt")
	require.NoError(t, os.WriteFile(target, []byte("keep"), 0o644))

	f, err := createFree(target)
	require.NoError(t, err)
	require.NoError(t, f.Close())

	assert.Equal(t, filepath.Join(dir, "a_(1).txt"), f.Name())
	data, err := os.ReadFile(target)
	require.NoError(t, err)
	assert.Equal(t, "keep", string(data))
}

package storageutil

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// symlinkFixture builds a base directory with an outside directory next to it,
// so a test can plant links that stay in base and links that leave it.
func symlinkFixture(t *testing.T) (base, outside string) {
	t.Helper()
	root := t.TempDir()
	base = filepath.Join(root, "base")
	outside = filepath.Join(root, "outside")
	require.NoError(t, os.MkdirAll(filepath.Join(base, "docs"), 0o755))
	require.NoError(t, os.MkdirAll(outside, 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(base, "docs", "a.txt"), []byte("a"), 0o644))
	require.NoError(t, os.WriteFile(filepath.Join(outside, "secret.txt"), []byte("s"), 0o644))
	return base, outside
}

func TestSafeJoin_LexicalEscapeRefused(t *testing.T) {
	base, _ := symlinkFixture(t)
	_, err := SafeJoin(base, "../outside/secret.txt")
	assert.Error(t, err)
}

func TestSafeJoin_PlainPathsAllowed(t *testing.T) {
	base, _ := symlinkFixture(t)
	for _, rel := range []string{"", "docs", "docs/a.txt", "docs/new.txt", "new/deeper/file.txt", "docs/a.txt/child"} {
		got, err := SafeJoin(base, rel)
		require.NoError(t, err, rel)
		assert.Equal(t, filepath.Join(base, rel), got, rel)
	}
}

func TestSafeJoin_FileSymlinkEscapeRefused(t *testing.T) {
	base, outside := symlinkFixture(t)
	require.NoError(t, os.Symlink(filepath.Join(outside, "secret.txt"), filepath.Join(base, "link.txt")))

	_, err := SafeJoin(base, "link.txt")
	assert.Error(t, err)
}

func TestSafeJoin_DirSymlinkEscapeRefused(t *testing.T) {
	base, outside := symlinkFixture(t)
	require.NoError(t, os.Symlink(outside, filepath.Join(base, "out")))

	for _, rel := range []string{"out", "out/secret.txt", "out/not-yet-created.txt", "out/new/dir"} {
		_, err := SafeJoin(base, rel)
		assert.Error(t, err, rel)
	}
}

func TestSafeJoin_RelativeDirSymlinkEscapeRefused(t *testing.T) {
	base, _ := symlinkFixture(t)
	require.NoError(t, os.Symlink("../outside", filepath.Join(base, "docs", "up")))

	_, err := SafeJoin(base, "docs/up/secret.txt")
	assert.Error(t, err)
}

func TestSafeJoin_NestedSymlinkEscapeRefused(t *testing.T) {
	base, outside := symlinkFixture(t)
	// base/hop -> base/docs (inside), base/docs/out -> outside: the chain only
	// leaves base on its second link.
	require.NoError(t, os.Symlink(filepath.Join(base, "docs"), filepath.Join(base, "hop")))
	require.NoError(t, os.Symlink(outside, filepath.Join(base, "docs", "out")))

	_, err := SafeJoin(base, "hop/out/secret.txt")
	assert.Error(t, err)
}

func TestSafeJoin_DanglingSymlinkRefused(t *testing.T) {
	base, outside := symlinkFixture(t)
	// Writing through this link would create a file outside base.
	require.NoError(t, os.Symlink(filepath.Join(outside, "planted.txt"), filepath.Join(base, "dangling")))
	require.NoError(t, os.Symlink(filepath.Join(outside, "gone"), filepath.Join(base, "dangling-dir")))

	_, err := SafeJoin(base, "dangling")
	assert.Error(t, err)
	_, err = SafeJoin(base, "dangling-dir/file.txt")
	assert.Error(t, err)
}

// A folder upload sends many files into one new directory at once, so one
// request creates it while another is still checking it. A directory that
// appears mid-check is not a dangling link.
func TestSafeJoin_DirectoryCreatedMidCheckAllowed(t *testing.T) {
	base, _ := symlinkFixture(t)
	for round := range 200 {
		dir := fmt.Sprintf("new%d", round)
		var wg sync.WaitGroup
		errs := make([]error, 8)
		for i := range errs {
			wg.Add(1)
			go func() {
				defer wg.Done()
				if _, errs[i] = SafeJoin(base, dir, "deep", "file.txt"); errs[i] == nil {
					errs[i] = os.MkdirAll(filepath.Join(base, dir, "deep"), 0o755)
				}
			}()
		}
		wg.Wait()
		for _, err := range errs {
			require.NoError(t, err)
		}
	}
}

func TestSafeJoin_SymlinkInsideBaseAllowed(t *testing.T) {
	base, _ := symlinkFixture(t)
	require.NoError(t, os.Symlink(filepath.Join(base, "docs"), filepath.Join(base, "alias")))
	require.NoError(t, os.Symlink("a.txt", filepath.Join(base, "docs", "same.txt")))

	for _, rel := range []string{"alias", "alias/a.txt", "alias/new.txt", "docs/same.txt"} {
		got, err := SafeJoin(base, rel)
		require.NoError(t, err, rel)
		// The lexical path comes back, not the resolved one.
		assert.Equal(t, filepath.Join(base, rel), got, rel)
	}
}

func TestSafeJoin_SymlinkedBaseAllowed(t *testing.T) {
	base, _ := symlinkFixture(t)
	// The files directory itself reached through a link, as datalinks/ does.
	linked := filepath.Join(t.TempDir(), "linked-base")
	require.NoError(t, os.Symlink(base, linked))

	got, err := SafeJoin(linked, "docs/a.txt")
	require.NoError(t, err)
	assert.Equal(t, filepath.Join(linked, "docs", "a.txt"), got)
}

func TestSafeJoin_MissingBaseIsLexicalOnly(t *testing.T) {
	// A base that does not exist has nothing on disk to follow; the upload
	// session's sentinel root relies on this.
	got, err := SafeJoin("/upload-root-does-not-exist", "a/b.txt")
	require.NoError(t, err)
	assert.Equal(t, "/upload-root-does-not-exist/a/b.txt", got)

	_, err = SafeJoin("/upload-root-does-not-exist", "../etc/passwd")
	assert.Error(t, err)
}

func TestDownloadFileImpl_RefusesSymlinkEscape(t *testing.T) {
	base, outside := symlinkFixture(t)
	require.NoError(t, os.Symlink(outside, filepath.Join(base, "out")))

	_, err := DownloadFileImpl(DownloadFileParams{FilePath: "out/secret.txt"}, nil, base)
	assert.Error(t, err)

	res, err := DownloadFileImpl(DownloadFileParams{FilePath: "docs/a.txt"}, nil, base)
	require.NoError(t, err)
	assert.Equal(t, filepath.Join(base, "docs", "a.txt"), res.FullPath)
}

// Concurrent uploads into one new folder race to create it (#2767): one
// request finds notes/2024 missing, another's MkdirAll creates it, and the
// first then sees it exist. That is a directory that appeared, not a dangling
// link, and must not be refused as one. The fake resolver forces the
// interleaving: it reports the folder missing, then creates it.
func TestResolvePending_DirectoryCreatedMidWalk(t *testing.T) {
	base, _ := symlinkFixture(t)
	dir := filepath.Join(base, "notes", "2024")
	target := filepath.Join(dir, "file.txt")
	raced := false
	eval := func(p string) (string, error) {
		if p == dir && !raced {
			raced = true
			require.NoError(t, os.MkdirAll(dir, 0o755))
			return "", os.ErrNotExist
		}
		return filepath.EvalSymlinks(p)
	}

	got, ok := resolvePending(base, target, eval)

	require.True(t, ok, "a directory created mid-walk was refused")
	realBase, err := filepath.EvalSymlinks(base)
	require.NoError(t, err)
	assert.Equal(t, filepath.Join(realBase, "notes", "2024", "file.txt"), got)
}

func TestResolvePending_DanglingLinkStillRefused(t *testing.T) {
	base, outside := symlinkFixture(t)
	link := filepath.Join(base, "gone")
	require.NoError(t, os.Symlink(filepath.Join(outside, "missing"), link))

	_, ok := ResolvePending(base, filepath.Join(link, "file.txt"))
	assert.False(t, ok)
}

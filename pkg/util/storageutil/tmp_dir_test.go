package storageutil_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func TestClearTmpDirEmptiesTheDirAndKeepsIt(t *testing.T) {
	t.Parallel()

	dataDir := t.TempDir()
	tmpDir := filepath.Join(dataDir, "tmp")
	nested := filepath.Join(tmpDir, "upload-sessions")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(nested, "upload-1.part"), make([]byte, 1000), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "upload-2"), make([]byte, 24), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}
	// A sibling of tmp is not tmp's to clear.
	keep := filepath.Join(dataDir, "files", "keep.txt")
	if err := os.MkdirAll(filepath.Dir(keep), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(keep, []byte("mine"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}

	result, err := storageutil.ClearTmpDir(storageutil.ClearTmpDirParams{DataDir: dataDir})
	if err != nil {
		t.Fatalf("ClearTmpDir: %v", err)
	}
	if result.Removed != 2 || result.Bytes != 1024 {
		t.Errorf("result = %+v, want 2 entries and 1024 bytes", result)
	}
	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		t.Fatalf("tmp dir is gone: %v", err)
	}
	if len(entries) != 0 {
		t.Errorf("tmp dir still holds %d entries", len(entries))
	}
	if _, err := os.Stat(keep); err != nil {
		t.Errorf("a file outside tmp was touched: %v", err)
	}
}

func TestClearTmpDirWithoutATmpDirIsANoOp(t *testing.T) {
	t.Parallel()

	result, err := storageutil.ClearTmpDir(storageutil.ClearTmpDirParams{DataDir: t.TempDir()})
	if err != nil || result.Removed != 0 {
		t.Errorf("ClearTmpDir = %+v, %v; want nothing removed and no error", result, err)
	}
}

// A data dir that is unset, relative or the filesystem root would point the
// wipe at a tmp dir that is not Quark's — /tmp, or one under the working dir.
func TestClearTmpDirRefusesADataDirThatIsNotQuarks(t *testing.T) {
	t.Parallel()

	for _, dataDir := range []string{"", ".", "data", "/", "//"} {
		if _, err := storageutil.ClearTmpDir(storageutil.ClearTmpDirParams{DataDir: dataDir}); err == nil {
			t.Errorf("ClearTmpDir(%q) succeeded, want a refusal", dataDir)
		}
	}
}

// A tmp that is a symlink would have the wipe follow it somewhere else.
func TestClearTmpDirRefusesASymlinkedTmp(t *testing.T) {
	t.Parallel()

	dataDir := t.TempDir()
	elsewhere := t.TempDir()
	precious := filepath.Join(elsewhere, "precious.txt")
	if err := os.WriteFile(precious, []byte("keep"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if err := os.Symlink(elsewhere, filepath.Join(dataDir, "tmp")); err != nil {
		t.Fatalf("symlink: %v", err)
	}

	if _, err := storageutil.ClearTmpDir(storageutil.ClearTmpDirParams{DataDir: dataDir}); err == nil {
		t.Error("ClearTmpDir followed a symlinked tmp dir")
	}
	if _, err := os.Stat(precious); err != nil {
		t.Errorf("the symlink target was emptied: %v", err)
	}
}

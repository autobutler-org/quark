package storageutil_test

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func TestWriteFileAtomicReplacesTheFileWhole(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	dst := filepath.Join(dir, "nested", "report.txt")
	if err := storageutil.WriteFileAtomic(dst, strings.NewReader("first")); err != nil {
		t.Fatalf("first write: %v", err)
	}
	if err := storageutil.WriteFileAtomic(dst, strings.NewReader("second")); err != nil {
		t.Fatalf("second write: %v", err)
	}

	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != "second" {
		t.Fatalf("content = %q, want %q", got, "second")
	}
	info, err := os.Stat(dst)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o644 {
		t.Fatalf("mode = %o, want 644", perm)
	}
	assertNoWriteTemps(t, filepath.Dir(dst))
}

func TestWriteFileAtomicLeavesTheOldFileOnAFailedWrite(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	dst := filepath.Join(dir, "photo.jpg")
	if err := os.WriteFile(dst, []byte("intact"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}

	errCut := errors.New("connection cut")
	r := io.MultiReader(strings.NewReader("half a photo"), errReader{errCut})
	if err := storageutil.WriteFileAtomic(dst, r); !errors.Is(err, errCut) {
		t.Fatalf("err = %v, want %v", err, errCut)
	}

	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != "intact" {
		t.Fatalf("content = %q, want the old file untouched", got)
	}
	assertNoWriteTemps(t, dir)
}

func TestSyncFileAndSyncDir(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	file := filepath.Join(dir, "a.txt")
	if err := os.WriteFile(file, []byte("a"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if err := storageutil.SyncFile(file); err != nil {
		t.Fatalf("SyncFile: %v", err)
	}
	if err := storageutil.SyncDir(dir); err != nil {
		t.Fatalf("SyncDir: %v", err)
	}
	if err := storageutil.SyncFile(filepath.Join(dir, "missing")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("SyncFile on a missing file = %v, want ErrNotExist", err)
	}
	if err := storageutil.SyncDir(filepath.Join(dir, "missing")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("SyncDir on a missing dir = %v, want ErrNotExist", err)
	}
}

type errReader struct{ err error }

func (r errReader) Read([]byte) (int, error) { return 0, r.err }

func assertNoWriteTemps(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), storageutil.WriteTempPrefix) {
			t.Fatalf("temp %s left behind", e.Name())
		}
	}
}

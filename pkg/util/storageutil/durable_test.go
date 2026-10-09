package storageutil_test

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync"
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

func TestWriteFileAtomicPermKeepsAPrivateFilePrivate(t *testing.T) {
	t.Parallel()

	dst := filepath.Join(t.TempDir(), "settings.json")
	if err := storageutil.WriteFileAtomicPerm(dst, strings.NewReader("{}"), 0o600); err != nil {
		t.Fatalf("write: %v", err)
	}

	info, err := os.Stat(dst)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Fatalf("mode = %o, want 600", perm)
	}
}

// TestWriteFileAtomicLeavesTheOldFileWhenAStepFails stands in for a crash at
// each step after the bytes are written: the real name keeps the old file
// whole, and the temp is cleaned up.
func TestWriteFileAtomicLeavesTheOldFileWhenAStepFails(t *testing.T) {
	errCut := errors.New("power cut")
	for name, fail := range map[string]func(*testing.T, error){
		"sync":   storageutil.FailAtomicSyncForTesting,
		"rename": storageutil.FailAtomicRenameForTesting,
	} {
		t.Run(name, func(t *testing.T) {
			fail(t, errCut)
			dir := t.TempDir()
			dst := filepath.Join(dir, "settings.json")
			if err := os.WriteFile(dst, []byte("intact"), 0o600); err != nil {
				t.Fatalf("seed: %v", err)
			}

			if err := storageutil.WriteFileAtomicPerm(dst, strings.NewReader("new"), 0o600); !errors.Is(err, errCut) {
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
		})
	}
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

// An exclusive write refuses a taken name and leaves what is there alone.
func TestWriteFileAtomicExclusiveRefusesATakenName(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	dst := filepath.Join(dir, "photo.jpg")
	if err := storageutil.WriteFileAtomicExclusive(dst, strings.NewReader("first")); err != nil {
		t.Fatalf("first write: %v", err)
	}
	if err := storageutil.WriteFileAtomicExclusive(dst, strings.NewReader("second")); !errors.Is(err, fs.ErrExist) {
		t.Fatalf("second write: err = %v, want fs.ErrExist", err)
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(got) != "first" {
		t.Fatalf("content = %q, want the first write untouched", got)
	}
	assertNoWriteTemps(t, dir)
}

// Of many writers racing for one name, exactly one wins, with or without hard
// links. A stat before the rename let several through (#2640).
func TestWriteFileAtomicExclusiveOneRacerWins(t *testing.T) {
	for _, tc := range []struct {
		name  string
		setup func(*testing.T)
	}{
		{"hard links", func(*testing.T) {}},
		{"no hard links", storageutil.NoHardLinksForTesting},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tc.setup(t)
			dir := t.TempDir()
			dst := filepath.Join(dir, "upload.bin")

			const racers = 16
			errs := make(chan error, racers)
			var wg sync.WaitGroup
			for i := range racers {
				wg.Add(1)
				go func() {
					defer wg.Done()
					errs <- storageutil.WriteFileAtomicExclusive(dst, strings.NewReader(fmt.Sprintf("racer %d", i)))
				}()
			}
			wg.Wait()
			close(errs)

			wins := 0
			for err := range errs {
				switch {
				case err == nil:
					wins++
				case !errors.Is(err, fs.ErrExist):
					t.Errorf("a losing racer got %v, want fs.ErrExist", err)
				}
			}
			if wins != 1 {
				t.Fatalf("%d racers won, want exactly 1", wins)
			}
			got, err := os.ReadFile(dst)
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			if !strings.HasPrefix(string(got), "racer ") {
				t.Fatalf("content = %q, want one racer's whole write", got)
			}
			assertNoWriteTemps(t, dir)
		})
	}
}

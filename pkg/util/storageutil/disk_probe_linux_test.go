package storageutil

import (
	"io"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"unsafe"

	"golang.org/x/sys/unix"
)

// residentPages counts the pages of the file at path held in the page cache.
func residentPages(t *testing.T, path string) int {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer f.Close()
	mapped, err := unix.Mmap(int(f.Fd()), 0, probeSizeBytes, unix.PROT_READ, unix.MAP_SHARED)
	if err != nil {
		t.Fatalf("mmap: %v", err)
	}
	defer unix.Munmap(mapped) //nolint:errcheck // test cleanup
	vec := make([]byte, (probeSizeBytes+os.Getpagesize()-1)/os.Getpagesize())
	if _, _, errno := syscall.Syscall(
		syscall.SYS_MINCORE,
		uintptr(unsafe.Pointer(&mapped[0])),
		uintptr(len(mapped)),
		uintptr(unsafe.Pointer(&vec[0])),
	); errno != 0 {
		t.Fatalf("resident page lookup: %v", errno)
	}
	resident := 0
	for _, page := range vec {
		resident += int(page & 1)
	}
	return resident
}

// #2467: the probe read back the file it had just written, so the page cache
// answered and the figures measured memory, not the disk.
func TestOpenProbeFile_ReadsAreNotServedFromThePageCache(t *testing.T) {
	// Beside the test, not t.TempDir(): /tmp is often a tmpfs, whose pages are
	// the file itself and cannot be evicted.
	dir, err := os.MkdirTemp(".", ".probe-test-")
	if err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	var stat unix.Statfs_t
	if err := unix.Statfs(dir, &stat); err != nil {
		t.Fatalf("statfs: %v", err)
	}
	if stat.Type == unix.TMPFS_MAGIC {
		t.Skip("the test directory is on a tmpfs")
	}

	path := filepath.Join(dir, "probe")
	if err := writeProbeFile(path); err != nil {
		t.Fatalf("writeProbeFile: %v", err)
	}
	// A full read puts every page in the cache, as the sequential pass does
	// before the random reads.
	warm, err := os.Open(path)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if _, err := io.Copy(io.Discard, warm); err != nil {
		t.Fatalf("read: %v", err)
	}
	warm.Close()
	if residentPages(t, path) == 0 {
		t.Skip("this filesystem does not keep read pages in the page cache")
	}

	f, err := openProbeFile(path)
	if err != nil {
		t.Fatalf("openProbeFile: %v", err)
	}
	defer f.Close()
	if resident := residentPages(t, path); resident != 0 {
		t.Errorf("%d pages still in the page cache after openProbeFile, want 0", resident)
	}
}

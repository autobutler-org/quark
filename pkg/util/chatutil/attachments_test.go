package chatutil

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func TestAttachmentPathRejectsTraversal(t *testing.T) {
	dir := t.TempDir()
	for _, id := range []string{"", "..", "../" + strings.Repeat("a", 61), strings.Repeat("A", 64), strings.Repeat("a", 63), strings.Repeat("g", 64)} {
		if _, err := AttachmentPath(dir, 1, id); !errors.Is(err, ErrInvalidAttachment) {
			t.Errorf("AttachmentPath(%q) = %v, want ErrInvalidAttachment", id, err)
		}
	}
	got, err := AttachmentPath(dir, 7, strings.Repeat("ab", 32))
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(dir, "chat-attachments", "7", strings.Repeat("ab", 32))
	if got != want {
		t.Errorf("AttachmentPath = %s, want %s", got, want)
	}
	if _, err := os.Stat(filepath.Join(dir, "chat-attachments")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("AttachmentPath touched the disk: %v", err)
	}
}

// TestWriteAttachmentWithoutHardLinks is #4050: on a data directory that
// refuses link(2), an Azure Files SMB share answering EOPNOTSUPP, an upload
// still lands, still private, and a second upload of the same id is still
// refused without touching the first.
func TestWriteAttachmentWithoutHardLinks(t *testing.T) {
	t.Cleanup(storageutil.FailHardLinksForTesting(syscall.EOPNOTSUPP))
	path, err := AttachmentPath(t.TempDir(), 1, strings.Repeat("ab", 32))
	if err != nil {
		t.Fatal(err)
	}
	n, err := writeAttachment(path, strings.NewReader("ciphertext"))
	if err != nil {
		t.Fatalf("write without hard links: %v", err)
	}
	if n != int64(len("ciphertext")) {
		t.Errorf("wrote %d bytes, want %d", n, len("ciphertext"))
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("attachment mode %o, want 600", perm)
	}
	if _, err := writeAttachment(path, strings.NewReader("other")); !errors.Is(err, ErrAttachmentExists) {
		t.Errorf("second write = %v, want ErrAttachmentExists", err)
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "ciphertext" {
		t.Errorf("attachment = %q, %v; want the first upload kept", got, err)
	}
}

// TestAttachmentServeStaysBounded is the acceptance check for serving
// ciphertext: a 1 GiB file through http.ServeContent stays inside a fixed
// heap bound, because the handler streams it instead of buffering it.
func TestAttachmentServeStaysBounded(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sparse.bin")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(1 << 30); err != nil {
		t.Skip("sparse file: " + err.Error())
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	file, err = os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := file.Seek(0, io.SeekStart); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Accept-Ranges", "bytes")
		http.ServeContent(w, r, "attachment.bin", time.Time{}, file)
	}))
	t.Cleanup(srv.Close)

	runtime.GC()
	var before runtime.MemStats
	runtime.ReadMemStats(&before)
	var peak atomic.Uint64
	peak.Store(before.HeapAlloc)
	stop := make(chan struct{})
	var stopped sync.WaitGroup
	stopped.Add(1)
	go func() {
		defer stopped.Done()
		ticker := time.NewTicker(10 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				var sample runtime.MemStats
				runtime.ReadMemStats(&sample)
				for {
					old := peak.Load()
					if sample.HeapAlloc <= old || peak.CompareAndSwap(old, sample.HeapAlloc) {
						break
					}
				}
			}
		}
	}()

	resp, err := http.Get(srv.URL)
	if err != nil {
		close(stop)
		stopped.Wait()
		t.Fatal(err)
	}
	n, err := io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	close(stop)
	stopped.Wait()
	if err != nil {
		t.Fatal(err)
	}
	if n != 1<<30 {
		t.Fatalf("served %d bytes, want 1 GiB", n)
	}
	const limit = 32 << 20
	if high := peak.Load(); high > before.HeapAlloc && high-before.HeapAlloc > limit {
		t.Fatalf("serving 1 GiB grew the heap by %d bytes, over %d", high-before.HeapAlloc, limit)
	}
}

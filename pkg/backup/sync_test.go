package backup

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func newTestSyncWorker(t *testing.T) (*SyncWorker, string, string) {
	t.Helper()
	srcDir := t.TempDir()
	dstDir := t.TempDir()
	bus := eventbus.New()

	w := NewSyncWorker(SyncWorkerParams{Bus: bus})
	w.resolveTarget = func(ctx context.Context) (string, error) { return dstDir, nil }
	w.resolveInternalDir = func() (string, error) { return srcDir, nil }

	return w, srcDir, dstDir
}

func writeTestFile(t *testing.T, dir, rel, content string) {
	t.Helper()
	full := filepath.Join(dir, rel)
	os.MkdirAll(filepath.Dir(full), 0755)
	if err := os.WriteFile(full, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func readTestFile(t *testing.T, dir, rel string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, rel))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestSyncWorker_SyncPath_CopiesFile(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	writeTestFile(t, srcDir, "photos/a.jpg", "photo-data")

	w.syncPath(context.Background(), "photos/a.jpg")

	got := readTestFile(t, dstDir, "photos/a.jpg")
	if got != "photo-data" {
		t.Errorf("expected 'photo-data', got %q", got)
	}
}

func TestSyncWorker_SyncPath_CreatesDirectory(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	os.MkdirAll(filepath.Join(srcDir, "docs/reports"), 0755)

	w.syncPath(context.Background(), "docs/reports")

	info, err := os.Stat(filepath.Join(dstDir, "docs/reports"))
	if err != nil {
		t.Fatal("directory should exist on target:", err)
	}
	if !info.IsDir() {
		t.Error("expected directory")
	}
}

func TestSyncWorker_MovePath(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "old/file.txt", "content")

	w.movePath(context.Background(), "old/file.txt", "new/file.txt")

	if _, err := os.Stat(filepath.Join(dstDir, "old/file.txt")); !os.IsNotExist(err) {
		t.Error("old path should not exist")
	}
	got := readTestFile(t, dstDir, "new/file.txt")
	if got != "content" {
		t.Errorf("expected 'content', got %q", got)
	}
}

func TestSyncWorker_QueueRetry(t *testing.T) {
	w, _, _ := newTestSyncWorker(t)

	w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: "a.txt"})
	w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: "b.txt"})

	if w.QueueLength() != 2 {
		t.Errorf("expected queue length 2, got %d", w.QueueLength())
	}
}

func TestSyncWorker_QueueMaxSize(t *testing.T) {
	w, _, _ := newTestSyncWorker(t)
	w.maxQueue = 3

	for i := 0; i < 5; i++ {
		w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: "file.txt"})
	}

	if w.QueueLength() != 3 {
		t.Errorf("expected queue capped at 3, got %d", w.QueueLength())
	}
}

func TestSyncWorker_DrainPending(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	writeTestFile(t, srcDir, "retry.txt", "retry-content")

	w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: "retry.txt"})

	n := w.DrainPending(context.Background())
	if n != 1 {
		t.Errorf("expected 1 drained, got %d", n)
	}
	if w.QueueLength() != 0 {
		t.Errorf("queue should be empty after drain, got %d", w.QueueLength())
	}

	got := readTestFile(t, dstDir, "retry.txt")
	if got != "retry-content" {
		t.Errorf("expected 'retry-content', got %q", got)
	}
}

func TestSyncWorker_HandleEvent_Upload(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	writeTestFile(t, srcDir, "doc.txt", "hello")

	w.handleEvent(context.Background(), eventbus.Event{
		Kind: eventbus.EventUpload,
		Path: "doc.txt",
	})

	got := readTestFile(t, dstDir, "doc.txt")
	if got != "hello" {
		t.Errorf("expected 'hello', got %q", got)
	}
}

func TestSyncWorker_HandleEvent_NewFolder(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	os.MkdirAll(filepath.Join(srcDir, "new-folder"), 0755)

	w.handleEvent(context.Background(), eventbus.Event{
		Kind: eventbus.EventNewFolder,
		Path: "new-folder",
	})

	info, err := os.Stat(filepath.Join(dstDir, "new-folder"))
	if err != nil {
		t.Fatal(err)
	}
	if !info.IsDir() {
		t.Error("expected directory")
	}
}

func TestSyncWorker_HandleEvent_Move(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "src.txt", "data")

	w.handleEvent(context.Background(), eventbus.Event{
		Kind:    eventbus.EventMove,
		Path:    "src.txt",
		NewPath: "dst.txt",
	})

	if _, err := os.Stat(filepath.Join(dstDir, "src.txt")); !os.IsNotExist(err) {
		t.Error("old path should not exist")
	}
	got := readTestFile(t, dstDir, "dst.txt")
	if got != "data" {
		t.Errorf("expected 'data', got %q", got)
	}
}

func TestSyncWorker_StartStop(t *testing.T) {
	bus := eventbus.New()
	w := NewSyncWorker(SyncWorkerParams{Bus: bus})

	srcDir := t.TempDir()
	dstDir := t.TempDir()
	w.resolveTarget = func(ctx context.Context) (string, error) { return dstDir, nil }
	w.resolveInternalDir = func() (string, error) { return srcDir, nil }

	writeTestFile(t, srcDir, "live.txt", "live-data")

	w.Start()
	w.Start() // idempotent

	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "live.txt"})

	deadline := time.After(2 * time.Second)
	for {
		select {
		case <-deadline:
			t.Fatal("timed out waiting for sync")
		default:
			if _, err := os.Stat(filepath.Join(dstDir, "live.txt")); err == nil {
				got := readTestFile(t, dstDir, "live.txt")
				if got != "live-data" {
					t.Errorf("expected 'live-data', got %q", got)
				}
				w.Stop()
				w.Stop() // idempotent
				return
			}
			time.Sleep(10 * time.Millisecond)
		}
	}
}

func TestSyncWorker_NoTarget_NoError(t *testing.T) {
	bus := eventbus.New()
	w := NewSyncWorker(SyncWorkerParams{Bus: bus})
	w.resolveTarget = func(ctx context.Context) (string, error) { return "", nil }
	w.resolveInternalDir = func() (string, error) { return t.TempDir(), nil }

	w.handleEvent(context.Background(), eventbus.Event{
		Kind: eventbus.EventUpload,
		Path: "whatever.txt",
	})
}

func TestSyncWorker_SyncPath_MissingSource_NoError(t *testing.T) {
	w, _, _ := newTestSyncWorker(t)

	w.syncPath(context.Background(), "nonexistent.txt")
}

func TestSyncWorker_SyncPath_FailedCopy_QueuesRetry(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)

	writeTestFile(t, srcDir, "file.txt", "data")
	// Make destination parent read-only so copy fails.
	os.MkdirAll(dstDir, 0755)
	os.Chmod(dstDir, 0555)
	defer os.Chmod(dstDir, 0755)

	w.syncPath(context.Background(), "file.txt")

	if w.QueueLength() != 1 {
		t.Errorf("expected retry queued, got queue length %d", w.QueueLength())
	}
}

func TestCopyFile(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src.bin")
	dst := filepath.Join(dir, "dst.bin")

	os.WriteFile(src, []byte("binary-content"), 0644)

	if err := copyFile(t.Context(), src, dst, nil); err != nil {
		t.Fatal(err)
	}

	data, _ := os.ReadFile(dst)
	if string(data) != "binary-content" {
		t.Errorf("expected 'binary-content', got %q", string(data))
	}
}

func TestCopyFile_MissingSource(t *testing.T) {
	dir := t.TempDir()
	err := copyFile(t.Context(), filepath.Join(dir, "nope"), filepath.Join(dir, "dst"), nil)
	if err == nil {
		t.Error("expected error for missing source")
	}
}

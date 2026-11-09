package backup

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const targetSerial = "target-drive"

// localNamespaces registers a disk-backed files namespace for each serial,
// keyed to its directory.
func localNamespaces(t *testing.T, dirs map[string]string) vfs.Registry {
	t.Helper()
	reg := vfs.NewRegistry()
	for serial, dir := range dirs {
		fsys, err := vfs.NewLocalVFS(dir, vfs.FilesNamespace(serial))
		if err != nil {
			t.Fatal(err)
		}
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	return reg
}

// newSyncWorker returns a worker mirroring registry's internal drive onto
// the drive with serial.
func newSyncWorker(registry vfs.Registry, serial string) *SyncWorker {
	w := NewSyncWorker(SyncWorkerParams{Bus: eventbus.New(), Registry: registry})
	w.targetSerial = func(context.Context) (string, bool, error) { return serial, serial != "", nil }
	return w
}

func queueLen(w *SyncWorker) int {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.pending)
}

func newTestSyncWorker(t *testing.T) (*SyncWorker, string, string) {
	t.Helper()
	srcDir := t.TempDir()
	dstDir := t.TempDir()
	w := newSyncWorker(localNamespaces(t, map[string]string{"": srcDir, targetSerial: dstDir}), targetSerial)
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

// waitForFile polls until rel exists under dir. It is bounded by the test
// binary's -timeout, not a fixed window: the worker copies one file at a time,
// and under -race on a loaded machine a burst of them takes several times as
// long as it does alone (#3532). The margin leaves room to name the missing
// file before the binary's own timeout panics.
func waitForFile(t *testing.T, dir, rel string) {
	t.Helper()
	deadline, bounded := t.Deadline()
	deadline = deadline.Add(-10 * time.Second)
	for {
		if _, err := os.Stat(filepath.Join(dir, rel)); err == nil {
			return
		}
		if bounded && time.Now().After(deadline) {
			t.Fatalf("%s never reached the target", rel)
		}
		time.Sleep(5 * time.Millisecond)
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

	if queueLen(w) != 2 {
		t.Errorf("expected queue length 2, got %d", queueLen(w))
	}
}

func TestSyncWorker_QueueMaxSize(t *testing.T) {
	w, _, _ := newTestSyncWorker(t)
	w.maxQueue = 3

	for i := 0; i < 5; i++ {
		w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: "file.txt"})
	}

	if queueLen(w) != 3 {
		t.Errorf("expected queue capped at 3, got %d", queueLen(w))
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
	if queueLen(w) != 0 {
		t.Errorf("queue should be empty after drain, got %d", queueLen(w))
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

// A move onto the internal drive carries no serial, so it reaches the worker
// as a rename of a path the target never held (#4030).
func TestSyncWorker_HandleEvent_MoveArrival(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	writeTestFile(t, srcDir, "arrived.txt", "data")

	w.handleEvent(context.Background(), eventbus.Event{
		Kind:    eventbus.EventMove,
		Path:    "arrived.txt",
		NewPath: "arrived.txt",
	})

	got := readTestFile(t, dstDir, "arrived.txt")
	if got != "data" {
		t.Errorf("expected 'data', got %q", got)
	}
}

func TestSyncWorker_StartStop(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	bus := w.bus

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
	w := newSyncWorker(localNamespaces(t, map[string]string{"": t.TempDir()}), "")

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

	if queueLen(w) != 1 {
		t.Errorf("expected retry queued, got queue length %d", queueLen(w))
	}
}

// A resync means the bus dropped events, so the worker copies whatever the
// target is missing or holds an older copy of, and deletes nothing (#2753).
func TestSyncWorker_ResyncReconcilesTarget(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	writeTestFile(t, srcDir, "missed/a.txt", "new")
	writeTestFile(t, srcDir, "stale.txt", "fresh contents")
	writeTestFile(t, dstDir, "stale.txt", "old")
	writeTestFile(t, dstDir, "only-in-target.txt", "keep")
	if err := os.MkdirAll(filepath.Join(srcDir, "empty"), 0755); err != nil {
		t.Fatal(err)
	}

	w.handleEvent(context.Background(), eventbus.Event{Kind: eventbus.EventResync})

	if got := readTestFile(t, dstDir, "missed/a.txt"); got != "new" {
		t.Errorf("missed/a.txt = %q, want %q", got, "new")
	}
	if got := readTestFile(t, dstDir, "stale.txt"); got != "fresh contents" {
		t.Errorf("stale.txt = %q, want %q", got, "fresh contents")
	}
	if got := readTestFile(t, dstDir, "only-in-target.txt"); got != "keep" {
		t.Errorf("only-in-target.txt = %q, want %q", got, "keep")
	}
	if info, err := os.Stat(filepath.Join(dstDir, "empty")); err != nil || !info.IsDir() {
		t.Errorf("empty folder not mirrored: %v", err)
	}
}

// Started worker, burst of uploads published faster than it copies: every
// file still reaches the target.
func TestSyncWorker_MirrorsEveryUploadInABurst(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	const n = 200
	for i := 0; i < n; i++ {
		writeTestFile(t, srcDir, fmt.Sprintf("burst/%d.txt", i), "x")
	}
	w.Start()
	defer w.Stop()
	for i := 0; i < n; i++ {
		w.bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: fmt.Sprintf("burst/%d.txt", i)})
	}

	for i := 0; i < n; i++ {
		waitForFile(t, dstDir, fmt.Sprintf("burst/%d.txt", i))
	}
}

// Built-in storage as the backup drive holds its runs in backups/. The mirror
// onto main storage never copies them, by resync, upload or move, and never
// moves away the backups/ folder main storage holds. A backups folder deeper
// down is the user's and is mirrored.
func TestSyncWorker_LeavesBackupsAlone(t *testing.T) {
	ctx := context.Background()
	w, srcDir, dstDir := newTestSyncWorker(t)
	run := filepath.Join(BackupsDir, "2026-11-07 21.57", "Photos (USB 90C82C65)")
	writeTestFile(t, srcDir, filepath.Join(run, "a.jpg"), "run")
	writeTestFile(t, srcDir, "photos/backups/keep.txt", "keep")
	writeTestFile(t, dstDir, filepath.Join(BackupsDir, "mine.txt"), "main storage's own")

	w.handleEvent(ctx, eventbus.Event{Kind: eventbus.EventResync})
	w.handleEvent(ctx, eventbus.Event{Kind: eventbus.EventUpload, Path: filepath.ToSlash(run)})
	w.handleEvent(ctx, eventbus.Event{Kind: eventbus.EventUpload, Path: ""})
	w.handleEvent(ctx, eventbus.Event{Kind: eventbus.EventMove, Path: "photos/backups/keep.txt", NewPath: BackupsDir + "/keep.txt"})

	if _, err := os.Stat(filepath.Join(dstDir, BackupsDir, "2026-11-07 21.57")); !os.IsNotExist(err) {
		t.Errorf("a backup run was mirrored onto main storage: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dstDir, BackupsDir, "keep.txt")); !os.IsNotExist(err) {
		t.Errorf("a move into backups/ was mirrored: %v", err)
	}
	if got := readTestFile(t, dstDir, "photos/backups/keep.txt"); got != "keep" {
		t.Errorf("photos/backups/keep.txt = %q, want it mirrored", got)
	}

	// Renaming built-in's backups/ never renames main storage's.
	w.handleEvent(ctx, eventbus.Event{Kind: eventbus.EventMove, Path: BackupsDir, NewPath: "old backups"})
	w.handleEvent(ctx, eventbus.Event{Kind: eventbus.EventMove, Path: BackupsDir + "/mine.txt", NewPath: "mine.txt"})
	if got := readTestFile(t, dstDir, filepath.Join(BackupsDir, "mine.txt")); got != "main storage's own" {
		t.Errorf("backups/mine.txt = %q, want main storage's backups/ left in place", got)
	}
}

package backup

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func newTestSyncWorker(t *testing.T) (*SyncWorker, string, string) {
	t.Helper()
	srcDir := t.TempDir()
	dstDir := t.TempDir()
	bus := eventbus.New()

	w := NewSyncWorker(SyncWorkerParams{Bus: bus})
	w.resolveTarget = func(ctx context.Context) (string, error) { return dstDir, nil }
	w.resolveInternalDir = func() (string, error) { return srcDir, nil }
	// By default, expose dstDir as a single managed USB device with no serial
	// (serial "") so that internal-source deletes propagate to it.
	w.getManagedDevices = func() ([]storageutil.ManagedDevice, error) {
		return []storageutil.ManagedDevice{
			{Device: storageutil.Device{IsInternal: false}, FilesDir: dstDir},
		}, nil
	}

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

func TestSyncWorker_DeletePath(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "photos/a.jpg", "photo-data")

	w.deletePath(context.Background(), "photos/a.jpg", "")

	if _, err := os.Stat(filepath.Join(dstDir, "photos/a.jpg")); !os.IsNotExist(err) {
		t.Error("file should have been deleted")
	}
}

func TestSyncWorker_DeletePath_Directory(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "photos/a.jpg", "data")
	writeTestFile(t, dstDir, "photos/b.jpg", "data")

	w.deletePath(context.Background(), "photos", "")

	if _, err := os.Stat(filepath.Join(dstDir, "photos")); !os.IsNotExist(err) {
		t.Error("directory should have been deleted")
	}
}

// TestSyncWorker_DeletePath_CrossDevice verifies that a delete event originating
// from a USB device (non-empty DeviceSerial) propagates to internal Files AND
// all other USB devices, but NOT to the source device.
func TestSyncWorker_DeletePath_CrossDevice(t *testing.T) {
	srcDir := t.TempDir()     // internal Files dir
	deviceADir := t.TempDir() // source USB device (device-A)
	deviceBDir := t.TempDir() // another USB device (device-B)
	bus := eventbus.New()

	w := NewSyncWorker(SyncWorkerParams{Bus: bus})
	w.resolveInternalDir = func() (string, error) { return srcDir, nil }
	w.resolveTarget = func(ctx context.Context) (string, error) { return deviceADir, nil } // unused for delete
	w.getManagedDevices = func() ([]storageutil.ManagedDevice, error) {
		return []storageutil.ManagedDevice{
			{
				Device:   storageutil.Device{IsInternal: false, UsbInfo: newMockUsbDevice("device-A")},
				FilesDir: deviceADir,
			},
			{
				Device:   storageutil.Device{IsInternal: false, UsbInfo: newMockUsbDevice("device-B")},
				FilesDir: deviceBDir,
			},
		}, nil
	}

	const relPath = "photos/test.jpg"
	writeTestFile(t, srcDir, relPath, "internal-data")
	writeTestFile(t, deviceADir, relPath, "device-a-data")
	writeTestFile(t, deviceBDir, relPath, "device-b-data")

	// Delete originates from device-A
	w.deletePath(context.Background(), relPath, "device-A")

	// Internal Files should be deleted (source was a USB device)
	if _, err := os.Stat(filepath.Join(srcDir, relPath)); !os.IsNotExist(err) {
		t.Error("file should have been deleted from internal Files")
	}
	// device-B should be deleted
	if _, err := os.Stat(filepath.Join(deviceBDir, relPath)); !os.IsNotExist(err) {
		t.Error("file should have been deleted from device-B")
	}
	// device-A (source) should NOT be deleted
	if _, err := os.Stat(filepath.Join(deviceADir, relPath)); os.IsNotExist(err) {
		t.Error("file should NOT have been deleted from source device-A")
	}
}

// TestSyncWorker_DeletePath_InternalSource verifies that a delete event from
// internal Files (empty DeviceSerial) propagates to all USB devices but does
// NOT attempt to re-delete from internal Files.
func TestSyncWorker_DeletePath_InternalSource(t *testing.T) {
	srcDir := t.TempDir()     // internal Files dir
	deviceADir := t.TempDir() // USB device (device-A)
	bus := eventbus.New()

	w := NewSyncWorker(SyncWorkerParams{Bus: bus})
	w.resolveInternalDir = func() (string, error) { return srcDir, nil }
	w.resolveTarget = func(ctx context.Context) (string, error) { return deviceADir, nil }
	w.getManagedDevices = func() ([]storageutil.ManagedDevice, error) {
		return []storageutil.ManagedDevice{
			{
				Device:   storageutil.Device{IsInternal: false, UsbInfo: newMockUsbDevice("device-A")},
				FilesDir: deviceADir,
			},
		}, nil
	}

	const relPath = "docs/report.pdf"
	writeTestFile(t, srcDir, relPath, "internal-data")
	writeTestFile(t, deviceADir, relPath, "device-a-data")

	// Delete originates from internal (empty serial)
	w.deletePath(context.Background(), relPath, "")

	// device-A should be deleted
	if _, err := os.Stat(filepath.Join(deviceADir, relPath)); !os.IsNotExist(err) {
		t.Error("file should have been deleted from device-A")
	}
	// Internal Files should NOT be touched (source was internal)
	if _, err := os.Stat(filepath.Join(srcDir, relPath)); os.IsNotExist(err) {
		t.Error("file should NOT have been deleted from internal Files (it was the source)")
	}
}

// mockUsbDevice is a minimal UsbDevice implementation for testing.
type mockUsbDevice struct {
	serial string
}

func newMockUsbDevice(serial string) storageutil.UsbDevice {
	return &mockUsbDevice{serial: serial}
}

func (m *mockUsbDevice) GetSerial() string                            { return m.serial }
func (m *mockUsbDevice) GetPath() string                              { return "" }
func (m *mockUsbDevice) GetVendorID() string                          { return "" }
func (m *mockUsbDevice) GetProductID() string                         { return "" }
func (m *mockUsbDevice) GetManufacturer() string                      { return "" }
func (m *mockUsbDevice) GetProduct() string                           { return "" }
func (m *mockUsbDevice) GetMountPath() string                         { return "" }
func (m *mockUsbDevice) BlockDevicePath() (string, bool)              { return "", false }
func (m *mockUsbDevice) IsStorageDevice() bool                        { return true }
func (m *mockUsbDevice) Partitions() ([]storageutil.Partition, error) { return nil, nil }

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

func TestSyncWorker_HandleEvent_Delete(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "gone.txt", "bye")

	w.handleEvent(context.Background(), eventbus.Event{
		Kind: eventbus.EventDelete,
		Path: "gone.txt",
	})

	if _, err := os.Stat(filepath.Join(dstDir, "gone.txt")); !os.IsNotExist(err) {
		t.Error("file should have been deleted")
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

	deadline := time.Now().Add(10 * time.Second)
	for i := 0; i < n; i++ {
		for {
			if _, err := os.Stat(filepath.Join(dstDir, fmt.Sprintf("burst/%d.txt", i))); err == nil {
				break
			}
			if time.Now().After(deadline) {
				t.Fatalf("burst/%d.txt never reached the target", i)
			}
			time.Sleep(5 * time.Millisecond)
		}
	}
}

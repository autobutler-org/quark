package backup

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func (w *SyncWorker) Start() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.running {
		return
	}

	ch, unsub := w.bus.Subscribe("sync-worker")
	w.unsub = unsub
	w.running = true

	ctx, cancel := context.WithCancel(context.Background())
	w.cancel = cancel

	go w.loop(ctx, ch)
}

func (w *SyncWorker) Stop() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if !w.running {
		return
	}
	w.cancel()
	w.unsub()
	w.running = false
}

func (w *SyncWorker) QueueLength() int {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.pending)
}

func (w *SyncWorker) loop(ctx context.Context, ch <-chan eventbus.Event) {
	for {
		select {
		case <-ctx.Done():
			return
		case evt, ok := <-ch:
			if !ok {
				return
			}
			w.handleEvent(ctx, evt)
		}
	}
}

func (w *SyncWorker) handleEvent(ctx context.Context, evt eventbus.Event) {
	switch evt.Kind {
	case eventbus.EventUpload, eventbus.EventNewFolder:
		w.syncPath(ctx, evt.Path)
	case eventbus.EventDelete:
		w.deletePath(ctx, evt.Path, evt.DeviceSerial)
	case eventbus.EventMove:
		w.movePath(ctx, evt.Path, evt.NewPath)
	case eventbus.EventDerivativesChanged:
		w.syncDerivatives(ctx, evt.Path)
	}
}

func (w *SyncWorker) defaultResolveTarget(ctx context.Context) (string, error) {
	roles, err := w.queries.GetAllDeviceRoles(ctx)
	if err != nil {
		return "", err
	}

	for _, r := range roles {
		if r.Role == "default-storage" {
			dev, err := w.storage.FindManagedDeviceBySerial(r.DeviceSerial)
			if err != nil {
				return "", err
			}
			if dev == nil {
				return "", nil
			}
			return dev.FilesDir, nil
		}
	}
	return "", nil
}

func (w *SyncWorker) defaultResolveInternalDir() (string, error) {
	return storageutil.GetFilesDir()
}

func (w *SyncWorker) defaultGetManagedDevices() ([]storageutil.ManagedDevice, error) {
	if w.storage == nil {
		return nil, nil
	}
	return w.storage.GetManagedDevices()
}

func (w *SyncWorker) syncPath(ctx context.Context, relPath string) {
	targetDir, err := w.resolveTarget(ctx)
	if err != nil || targetDir == "" {
		return
	}

	srcDir, err := w.resolveInternalDir()
	if err != nil {
		return
	}

	srcPath := filepath.Join(srcDir, relPath)
	dstPath := filepath.Join(targetDir, relPath)

	info, err := os.Stat(srcPath)
	if err != nil {
		return
	}

	if info.IsDir() {
		if err := os.MkdirAll(dstPath, 0755); err != nil {
			log.Printf("sync: mkdir %s: %v", relPath, err)
		}
		return
	}

	if err := os.MkdirAll(filepath.Dir(dstPath), 0755); err != nil {
		log.Printf("sync: mkdir parent %s: %v", relPath, err)
		return
	}

	if err := copyFile(ctx, srcPath, dstPath, w.ioSem); err != nil {
		log.Printf("sync: copy %s: %v", relPath, err)
		w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: relPath})
		return
	}
	// After the file, so the copies are newer than it and still count as
	// fresh.
	if err := derivativeutil.Copy(srcPath, dstPath); err != nil {
		log.Printf("sync: copy derivatives of %s: %v", relPath, err)
	}
}

// syncDerivatives copies a file's derivatives, attached after the file was
// synced, to the target.
func (w *SyncWorker) syncDerivatives(ctx context.Context, relPath string) {
	targetDir, err := w.resolveTarget(ctx)
	if err != nil || targetDir == "" {
		return
	}
	srcDir, err := w.resolveInternalDir()
	if err != nil {
		return
	}
	if err := derivativeutil.Copy(filepath.Join(srcDir, relPath), filepath.Join(targetDir, relPath)); err != nil {
		log.Printf("sync: copy derivatives of %s: %v", relPath, err)
	}
}

func (w *SyncWorker) deletePath(ctx context.Context, relPath string, sourceSerial string) {
	// 1. Delete from internal Files (if source was a USB device, not internal).
	if sourceSerial != "" {
		internalDir, err := w.resolveInternalDir()
		if err == nil && internalDir != "" {
			os.RemoveAll(filepath.Join(internalDir, relPath))
			_ = derivativeutil.Remove(filepath.Join(internalDir, relPath))
		}
	}

	// 2. Delete from all managed USB devices except the source device.
	managed, err := w.getManagedDevices()
	if err != nil {
		return
	}
	for _, dev := range managed {
		// Skip internal devices — already handled above (or is the source).
		if dev.IsInternal {
			continue
		}
		var devSerial string
		if dev.UsbInfo != nil {
			devSerial = dev.UsbInfo.GetSerial()
		}
		// Skip the source device (only relevant when source is a USB device).
		if sourceSerial != "" && devSerial == sourceSerial {
			continue
		}
		os.RemoveAll(filepath.Join(dev.FilesDir, relPath))
		_ = derivativeutil.Remove(filepath.Join(dev.FilesDir, relPath))
	}
}

func (w *SyncWorker) movePath(ctx context.Context, oldPath, newPath string) {
	targetDir, err := w.resolveTarget(ctx)
	if err != nil || targetDir == "" {
		return
	}

	oldDst := filepath.Join(targetDir, oldPath)
	newDst := filepath.Join(targetDir, newPath)

	// A failure here surfaces as the rename error just below.
	_ = os.MkdirAll(filepath.Dir(newDst), 0755)
	if err := os.Rename(oldDst, newDst); err != nil {
		log.Printf("sync: move %s → %s: %v", oldPath, newPath, err)
		return
	}
	if err := derivativeutil.Move(oldDst, newDst); err != nil {
		log.Printf("sync: move derivatives of %s: %v", oldPath, err)
	}
}

func (w *SyncWorker) queueRetry(evt eventbus.Event) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if len(w.pending) < w.maxQueue {
		w.pending = append(w.pending, evt)
	}
}

func (w *SyncWorker) DrainPending(ctx context.Context) int {
	w.mu.Lock()
	pending := w.pending
	w.pending = nil
	w.mu.Unlock()

	synced := 0
	for _, evt := range pending {
		w.handleEvent(ctx, evt)
		synced++
	}
	return synced
}

func copyFile(ctx context.Context, src, dst string, sem *iosemutil.Semaphore) error {
	// Acquire IO semaphore before reading/writing to yield to interactive requests.
	if sem != nil {
		if !sem.AcquireDefault(ctx) {
			return fmt.Errorf("sync: IO semaphore timeout for %s", src)
		}
		defer sem.Release()
	}

	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("open source: %w", err)
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("create dest: %w", err)
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		return fmt.Errorf("copy: %w", err)
	}
	return out.Close()
}

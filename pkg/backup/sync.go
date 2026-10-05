package backup

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"path/filepath"

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
	case eventbus.EventResync:
		w.reconcile(ctx)
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
	}
}

func (w *SyncWorker) deletePath(ctx context.Context, relPath string, sourceSerial string) {
	// 1. Delete from internal Files (if source was a USB device, not internal).
	if sourceSerial != "" {
		internalDir, err := w.resolveInternalDir()
		if err == nil && internalDir != "" {
			os.RemoveAll(filepath.Join(internalDir, relPath))
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
	}
}

// reconcile mirrors the internal Files tree onto the target after the bus
// dropped events (#2753): every folder is created and every file the target
// lacks, or holds a different-sized or older copy of, is copied. It deletes
// nothing: a file only the target holds may be a missed delete or may have
// been written to the device directly, and the two look the same from here.
func (w *SyncWorker) reconcile(ctx context.Context) {
	targetDir, err := w.resolveTarget(ctx)
	if err != nil || targetDir == "" {
		return
	}
	srcDir, err := w.resolveInternalDir()
	if err != nil {
		return
	}
	walkErr := filepath.WalkDir(srcDir, func(srcPath string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		relPath, err := filepath.Rel(srcDir, srcPath)
		if err != nil || relPath == "." {
			return nil
		}
		dstPath := filepath.Join(targetDir, relPath)
		if d.IsDir() {
			if err := os.MkdirAll(dstPath, 0755); err != nil {
				log.Printf("sync: reconcile mkdir %s: %v", relPath, err)
			}
			return nil
		}
		if !d.Type().IsRegular() || upToDate(srcPath, dstPath) {
			return nil
		}
		if err := copyFile(ctx, srcPath, dstPath, w.ioSem); err != nil {
			log.Printf("sync: reconcile copy %s: %v", relPath, err)
			w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: filepath.ToSlash(relPath)})
		}
		return nil
	})
	if walkErr != nil {
		log.Printf("sync: reconcile: %v", walkErr)
	}
}

// upToDate reports whether dst is the same size as src and no older.
func upToDate(src, dst string) bool {
	srcInfo, err := os.Stat(src)
	if err != nil {
		return true
	}
	dstInfo, err := os.Stat(dst)
	if err != nil {
		return false
	}
	return srcInfo.Size() == dstInfo.Size() && !srcInfo.ModTime().After(dstInfo.ModTime())
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

package backup

import (
	"context"
	"fmt"
	"io"
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
	// Live sync mirrors the internal drive onto the default-storage drive and
	// nothing else. An event from another drive names a path on that drive; the
	// same relative path anywhere else is an unrelated file (#2791).
	if evt.DeviceSerial != "" {
		return
	}
	// A delete is not mirrored. The user's delete moved the file into the
	// internal drive's Trash, where it can be restored; the mirror keeps its
	// copy rather than destroying a file nobody asked to delete (#2791).
	switch evt.Kind {
	case eventbus.EventUpload, eventbus.EventNewFolder:
		w.syncPath(ctx, evt.Path)
	case eventbus.EventMove:
		w.movePath(ctx, evt.Path, evt.NewPath)
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

func (w *SyncWorker) movePath(ctx context.Context, oldPath, newPath string) {
	targetDir, err := w.resolveTarget(ctx)
	if err != nil || targetDir == "" {
		return
	}

	oldDst := filepath.Join(targetDir, oldPath)
	newDst := filepath.Join(targetDir, newPath)

	// os.Rename replaces an existing file, and what sits at the new name on
	// the target may be a file the mirror never wrote.
	if _, err := os.Lstat(newDst); !os.IsNotExist(err) {
		log.Printf("sync: move %s → %s: destination exists on target, leaving both", oldPath, newPath)
		return
	}
	// A failure here surfaces as the rename error just below.
	_ = os.MkdirAll(filepath.Dir(newDst), 0755)
	if err := os.Rename(oldDst, newDst); err != nil {
		log.Printf("sync: move %s → %s: %v", oldPath, newPath, err)
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

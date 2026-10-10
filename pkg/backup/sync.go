package backup

import (
	"context"
	"errors"
	"fmt"
	"log"
	"path"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
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
	case eventbus.EventResync:
		w.reconcile(ctx)
	}
}

// defaultTargetSerial returns the serial of the default-storage drive, and
// false when no drive holds the role or the internal drive does.
func (w *SyncWorker) defaultTargetSerial(ctx context.Context) (string, bool, error) {
	roles, err := w.queries.GetAllDeviceRoles(ctx)
	if err != nil {
		return "", false, err
	}
	for _, r := range roles {
		if r.Role == "default-storage" {
			return r.DeviceSerial, r.DeviceSerial != "", nil
		}
	}
	return "", false, nil
}

// namespaces returns the internal drive's namespace and the default-storage
// drive's, the two live sync copies between. ok is false when there is
// nothing to mirror onto: no drive holds the role, or it is not attached.
func (w *SyncWorker) namespaces(ctx context.Context) (src, dst vfs.VFS, ok bool) {
	serial, found, err := w.targetSerial(ctx)
	if err != nil || !found {
		return nil, nil, false
	}
	dst, err = fileutil.FilesVFS(w.registry, serial)
	if err != nil {
		return nil, nil, false
	}
	src, err = fileutil.FilesVFS(w.registry, "")
	if err != nil {
		return nil, nil, false
	}
	return src, dst, true
}

// syncPath mirrors relPath onto the target. A folder is created there along
// with the files directly in it that the target lacks or holds an older copy
// of: an upload event names the folder it landed in, not the file (#2649).
func (w *SyncWorker) syncPath(ctx context.Context, relPath string) {
	src, dst, ok := w.namespaces(ctx)
	if !ok {
		return
	}
	info, err := src.Stat(ctx, relPath)
	if err != nil {
		return
	}
	w.mirror(ctx, src, dst, info)
	if !info.IsDir {
		return
	}
	entries, err := src.List(ctx, relPath, nil)
	if err != nil {
		log.Printf("sync: list %s: %v", relPath, err)
		return
	}
	for _, fi := range entries {
		if storageutil.IsInternalName(fi.Name) {
			continue
		}
		w.mirror(ctx, src, dst, fi)
	}
}

// mirror copies one entry of the internal drive onto the target: a folder is
// created, and a file is copied unless the target's copy is up to date. A
// failed copy is queued for a retry.
func (w *SyncWorker) mirror(ctx context.Context, src, dst vfs.VFS, fi vfs.FileInfo) {
	if fi.IsDir {
		if err := dst.MkdirAll(ctx, fi.Path); err != nil {
			log.Printf("sync: mkdir %s: %v", fi.Path, err)
		}
		return
	}
	if upToDate(ctx, fi, dst) {
		return
	}
	if err := copyFile(ctx, src, dst, fi.Path, w.ioSem); err != nil {
		log.Printf("sync: copy %s: %v", fi.Path, err)
		w.queueRetry(eventbus.Event{Kind: eventbus.EventUpload, Path: fi.Path})
	}
}

func (w *SyncWorker) movePath(ctx context.Context, oldPath, newPath string) {
	_, dst, ok := w.namespaces(ctx)
	if !ok {
		return
	}
	// A move replaces an existing file, and what sits at the new name on the
	// target may be a file the mirror never wrote.
	if _, err := dst.Stat(ctx, newPath); !errors.Is(err, vfs.ErrNotFound) {
		log.Printf("sync: move %s → %s: destination exists on target, leaving both", oldPath, newPath)
		return
	}
	if dir := path.Dir(newPath); dir != "." {
		// A failure here surfaces as the move error just below.
		_ = dst.MkdirAll(ctx, dir)
	}
	if err := dst.Move(ctx, oldPath, newPath); err != nil {
		log.Printf("sync: move %s → %s: %v", oldPath, newPath, err)
	}
}

// reconcile mirrors the internal Files tree onto the target after the bus
// dropped events (#2753): every folder is created and every file the target
// lacks, or holds a different-sized or older copy of, is copied. It deletes
// nothing: a file only the target holds may be a missed delete or may have
// been written to the device directly, and the two look the same from here.
func (w *SyncWorker) reconcile(ctx context.Context) {
	src, dst, ok := w.namespaces(ctx)
	if !ok {
		return
	}
	err := vfs.Walk(ctx, src, "", func(fi vfs.FileInfo) error {
		w.mirror(ctx, src, dst, fi)
		return nil
	})
	if err != nil {
		log.Printf("sync: reconcile: %v", err)
	}
}

// upToDate reports whether dst holds a copy of src that is the same size and
// no older.
func upToDate(ctx context.Context, src vfs.FileInfo, dst vfs.VFS) bool {
	dstInfo, err := dst.Stat(ctx, src.Path)
	if err != nil || dstInfo.IsDir {
		return false
	}
	return src.Size == dstInfo.Size && !src.ModTime.After(dstInfo.ModTime)
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

// copyFile copies relPath from src to the same path on dst. The copy goes
// through [vfs.CopyBetween], so the target never holds a half-written file
// under its real name.
func copyFile(ctx context.Context, src, dst vfs.VFS, relPath string, sem *iosemutil.Semaphore) error {
	// Acquire IO semaphore before reading/writing to yield to interactive requests.
	if sem != nil {
		if !sem.AcquireDefault(ctx) {
			return fmt.Errorf("sync: IO semaphore timeout for %s", relPath)
		}
		defer sem.Release()
	}
	return vfs.CopyBetween(ctx, src, relPath, dst, relPath, vfs.CopyOptions{})
}

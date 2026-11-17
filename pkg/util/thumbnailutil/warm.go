package thumbnailutil

import (
	"context"
	"errors"
	"log"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// warmQueueSize bounds the photos waiting for their grid tier. A caller with
// more waits for room: the backfill and the event watcher each run on a
// goroutine of their own, and the bus queues a watcher's events meanwhile.
const warmQueueSize = 1024

// warmYieldInterval is how long the warmer waits before it looks again at a
// semaphore whose free slots requests may need.
const warmYieldInterval = 100 * time.Millisecond

// NewWarmer returns a Warmer with an empty queue. Nothing is generated until
// [Warmer.Run] is running.
func NewWarmer(params WarmerParams) *Warmer {
	return &Warmer{
		params:  params,
		queue:   make(chan WarmItem, warmQueueSize),
		pending: map[WarmItem]bool{},
	}
}

// Warms reports whether a [Warmer] takes the file at name: a photo the device
// decodes itself. HEIC, video and 3D models are a client's to render
// ([NeedsClientRender]), a camera RAW needs a converter on the PATH, and
// nothing in the trash is warmed.
func Warms(name string) bool {
	canonical := accessutil.Canonical(name)
	switch {
	case storageutil.IsTrashPath(canonical), NeedsClientRender(canonical),
		storageutil.DetermineFileTypeFromPath(canonical) != storageutil.FileTypeImage:
		return false
	case photoutil.IsRawFile(canonical):
		return photoutil.IsRawConverterAvailable()
	}
	return true
}

// Enqueue queues item's grid tier, waiting for room in the queue until ctx is
// done. It reports whether the item was queued: false for a file [Warms]
// refuses, one already waiting, or a ctx that ended first.
func (w *Warmer) Enqueue(ctx context.Context, item WarmItem) bool {
	item.RelPath = accessutil.Canonical(item.RelPath)
	if !Warms(item.RelPath) {
		return false
	}
	w.mu.Lock()
	if w.pending[item] {
		w.mu.Unlock()
		return false
	}
	w.pending[item] = true
	w.mu.Unlock()
	select {
	case w.queue <- item:
		return true
	case <-ctx.Done():
		w.forget(item)
		return false
	}
}

// Run generates the queued grid tiers one at a time until ctx is done. A
// failure is logged and the photo left for its first request to try again.
func (w *Warmer) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case item := <-w.queue:
			// Forgotten before it is warmed, so a write landing meanwhile
			// queues the photo again rather than leaving a stale thumbnail.
			w.forget(item)
			if _, err := w.warm(ctx, item); err != nil && ctx.Err() == nil {
				log.Printf("[thumbnail-warmer] %q (serial=%q): %v", item.RelPath, item.Serial, err)
			}
		}
	}
}

// Watch queues the photos each upload, new folder and move lands, walking a
// folder the event names, until ctx is done. It subscribes before it returns;
// a nil bus watches nothing.
func (w *Warmer) Watch(ctx context.Context, bus *eventbus.Bus) {
	if bus == nil {
		return
	}
	events, unsubscribe := bus.Subscribe("thumbnail-warmer")
	go func() {
		<-ctx.Done()
		unsubscribe()
	}()
	go func() {
		for evt := range events {
			switch evt.Kind {
			case eventbus.EventUpload, eventbus.EventNewFolder:
				w.enqueuePath(ctx, evt.DeviceSerial, evt.Path)
			case eventbus.EventMove:
				// The cache is keyed by path, so a moved photo has no
				// thumbnail at its new one.
				w.enqueuePath(ctx, evt.DeviceSerial, evt.NewPath)
			}
		}
	}()
}

// forget drops item from the set of photos waiting.
func (w *Warmer) forget(item WarmItem) {
	w.mu.Lock()
	delete(w.pending, item)
	w.mu.Unlock()
}

// enqueuePath queues the file at relPath on serial's device, or every file
// under it when it is a folder. A device or path that is gone is skipped.
func (w *Warmer) enqueuePath(ctx context.Context, serial, relPath string) {
	relPath = accessutil.Canonical(relPath)
	if storageutil.IsTrashPath(relPath) {
		return
	}
	fsys, err := photoutil.DeviceFS(w.params.Registry, serial)
	if err != nil {
		return
	}
	info, err := fsys.Stat(ctx, relPath)
	if err != nil {
		return
	}
	if !info.IsDir {
		w.Enqueue(ctx, WarmItem{Serial: serial, RelPath: relPath})
		return
	}
	err = vfs.Walk(ctx, fsys, relPath, func(fi vfs.FileInfo) error {
		if !fi.IsDir {
			w.Enqueue(ctx, WarmItem{Serial: serial, RelPath: fi.Path})
		}
		return ctx.Err()
	})
	if err != nil && ctx.Err() == nil && !errors.Is(err, vfs.ErrNotFound) {
		log.Printf("[thumbnail-warmer] walk %q (serial=%q): %v", relPath, serial, err)
	}
}

// warm generates item's grid tier the way GET /thumbnails/<path> would, under
// the same cache key, and reports whether it rendered one. A file that is
// gone, or whose tier is already fresh, or that has a fresh client thumbnail
// the tier is resized from, renders nothing.
func (w *Warmer) warm(ctx context.Context, item WarmItem) (bool, error) {
	fsys, err := photoutil.DeviceFS(w.params.Registry, item.Serial)
	if err != nil {
		return false, nil
	}
	info, err := fsys.Stat(ctx, item.RelPath)
	if errors.Is(err, vfs.ErrNotFound) || (err == nil && info.IsDir) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	// The handler's wildcard keeps the leading slash, and the key with it.
	filePath := "/" + item.RelPath
	client, err := FromClientThumbnail(FromClientThumbnailParams{
		Queries: w.params.Queries, Serial: item.Serial, RelPath: item.RelPath,
		FilePath: filePath, SourceModTime: info.ModTime, Size: SizeLg,
	})
	if err == nil && client.Found {
		return false, nil
	}
	prepared, err := Prepare(PrepareParams{
		Queries: w.params.Queries, Serial: item.Serial, RelPath: item.RelPath,
		FilePath: filePath, Size: SizeLg, SrcModTime: info.ModTime,
	})
	if err != nil || prepared.Hit {
		return false, err
	}
	release, err := w.acquire(ctx, SemaphoreClass(item.RelPath, false))
	if err != nil {
		return false, err
	}
	defer release()
	if _, err := Generate(GenerateParams{
		Ctx: ctx, Queries: w.params.Queries, FS: fsys,
		Serial: item.Serial, RelPath: item.RelPath,
		Ext:   strings.ToLower(filepath.Ext(item.RelPath)),
		Width: prepared.Width, Height: prepared.Height,
		RotationQuarters: prepared.RotationQuarters,
		CachedPath:       prepared.CachedPath,
	}); err != nil {
		return false, err
	}
	return true, nil
}

// acquire takes a slot of class's semaphore at low priority: only while a
// request could still take another, unless the class has one slot alone.
// It waits as long as that takes, and returns the slot's release.
func (w *Warmer) acquire(ctx context.Context, class iosemutil.Class) (func(), error) {
	sem := w.params.IOSemaphore.For(class)
	if sem == nil {
		return func() {}, nil
	}
	spare := min(2, sem.Cap())
	for {
		if sem.Available() >= spare && sem.Acquire(ctx, warmYieldInterval) {
			return sem.Release, nil
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(warmYieldInterval):
		}
	}
}

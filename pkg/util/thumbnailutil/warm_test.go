package thumbnailutil

import (
	"bytes"
	"context"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// warmLibrary is a registry whose internal drive holds files, a database,
// and a HOME of the test's own for the thumbnail cache.
func warmLibrary(t *testing.T, files map[string][]byte) (vfs.Registry, vfs.VFS, db.Querier) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	ctx := context.Background()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for p, data := range files {
		if err := fsys.Write(ctx, p, bytes.NewReader(data), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, fsys); err != nil {
		t.Fatal(err)
	}
	return registry, fsys, dbtest.NewDB(t).Queries
}

// gridTierFresh reports whether relPath's lg thumbnail is cached under the
// key a GET /thumbnails/<relPath> request computes, and newer than the file.
func gridTierFresh(t *testing.T, fsys vfs.VFS, queries db.Querier, relPath string) bool {
	t.Helper()
	info, err := fsys.Stat(context.Background(), relPath)
	if err != nil {
		t.Fatal(err)
	}
	prepared, err := Prepare(PrepareParams{
		Queries: queries, RelPath: relPath, FilePath: "/" + relPath,
		Size: ParseSize(""), SrcModTime: info.ModTime,
	})
	if err != nil {
		t.Fatal(err)
	}
	return prepared.Hit
}

func waitUntil(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// TestWarmerGeneratesTheGridTierOfAQueuedPhoto: a photo's grid thumbnail
// used to exist only once a client asked for it (#4219). A queued photo now
// has its lg tier cached where the GET handler looks, before any request.
func TestWarmerGeneratesTheGridTierOfAQueuedPhoto(t *testing.T) {
	registry, fsys, queries := warmLibrary(t, map[string][]byte{"Photos/a.jpg": sourceJPEG(t)})
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)

	if !w.Enqueue(ctx, WarmItem{RelPath: "/Photos/a.jpg"}) {
		t.Fatal("Enqueue refused a JPEG")
	}
	waitUntil(t, "the lg tier", func() bool { return gridTierFresh(t, fsys, queries, "Photos/a.jpg") })
}

// TestWarmsSkipsWhatTheDeviceDoesNotRender: HEIC, video and 3D models are
// rendered by a client, so the device never queues them; nor anything that
// is not a photo, nor the trash.
func TestWarmsSkipsWhatTheDeviceDoesNotRender(t *testing.T) {
	for name, want := range map[string]bool{
		"a.jpg":             true,
		"Photos/B.PNG":      true,
		"a.webp":            true,
		"a.heic":            false,
		"a.heif":            false,
		"clip.mp4":          false,
		"clip.webm":         false,
		"model.stl":         false,
		"notes.pdf":         false,
		"song.flac":         false,
		".trash/1-a/a.jpg":  false,
		"/.trash/1-a/a.jpg": false,
	} {
		if got := Warms(name); got != want {
			t.Errorf("Warms(%q) = %v, want %v", name, got, want)
		}
	}
}

// TestWarmerSkipsAFreshThumbnail: a photo whose lg tier is already newer than
// it is not decoded again.
func TestWarmerSkipsAFreshThumbnail(t *testing.T) {
	registry, _, queries := warmLibrary(t, map[string][]byte{"a.jpg": sourceJPEG(t)})
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	ctx := context.Background()
	generated, err := w.warm(ctx, WarmItem{RelPath: "a.jpg"})
	if err != nil || !generated {
		t.Fatalf("first warm: generated=%v err=%v, want a generated thumbnail", generated, err)
	}
	generated, err = w.warm(ctx, WarmItem{RelPath: "a.jpg"})
	if err != nil || generated {
		t.Fatalf("second warm: generated=%v err=%v, want it skipped as fresh", generated, err)
	}
}

// TestWarmerRegeneratesAStaleThumbnail: a file rewritten after its thumbnail
// was cached is warmed again.
func TestWarmerRegeneratesAStaleThumbnail(t *testing.T) {
	registry, fsys, queries := warmLibrary(t, map[string][]byte{"a.jpg": sourceJPEG(t)})
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	ctx := context.Background()
	if _, err := w.warm(ctx, WarmItem{RelPath: "a.jpg"}); err != nil {
		t.Fatal(err)
	}
	time.Sleep(10 * time.Millisecond)
	if err := fsys.Write(ctx, "a.jpg", bytes.NewReader(sourceJPEG(t)), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	generated, err := w.warm(ctx, WarmItem{RelPath: "a.jpg"})
	if err != nil || !generated {
		t.Fatalf("warm after rewrite: generated=%v err=%v, want it regenerated", generated, err)
	}
}

// TestWarmerSkipsAPhotoWithAClientThumbnail: a fresh thumbnail a client
// uploaded is what the GET handler serves first, so the device decodes
// nothing; the lg tier comes from the client's.
func TestWarmerSkipsAPhotoWithAClientThumbnail(t *testing.T) {
	registry, fsys, queries := warmLibrary(t, map[string][]byte{"a.jpg": []byte("not decodable here")})
	if err := store(t, StoreClientThumbnailParams{
		RelPath: "a.jpg", Reader: bytes.NewReader(clientJPEG(t, 400, 300)), SkipHash: true,
	}); err != nil {
		t.Fatal(err)
	}
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	generated, err := w.warm(context.Background(), WarmItem{RelPath: "a.jpg"})
	if err != nil || generated {
		t.Fatalf("warm: generated=%v err=%v, want the client's thumbnail used", generated, err)
	}
	if !gridTierFresh(t, fsys, queries, "a.jpg") {
		t.Error("the lg tier was not cached from the client's thumbnail")
	}
}

// TestWarmerQueuesEachPhotoOnce: a photo already waiting is not queued a
// second time, and what Warms refuses is never queued.
func TestWarmerQueuesEachPhotoOnce(t *testing.T) {
	registry, _, queries := warmLibrary(t, nil)
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	ctx := context.Background()
	if !w.Enqueue(ctx, WarmItem{RelPath: "a.jpg"}) {
		t.Fatal("first Enqueue refused")
	}
	if w.Enqueue(ctx, WarmItem{RelPath: "/a.jpg"}) {
		t.Error("the same photo, spelled with a leading slash, was queued twice")
	}
	if !w.Enqueue(ctx, WarmItem{Serial: "USB-1", RelPath: "a.jpg"}) {
		t.Error("the same path on another device was refused")
	}
	if w.Enqueue(ctx, WarmItem{RelPath: "clip.mp4"}) {
		t.Error("a video was queued")
	}
}

// TestWarmerYieldsTheDecodeSlotToRequests: generation runs off the request
// path, at low priority. While a request holds a decode slot the warmer
// waits rather than take the last one, and it never holds more than one.
func TestWarmerYieldsTheDecodeSlotToRequests(t *testing.T) {
	registry, fsys, queries := warmLibrary(t, map[string][]byte{"a.jpg": sourceJPEG(t)})
	sem := iosemutil.New()
	decode := sem.For(iosemutil.Decode)
	// Every slot but one is busy with requests.
	held := decode.Cap() - 1
	for range held {
		if !decode.AcquireDefault(context.Background()) {
			t.Fatal("could not take a decode slot")
		}
	}
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry, IOSemaphore: sem})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)
	w.Enqueue(ctx, WarmItem{RelPath: "a.jpg"})

	time.Sleep(3 * warmYieldInterval)
	if gridTierFresh(t, fsys, queries, "a.jpg") {
		t.Fatal("the warmer took the last decode slot from requests")
	}
	for range held {
		decode.Release()
	}
	waitUntil(t, "the lg tier once requests are done", func() bool { return gridTierFresh(t, fsys, queries, "a.jpg") })
	if decode.Available() != decode.Cap() {
		t.Errorf("%d of %d decode slots free after warming, want all", decode.Available(), decode.Cap())
	}
}

// TestWarmerWatchWarmsAnUploadedFolder: an upload event names the folder the
// files landed in, and every photo under it is warmed; a move warms the
// photo at its new path, whose cache key is new.
func TestWarmerWatchWarmsAnUploadedFolder(t *testing.T) {
	registry, fsys, queries := warmLibrary(t, map[string][]byte{
		"Camera/a.jpg": sourceJPEG(t), "Camera/2026/b.jpg": sourceJPEG(t), "moved.jpg": sourceJPEG(t),
	})
	bus := eventbus.New()
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)
	w.Watch(ctx, bus)

	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "/Camera"})
	bus.Publish(eventbus.Event{Kind: eventbus.EventMove, Path: "old.jpg", NewPath: "moved.jpg"})
	for _, p := range []string{"Camera/a.jpg", "Camera/2026/b.jpg", "moved.jpg"} {
		waitUntil(t, p+"'s lg tier", func() bool { return gridTierFresh(t, fsys, queries, p) })
	}
}

// TestWarmerMissingFileIsNoError: a photo deleted while it waited in the
// queue is skipped quietly.
func TestWarmerMissingFileIsNoError(t *testing.T) {
	registry, _, queries := warmLibrary(t, nil)
	w := NewWarmer(WarmerParams{Queries: queries, Registry: registry})
	if generated, err := w.warm(context.Background(), WarmItem{RelPath: "gone.jpg"}); err != nil || generated {
		t.Fatalf("warm: generated=%v err=%v, want a quiet skip", generated, err)
	}
}

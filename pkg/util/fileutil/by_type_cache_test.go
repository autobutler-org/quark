package fileutil

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// byTypeFixture is a USB device served through the VFS registry, the path the
// /files/by-type handler takes in production.
type byTypeFixture struct {
	filesDir string
	params   ListByTypeParams
}

func newByTypeFixture(t testing.TB) byTypeFixture {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: "USB-1780"})
	registry := newDeviceRegistry(t, svc)
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	return byTypeFixture{filesDir: filesDir, params: ListByTypeParams{
		Ctx:      context.Background(),
		Registry: registry,
		Storage:  svc,
		Access:   system.Access,
		FileType: storageutil.FileTypeQdoc,
	}}
}

func (f byTypeFixture) write(t testing.TB, rel string) {
	t.Helper()
	path := filepath.Join(f.filesDir, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{}"), 0644); err != nil {
		t.Fatal(err)
	}
}

func (f byTypeFixture) list(t testing.TB) []FileNode {
	t.Helper()
	result, err := ListByType(f.params)
	if err != nil {
		t.Fatalf("ListByType: %v", err)
	}
	return result.Files
}

func TestListByTypeCacheServesTheWalkUntilAFileEvent(t *testing.T) {
	f := newByTypeFixture(t)
	bus := eventbus.New()
	f.params.Cache = NewByTypeCache()
	f.params.Cache.Watch(bus)

	f.write(t, "notes/a.qdoc")
	if got := f.list(t); len(got) != 1 {
		t.Fatalf("first listing: got %d files, want 1", len(got))
	}

	// Written behind Quark's back: no event, so the cached walk still answers.
	f.write(t, "notes/b.qdoc")
	if got := f.list(t); len(got) != 1 {
		t.Fatalf("cached listing: got %d files, want 1", len(got))
	}

	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "notes/b.qdoc", DeviceSerial: "USB-1780"})
	deadline := time.Now().Add(2 * time.Second)
	for len(f.list(t)) != 2 {
		if time.Now().After(deadline) {
			t.Fatal("an upload event did not drop the cached listing")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestListByTypeCacheIgnoresEventsThatDoNotTouchFiles(t *testing.T) {
	bus := eventbus.New()
	c := NewByTypeCache()
	c.Watch(bus)

	// One subscriber reads in order, so once the delete has been handled the
	// chat message before it has been too.
	bus.Publish(eventbus.Event{Kind: eventbus.EventChatMessageCreated})
	bus.Publish(eventbus.Event{Kind: eventbus.EventDelete, Path: "a.qdoc"})
	deadline := time.Now().Add(2 * time.Second)
	for {
		_, gen, _ := c.get("")
		if gen == 1 {
			return
		}
		if gen > 1 {
			t.Fatalf("a chat event invalidated the cache (generation %d)", gen)
		}
		if time.Now().After(deadline) {
			t.Fatal("a delete event did not invalidate the cache")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestByTypeCacheDropsEverythingOnAResync(t *testing.T) {
	bus := eventbus.New()
	c := NewByTypeCache()
	c.Watch(bus)

	bus.Publish(eventbus.Event{Kind: eventbus.EventResync, Data: eventbus.Resync{Dropped: 1}})
	deadline := time.Now().Add(2 * time.Second)
	for {
		if _, gen, _ := c.get(""); gen == 1 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("a resync did not invalidate the cache")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestListByTypeCacheHandsOutCopies(t *testing.T) {
	f := newByTypeFixture(t)
	f.params.Cache = NewByTypeCache()
	f.write(t, "a.qdoc")

	first := f.list(t)
	first[0].Name = "mutated"
	if got := f.list(t); got[0].Name != "a.qdoc" {
		t.Fatalf("a caller's edit reached the cache: %q", got[0].Name)
	}
}

func TestByTypeCacheDropsAWalkThatRacedAnInvalidation(t *testing.T) {
	c := NewByTypeCache()
	_, gen, _ := c.get("k")
	c.Invalidate()
	c.put("k", gen, []FileNode{{}})
	if _, _, ok := c.get("k"); ok {
		t.Fatal("a walk started before an invalidation was stored")
	}
}

func TestByTypeCacheIsBounded(t *testing.T) {
	c := NewByTypeCache()
	clock := time.Unix(0, 0)
	c.now = func() time.Time { return clock }
	for i := range byTypeCacheMaxEntries + 1 {
		clock = clock.Add(time.Second)
		c.put(fmt.Sprintf("k%d", i), 0, []FileNode{{}})
	}
	if len(c.entries) != byTypeCacheMaxEntries {
		t.Fatalf("got %d entries, want %d", len(c.entries), byTypeCacheMaxEntries)
	}
	if _, _, ok := c.get("k0"); ok {
		t.Fatal("the oldest entry was not the one evicted")
	}

	c.put("big", 0, make([]FileNode, byTypeCacheMaxFiles+1))
	if _, _, ok := c.get("big"); ok {
		t.Fatal("a listing over the size cap was stored")
	}

	clock = clock.Add(byTypeCacheMaxAge + time.Second)
	if _, _, ok := c.get(fmt.Sprintf("k%d", byTypeCacheMaxEntries)); ok {
		t.Fatal("an entry older than the max age was served")
	}
}

func TestNilByTypeCacheCachesNothing(t *testing.T) {
	var c *ByTypeCache
	c.put("k", 0, []FileNode{{}})
	c.Invalidate()
	if _, _, ok := c.get("k"); ok {
		t.Fatal("a nil cache served an entry")
	}
}

// BenchmarkListByType measures the by-type listing over a library of 4,000
// files, 40 of them documents, walked fresh and served from the cache.
func BenchmarkListByType(b *testing.B) {
	f := newByTypeFixture(b)
	for d := range 40 {
		for i := range 100 {
			ext := "txt"
			if i == 0 {
				ext = "qdoc"
			}
			f.write(b, fmt.Sprintf("dir%02d/file%03d.%s", d, i, ext))
		}
	}
	b.Run("uncached", func(b *testing.B) {
		for b.Loop() {
			f.list(b)
		}
	})
	b.Run("cached", func(b *testing.B) {
		f.params.Cache = NewByTypeCache()
		for b.Loop() {
			f.list(b)
		}
	})
}

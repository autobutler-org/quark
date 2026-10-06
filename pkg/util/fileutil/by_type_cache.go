package fileutil

import (
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// byTypeCacheMaxEntries bounds how many (type, device set) listings are kept.
// Docs and Sheets ask for two types, so this leaves room for a few scopes.
const byTypeCacheMaxEntries = 8

// byTypeCacheMaxFiles is the largest listing worth keeping. A bigger one is
// walked on every request as before rather than pinning megabytes of heap.
const byTypeCacheMaxFiles = 2048

// byTypeCacheMaxAge bounds how stale a listing can get from a change Quark
// never saw — a file copied onto a USB disk elsewhere, or edited over SSH.
// Every change made through Quark publishes an event and drops the cache.
const byTypeCacheMaxAge = 5 * time.Minute

// ByTypeCache keeps ListByType's whole-tree walk between requests (#1780).
//
// It holds the listing before any caller's access filter, so one walk serves
// every account; ListByType filters a copy per request. Any file-tree event on
// the bus drops every entry. A walk that was already running when an event
// arrived is not stored, so a listing read before a change cannot outlive it.
//
// A nil *ByTypeCache is valid and caches nothing.
type ByTypeCache struct {
	mu      sync.Mutex
	gen     uint64
	entries map[string]byTypeEntry
	now     func() time.Time
}

// byTypeEntry is one cached listing, sorted newest-first.
type byTypeEntry struct {
	files    []FileNodeWithTime
	storedAt time.Time
}

// NewByTypeCache returns an empty cache. Call Watch to keep it current.
func NewByTypeCache() *ByTypeCache {
	return &ByTypeCache{entries: make(map[string]byTypeEntry), now: time.Now}
}

// Watch subscribes to bus and drops the cache on every event that changes the
// file tree, until the bus closes the subscription. The subscription is made
// before Watch returns, so no event published afterwards is missed. A resync
// means the bus replaced a backlog it could not hold, so it drops the cache
// too.
func (c *ByTypeCache) Watch(bus *eventbus.Bus) {
	if c == nil || bus == nil {
		return
	}
	events, _ := bus.Subscribe("by-type-cache")
	go func() {
		for evt := range events {
			switch evt.Kind {
			case eventbus.EventUpload, eventbus.EventDelete, eventbus.EventMove,
				eventbus.EventNewFolder, eventbus.EventTrashChanged, eventbus.EventResync:
				c.Invalidate()
			}
		}
	}()
}

// Invalidate drops every cached listing and turns away any walk in flight.
func (c *ByTypeCache) Invalidate() {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.gen++
	clear(c.entries)
}

// get returns the cached listing for key, or the generation a walk started
// now has to hand back to put.
func (c *ByTypeCache) get(key string) ([]FileNodeWithTime, uint64, bool) {
	if c == nil {
		return nil, 0, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[key]
	if ok && c.now().Sub(entry.storedAt) > byTypeCacheMaxAge {
		delete(c.entries, key)
		ok = false
	}
	return entry.files, c.gen, ok
}

// put stores files under key unless the cache was invalidated since get
// handed out gen, or the listing is too big to keep.
func (c *ByTypeCache) put(key string, gen uint64, files []FileNodeWithTime) {
	if c == nil || len(files) > byTypeCacheMaxFiles {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if gen != c.gen {
		return
	}
	if _, ok := c.entries[key]; !ok && len(c.entries) >= byTypeCacheMaxEntries {
		// Evict the oldest entry.
		oldest := ""
		for k, e := range c.entries {
			if oldest == "" || e.storedAt.Before(c.entries[oldest].storedAt) {
				oldest = k
			}
		}
		delete(c.entries, oldest)
	}
	c.entries[key] = byTypeEntry{files: files, storedAt: c.now()}
}

// byTypeKey names a listing by its type and the device roots it walks, so a
// disk plugged in or out is a different listing rather than a stale one.
func byTypeKey(fileType storageutil.FileType, serials []string, devices []storageutil.ManagedDevice) string {
	parts := []string{string(fileType)}
	parts = append(parts, slices.Sorted(slices.Values(serials))...)
	parts = append(parts, "\x01")
	for _, d := range devices {
		parts = append(parts, DeviceSerial(d)+"\x02"+d.FilesDir)
	}
	return strings.Join(parts, "\x00")
}

// Package iosemutil bounds the server's heavy work — image decodes, video
// frame extraction, RAW conversion and whole-file copies — with one counting
// semaphore per kind of work, so memory and disk stay bounded under
// concurrent load.
//
// Each kind of work is a [Class] with its own slots: a backup copying
// multi-GiB videos holds copy slots, never the decode slots thumbnails need
// (#2762). Pick the class with [Semaphore.For] before the work starts and
// release the slot when it ends. Operations that cannot acquire a slot within
// the timeout should return HTTP 503 with a Retry-After header rather than
// blocking indefinitely.
package iosemutil

import (
	"context"
	"runtime"
	"time"
)

// Class is a kind of work that holds a slot while it runs.
type Class int

const (
	// Decode is a full image decode in-process: thumbnail generation, JPEG
	// conversion of a download, and the perceptual-hash backfill. It is
	// CPU-bound and costs the decoded pixels in memory — up to
	// photoutil.MaxDecodePixels — so it gets half the cores, at least two.
	Decode Class = iota
	// Video is ffmpeg pulling a frame out of a video for its thumbnail.
	// ffmpeg threads on its own, so it also gets half the cores, at least one.
	Video
	// Raw is a camera RAW converted through dcraw, exiftool or ffmpeg. Each
	// runs a child process and decodes a full-size preview, so it gets a
	// quarter of the cores, at least one.
	Raw
	// Copy is a whole-file disk copy: backup sync and snapshot backup. It is
	// bound by one disk rather than by cores, so it stays at two slots
	// whatever the core count — enough to overlap a read with a write.
	Copy

	classCount
)

// String names the class for logs.
func (c Class) String() string {
	switch c {
	case Decode:
		return "decode"
	case Video:
		return "video"
	case Raw:
		return "raw"
	case Copy:
		return "copy"
	}
	return "unknown"
}

// Classes lists every class.
func Classes() []Class {
	return []Class{Decode, Video, Raw, Copy}
}

const (
	// DefaultTimeout is the maximum time a caller will wait to acquire the
	// semaphore before giving up. Callers should return HTTP 503 on timeout.
	DefaultTimeout = 30 * time.Second
)

// Semaphore is a counting semaphore that limits concurrent heavy operations.
// The one New returns also carries a semaphore per [Class]; reach those with
// For. The zero value is not valid — use New or NewWithConcurrency.
type Semaphore struct {
	ch      chan struct{}
	classes []*Semaphore
}

// New returns the server's semaphores: one per [Class], each sized from
// runtime.NumCPU as the class documents. The returned semaphore's own slots
// number the classes' total, for work that belongs to no class.
func New() *Semaphore {
	cores := runtime.NumCPU()
	classes := make([]*Semaphore, classCount)
	total := 0
	for _, c := range Classes() {
		classes[c] = NewWithConcurrency(classSlots(c, cores))
		total += classes[c].Cap()
	}
	s := NewWithConcurrency(total)
	s.classes = classes
	return s
}

// For returns the semaphore that bounds work of class c. A semaphore made by
// NewWithConcurrency has no classes, so every class shares it — what a test
// injecting a single semaphore expects. For on a nil Semaphore is nil, so a
// caller's nil check still reads "no throttling".
func (s *Semaphore) For(c Class) *Semaphore {
	if s == nil || s.classes == nil {
		return s
	}
	return s.classes[c]
}

// NewWithConcurrency returns a Semaphore limited to n concurrent holders.
// Panics if n < 1.
func NewWithConcurrency(n int) *Semaphore {
	if n < 1 {
		panic("iosemutil: concurrency must be >= 1")
	}
	return &Semaphore{ch: make(chan struct{}, n)}
}

// Acquire waits up to timeout to obtain one slot from the semaphore.
// Returns true if the slot was acquired; false if the context or timeout
// expired. Callers must call Release exactly once if Acquire returns true.
func (s *Semaphore) Acquire(ctx context.Context, timeout time.Duration) bool {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	select {
	case s.ch <- struct{}{}:
		return true
	case <-ctx.Done():
		return false
	}
}

// AcquireDefault calls Acquire with DefaultTimeout.
func (s *Semaphore) AcquireDefault(ctx context.Context) bool {
	return s.Acquire(ctx, DefaultTimeout)
}

// Release returns a slot to the semaphore. Must be called exactly once per
// successful Acquire, typically via defer.
func (s *Semaphore) Release() {
	<-s.ch
}

// Available returns the number of free slots (for monitoring/logging).
func (s *Semaphore) Available() int {
	return cap(s.ch) - len(s.ch)
}

// Cap returns the maximum concurrency of this semaphore.
func (s *Semaphore) Cap() int {
	return cap(s.ch)
}

package downloadutil

import "context"

// Acquire waits for a slot until the wait runs out or ctx ends, whichever is
// first. It reports whether it got one; when it did, release must be called
// exactly once when the zip ends. On a nil ZipSlots it always succeeds.
func (z *ZipSlots) Acquire(ctx context.Context) (release func(), ok bool) {
	if z == nil {
		return func() {}, true
	}
	if !z.sem.Acquire(ctx, z.wait) {
		return nil, false
	}
	return z.sem.Release, true
}

// Available is how many slots are free, for logs and tests.
func (z *ZipSlots) Available() int {
	return z.sem.Available()
}

// Cap is how many zips may run at once.
func (z *ZipSlots) Cap() int {
	return z.sem.Cap()
}

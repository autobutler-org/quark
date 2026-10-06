package accessutil

// cacheEntry is one account's snapshot in a Cache.
type cacheEntry struct {
	userID int64
	// seq is the bus sequence number read before the load; the snapshot
	// reflects every event up to it.
	seq    uint64
	result CacheGetResult
}

// cacheFlight is a load in progress that callers wait on together.
type cacheFlight struct {
	seq    uint64
	done   chan struct{}
	result CacheGetResult
	err    error
}

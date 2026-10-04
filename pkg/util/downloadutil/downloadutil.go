// Package downloadutil issues the tokens a browser download authenticates
// with. A plain link cannot send an Authorization header, so the web client
// trades its session for a token bound to one path, then hands the browser a
// URL carrying it and lets the browser stream the file to disk (#2226).
//
// A token is good for one download, not one request: a browser that loses its
// connection partway through retries with the same token, either with a Range
// header to carry on where it stopped or without one to start over (#2270).
//
// Limits: a folder is zipped on the fly and cannot be resumed, so its retry
// starts the zip over. A zip small enough to fit in the zip writer's and the
// OS's send buffers before the client goes away looks complete, so its retry
// gets a 401. Tokens live in memory, so a restart ends every download in
// progress.
//
// It also caps how many folder zips run at once ([ZipSlots], #2757), since
// each one can pin a core.
package downloadutil

import (
	"errors"
	"net/http"
	"runtime"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/iosemutil"
)

// DefaultTokenTTL is how long a token waits to be used. It only has to cover
// the gap between the client receiving it and the browser requesting the URL.
const DefaultTokenTTL = 60 * time.Second

// DefaultIdleWindow is how long a started download may sit with no request in
// flight before its token ends. It is measured from the end of the last
// response, so a slow download that streams for longer is never cut off.
const DefaultIdleWindow = 10 * time.Minute

// ErrInvalidToken is returned for a token that is unknown, ended, expired, or
// bound to a different path or serial.
var ErrInvalidToken = errors.New("invalid or expired download token")

// TokenStore holds the tokens issued whose download has not ended. It lives in
// memory only: a restart drops every token.
type TokenStore struct {
	mu     sync.Mutex
	tokens map[string]token
	ttl    time.Duration
	now    func() time.Time
}

// NewTokenStoreParams configures a store. The zero value is the production
// configuration; tests pin the clock.
type NewTokenStoreParams struct {
	// TTL overrides DefaultTokenTTL. Zero means the default.
	TTL time.Duration
	// Now overrides time.Now.
	Now func() time.Time
}

// NewTokenStore builds an empty store. It starts no goroutine: expired tokens
// are swept on the next issue.
func NewTokenStore(params NewTokenStoreParams) *TokenStore {
	ttl := params.TTL
	if ttl <= 0 {
		ttl = DefaultTokenTTL
	}
	now := params.Now
	if now == nil {
		now = time.Now
	}
	return &TokenStore{tokens: make(map[string]token), ttl: ttl, now: now}
}

// IssueTokenParams names who is downloading and what.
type IssueTokenParams struct {
	Username string
	UserID   int64
	FilePath string
	Serial   string
}

// IssueTokenResult is the token and when it stops working if unused.
type IssueTokenResult struct {
	Token     string
	ExpiresAt time.Time
}

// ConsumeTokenParams is a download request presenting a token.
type ConsumeTokenParams struct {
	Token    string
	FilePath string
	Serial   string
}

// ConsumeTokenResult is the user the download runs as.
type ConsumeTokenResult struct {
	Username string
	UserID   int64
}

// ReleaseTokenParams is the response a consumed token was served, reported
// once it has been written. Every successful ConsumeToken is paired with one.
type ReleaseTokenParams struct {
	Token string
	// Status, Header and Written describe the response: its status code, its
	// headers, and the body bytes that reached the client.
	Status  int
	Header  http.Header
	Written int64
	// Interrupted is true when the handler saw the client go away partway
	// through a response that cannot be resumed, such as a zipped folder. The
	// token then survives, so a retry starts the download over.
	Interrupted bool
}

// DefaultZipWait is how long a folder download waits for a zip slot before it
// is answered 503 with a Retry-After.
const DefaultZipWait = 10 * time.Second

// ZipRetryAfter is the Retry-After, in seconds, a folder download turned away
// for want of a slot is sent.
const ZipRetryAfter = "5"

// DefaultZipSlots is how many folder zips run at once: half the cores, at
// least one. A zip that deflates pins a core (~62 MiB/s on an M2, about a
// third of that on an A76, #2757), so half leaves the rest for thumbnails and
// every other request. Entries already compressed are stored, which makes
// most photo and video zips disk-bound, but the cap holds either way.
func DefaultZipSlots() int {
	return max(1, runtime.NumCPU()/2)
}

// ZipSlotsParams sizes a ZipSlots. Zero values take the defaults.
type ZipSlotsParams struct {
	// Slots is how many zips may run at once; DefaultZipSlots when zero.
	Slots int
	// Wait is how long Acquire waits for a slot; DefaultZipWait when zero.
	Wait time.Duration
}

// ZipSlots caps how many folder zips are built at once. The archive itself is
// still streamed straight onto the response; this bounds only how many
// streams run side by side.
type ZipSlots struct {
	sem  *iosemutil.Semaphore
	wait time.Duration
}

// NewZipSlots returns a ZipSlots sized by params.
func NewZipSlots(params ZipSlotsParams) *ZipSlots {
	if params.Slots < 1 {
		params.Slots = DefaultZipSlots()
	}
	if params.Wait <= 0 {
		params.Wait = DefaultZipWait
	}
	return &ZipSlots{sem: iosemutil.NewWithConcurrency(params.Slots), wait: params.Wait}
}

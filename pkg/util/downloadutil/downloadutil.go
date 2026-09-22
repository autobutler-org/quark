// Package downloadutil issues the single-use tokens a browser download
// authenticates with. A plain link cannot send an Authorization header, so the
// web client trades its session for a token bound to one path, then hands the
// browser a URL carrying it and lets the browser stream the file to disk
// (#2226).
package downloadutil

import (
	"errors"
	"sync"
	"time"
)

// DefaultTokenTTL is how long a token waits to be used. It only has to cover
// the gap between the client receiving it and the browser requesting the URL.
const DefaultTokenTTL = 60 * time.Second

// ErrInvalidToken is returned for a token that is unknown, already used,
// expired, or bound to a different path or serial.
var ErrInvalidToken = errors.New("invalid or expired download token")

// TokenStore holds the tokens issued and not yet used. It lives in memory
// only: a restart drops every token, which costs the client one retry.
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

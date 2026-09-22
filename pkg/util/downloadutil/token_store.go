package downloadutil

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"time"
)

// token is one issued download. lastSeen is not read yet: resumable downloads
// will keep a token alive while Range requests keep arriving, instead of
// deleting it on first use.
type token struct {
	username  string
	userID    int64
	filePath  string
	serial    string
	createdAt time.Time
	lastSeen  time.Time
}

// IssueToken creates a token for one path and serial, owned by one user.
func (s *TokenStore) IssueToken(params IssueTokenParams) (IssueTokenResult, error) {
	id, err := newTokenID()
	if err != nil {
		return IssueTokenResult{}, err
	}
	now := s.now()

	s.mu.Lock()
	defer s.mu.Unlock()
	s.sweepLocked(now)
	s.tokens[id] = token{
		username:  params.Username,
		userID:    params.UserID,
		filePath:  params.FilePath,
		serial:    params.Serial,
		createdAt: now,
		lastSeen:  now,
	}
	return IssueTokenResult{Token: id, ExpiresAt: now.Add(s.ttl)}, nil
}

// ConsumeToken spends a token. It works once, before it expires, and only for
// the path and serial it was issued for. A mismatched request still spends it,
// so a leaked token cannot be probed against other paths.
func (s *TokenStore) ConsumeToken(params ConsumeTokenParams) (ConsumeTokenResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.tokens[params.Token]
	if !ok {
		return ConsumeTokenResult{}, ErrInvalidToken
	}
	delete(s.tokens, params.Token)
	if s.expired(t, s.now()) || t.filePath != params.FilePath || t.serial != params.Serial {
		return ConsumeTokenResult{}, ErrInvalidToken
	}
	return ConsumeTokenResult{Username: t.username, UserID: t.userID}, nil
}

func (s *TokenStore) expired(t token, now time.Time) bool {
	return now.Sub(t.createdAt) > s.ttl
}

// sweepLocked drops tokens that expired unused. The caller holds mu.
func (s *TokenStore) sweepLocked(now time.Time) {
	for id, t := range s.tokens {
		if s.expired(t, now) {
			delete(s.tokens, id)
		}
	}
}

// newTokenID returns an unguessable, URL-safe id: the token alone authorizes
// a download, so it must not be predictable.
func newTokenID() (string, error) {
	const idBytes = 32
	var buf [idBytes]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", fmt.Errorf("failed to generate download token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(buf[:]), nil
}

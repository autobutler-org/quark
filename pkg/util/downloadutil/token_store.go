package downloadutil

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"net/http"
	"strconv"
	"time"
)

// token is one issued download. Until its first request it expires ttl after
// createdAt; once started, it expires DefaultIdleWindow after lastSeen, the
// end of its last response, and never while a request is in flight.
type token struct {
	username  string
	userID    int64
	filePath  string
	serial    string
	createdAt time.Time
	lastSeen  time.Time
	started   bool
	inFlight  int
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

// ConsumeToken admits one request of a download. The first request starts
// it; a later one, with a Range header to resume or without one to start over,
// must arrive within the idle window. It only works for the path and serial
// the token was issued for. A refused request ends the token, so a leaked
// token cannot be probed against other paths. Every success must be followed by ReleaseToken.
func (s *TokenStore) ConsumeToken(params ConsumeTokenParams) (ConsumeTokenResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.tokens[params.Token]
	if !ok {
		return ConsumeTokenResult{}, ErrInvalidToken
	}
	now := s.now()
	if s.expired(t, now) || t.filePath != params.FilePath || t.serial != params.Serial {
		delete(s.tokens, params.Token)
		return ConsumeTokenResult{}, ErrInvalidToken
	}
	t.started = true
	t.inFlight++
	t.lastSeen = now
	s.tokens[params.Token] = t
	return ConsumeTokenResult{Username: t.username, UserID: t.userID}, nil
}

// ReleaseToken reports the response a consumed request was served. The token
// ends when that response delivered the last byte of the file, or when it
// could not be resumed from at all and was not interrupted: no Accept-Ranges,
// as with a zipped folder, an archive entry, a converted image, or an error.
// Otherwise the idle window starts now.
func (s *TokenStore) ReleaseToken(params ReleaseTokenParams) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.tokens[params.Token]
	if !ok {
		return
	}
	resumable := params.Header.Get("Accept-Ranges") == "bytes"
	if (!resumable && !params.Interrupted) || reachedEnd(params) {
		delete(s.tokens, params.Token)
		return
	}
	t.inFlight--
	t.lastSeen = s.now()
	s.tokens[params.Token] = t
}

// reachedEnd reports whether a response delivered the file through its last
// byte: a whole 200 body, or a 206 whose single range ends the file. A
// multipart range response is never counted; the idle window ends it.
func reachedEnd(params ReleaseTokenParams) bool {
	switch params.Status {
	case http.StatusOK:
		length, err := strconv.ParseInt(params.Header.Get("Content-Length"), 10, 64)
		return err == nil && params.Written == length
	case http.StatusPartialContent:
		var start, end, size int64
		if _, err := fmt.Sscanf(params.Header.Get("Content-Range"), "bytes %d-%d/%d", &start, &end, &size); err != nil {
			return false
		}
		return end == size-1 && params.Written == end-start+1
	}
	return false
}

func (s *TokenStore) expired(t token, now time.Time) bool {
	if !t.started {
		return now.Sub(t.createdAt) > s.ttl
	}
	return t.inFlight == 0 && now.Sub(t.lastSeen) > DefaultIdleWindow
}

// sweepLocked drops tokens that expired unused or went idle. The caller holds
// mu.
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

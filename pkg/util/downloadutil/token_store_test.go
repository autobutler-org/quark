package downloadutil_test

import (
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/downloadutil"
)

type fakeClock struct{ t time.Time }

func (c *fakeClock) now() time.Time { return c.t }

func newStore() (*downloadutil.TokenStore, *fakeClock) {
	clock := &fakeClock{t: time.Unix(1_700_000_000, 0)}
	store := downloadutil.NewTokenStore(downloadutil.NewTokenStoreParams{
		TTL: time.Minute,
		Now: clock.now,
	})
	return store, clock
}

func issue(t *testing.T, store *downloadutil.TokenStore) string {
	t.Helper()
	result, err := store.IssueToken(downloadutil.IssueTokenParams{
		Username: "alice",
		UserID:   7,
		FilePath: "users/video.mp4",
		Serial:   "disk-1",
	})
	if err != nil {
		t.Fatalf("IssueToken: %v", err)
	}
	return result.Token
}

func TestConsumeTokenReturnsTheIssuingUser(t *testing.T) {
	store, _ := newStore()
	tok := issue(t, store)
	params := downloadutil.ConsumeTokenParams{Token: tok, FilePath: "users/video.mp4", Serial: "disk-1"}

	got, err := store.ConsumeToken(params)
	if err != nil {
		t.Fatalf("first consume: %v", err)
	}
	if got.Username != "alice" || got.UserID != 7 {
		t.Errorf("consume returned %+v, want alice/7", got)
	}
}

func TestConsumeTokenRejectsAnotherPathOrSerial(t *testing.T) {
	for name, params := range map[string]downloadutil.ConsumeTokenParams{
		"path":   {FilePath: "users/other.mp4", Serial: "disk-1"},
		"serial": {FilePath: "users/video.mp4", Serial: "disk-2"},
	} {
		t.Run(name, func(t *testing.T) {
			store, _ := newStore()
			params.Token = issue(t, store)
			if _, err := store.ConsumeToken(params); !errors.Is(err, downloadutil.ErrInvalidToken) {
				t.Errorf("got %v, want ErrInvalidToken", err)
			}
		})
	}
}

func TestConsumeTokenRejectsAnExpiredToken(t *testing.T) {
	store, clock := newStore()
	tok := issue(t, store)
	clock.t = clock.t.Add(time.Minute + time.Second)

	_, err := store.ConsumeToken(downloadutil.ConsumeTokenParams{
		Token: tok, FilePath: "users/video.mp4", Serial: "disk-1",
	})
	if !errors.Is(err, downloadutil.ErrInvalidToken) {
		t.Errorf("got %v, want ErrInvalidToken", err)
	}
}

func TestConsumeTokenRejectsAnUnknownToken(t *testing.T) {
	store, _ := newStore()
	_, err := store.ConsumeToken(downloadutil.ConsumeTokenParams{Token: "nope"})
	if !errors.Is(err, downloadutil.ErrInvalidToken) {
		t.Errorf("got %v, want ErrInvalidToken", err)
	}
}

// file is the one download every test below presents its token for.
var file = downloadutil.ConsumeTokenParams{FilePath: "users/video.mp4", Serial: "disk-1"}

func consume(store *downloadutil.TokenStore, tok string) error {
	params := file
	params.Token = tok
	_, err := store.ConsumeToken(params)
	return err
}

// release reports what a served download sent: its status, its headers and how
// much of the body reached the client.
func release(store *downloadutil.TokenStore, tok string, status int, written int64, header ...string) {
	h := http.Header{}
	for i := 0; i+1 < len(header); i += 2 {
		h.Set(header[i], header[i+1])
	}
	store.ReleaseToken(downloadutil.ReleaseTokenParams{Token: tok, Status: status, Header: h, Written: written})
}

// TestConsumeTokenResumesAnInterruptedDownload is #2270: a browser that loses
// its connection partway through retries with a Range header and the same
// token, and is let back in.
func TestConsumeTokenResumesAnInterruptedDownload(t *testing.T) {
	store, _ := newStore()
	tok := issue(t, store)

	if err := consume(store, tok); err != nil {
		t.Fatalf("first request: %v", err)
	}
	release(store, tok, http.StatusOK, 4, "Accept-Ranges", "bytes", "Content-Length", "10")

	if err := consume(store, tok); err != nil {
		t.Fatalf("Range retry: %v", err)
	}
	release(store, tok, http.StatusPartialContent, 3, "Accept-Ranges", "bytes", "Content-Range", "bytes 4-9/10")
	if err := consume(store, tok); err != nil {
		t.Errorf("second Range retry: %v", err)
	}
}

// TestConsumeTokenRestartsAnInterruptedDownload covers Firefox's Cancel then
// Retry: the partial file is discarded, so the retry is a plain GET with no
// Range, and it starts the download again from zero.
func TestConsumeTokenRestartsAnInterruptedDownload(t *testing.T) {
	store, _ := newStore()
	tok := issue(t, store)
	if err := consume(store, tok); err != nil {
		t.Fatalf("first request: %v", err)
	}
	release(store, tok, http.StatusOK, 4, "Accept-Ranges", "bytes", "Content-Length", "10")

	if err := consume(store, tok); err != nil {
		t.Fatalf("plain retry: %v", err)
	}
	release(store, tok, http.StatusOK, 10, "Accept-Ranges", "bytes", "Content-Length", "10")
	if err := consume(store, tok); !errors.Is(err, downloadutil.ErrInvalidToken) {
		t.Errorf("retry after the file completed: got %v, want ErrInvalidToken", err)
	}
}

func TestConsumeTokenRefusesARetryAfterTheIdleWindow(t *testing.T) {
	store, clock := newStore()
	tok := issue(t, store)
	if err := consume(store, tok); err != nil {
		t.Fatalf("first request: %v", err)
	}
	release(store, tok, http.StatusOK, 4, "Accept-Ranges", "bytes", "Content-Length", "10")
	clock.t = clock.t.Add(downloadutil.DefaultIdleWindow + time.Second)

	if err := consume(store, tok); !errors.Is(err, downloadutil.ErrInvalidToken) {
		t.Errorf("got %v, want ErrInvalidToken", err)
	}
}

// TestConsumeTokenIdleWindowStartsWhenTheResponseEnds verifies a download
// that streams for longer than the idle window can still be resumed: the
// window is measured from the end of the last response, not its start.
func TestConsumeTokenIdleWindowStartsWhenTheResponseEnds(t *testing.T) {
	store, clock := newStore()
	tok := issue(t, store)
	if err := consume(store, tok); err != nil {
		t.Fatalf("first request: %v", err)
	}
	clock.t = clock.t.Add(2 * downloadutil.DefaultIdleWindow)
	issue(t, store) // sweeps, and must not take the token in use
	release(store, tok, http.StatusOK, 4, "Accept-Ranges", "bytes", "Content-Length", "10")
	clock.t = clock.t.Add(downloadutil.DefaultIdleWindow - time.Second)

	if err := consume(store, tok); err != nil {
		t.Errorf("Range retry: %v", err)
	}
}

// TestReleaseTokenEndsTheDownload covers every response that ends a token: one
// that delivered the rest of the file, and one that cannot be resumed at all.
func TestReleaseTokenEndsTheDownload(t *testing.T) {
	for name, tc := range map[string]struct {
		status  int
		written int64
		header  []string
	}{
		"whole file":       {http.StatusOK, 10, []string{"Accept-Ranges", "bytes", "Content-Length", "10"}},
		"range to the end": {http.StatusPartialContent, 6, []string{"Accept-Ranges", "bytes", "Content-Range", "bytes 4-9/10"}},
		"folder zip":       {http.StatusOK, 4, nil},
		"archive entry":    {http.StatusOK, 4, []string{"Content-Length", "10"}},
		"error":            {http.StatusNotFound, 20, nil},
	} {
		t.Run(name, func(t *testing.T) {
			store, _ := newStore()
			tok := issue(t, store)
			if err := consume(store, tok); err != nil {
				t.Fatalf("first request: %v", err)
			}
			release(store, tok, tc.status, tc.written, tc.header...)
			if err := consume(store, tok); !errors.Is(err, downloadutil.ErrInvalidToken) {
				t.Errorf("Range retry: got %v, want ErrInvalidToken", err)
			}
		})
	}
}

// TestReleaseTokenKeepsAnInterruptedZip covers Firefox's Cancel then Retry on
// a folder: the zip cannot be resumed, but one that was cut off keeps its
// token, so the plain retry gets a fresh zip instead of a 401.
func TestReleaseTokenKeepsAnInterruptedZip(t *testing.T) {
	store, _ := newStore()
	tok := issue(t, store)
	if err := consume(store, tok); err != nil {
		t.Fatalf("first request: %v", err)
	}
	store.ReleaseToken(downloadutil.ReleaseTokenParams{
		Token: tok, Status: http.StatusOK, Header: http.Header{}, Written: 4, Interrupted: true,
	})
	if err := consume(store, tok); err != nil {
		t.Errorf("retry after an interrupted zip: %v", err)
	}
}

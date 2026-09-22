package downloadutil_test

import (
	"errors"
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

func TestConsumeTokenWorksOnce(t *testing.T) {
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
	if _, err := store.ConsumeToken(params); !errors.Is(err, downloadutil.ErrInvalidToken) {
		t.Errorf("second consume: got %v, want ErrInvalidToken", err)
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

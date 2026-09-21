//go:build chaos

package chaos

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"testing"
)

// TestOversizedLoginBody posts an Anna Karenina–scale JSON body to the public
// login endpoint. Expected: graceful 4xx/413/429 or transport failure — not a
// 5xx storm / hang beyond the client timeout.
func TestOversizedLoginBody(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)

	size := oversizeBytes()
	prose := generateLargeText(size)
	payload, err := json.Marshal(map[string]string{
		"username": prose,
		"password": prose,
	})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	t.Logf("POST /api/v0/auth/login with ~%d byte JSON body", len(payload))

	r := c.exchange(http.MethodPost, "/api/v0/auth/login", payload, map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "oversized login", r, false)
}

// TestOversizedRecoverBody exercises another public JSON auth path with a huge
// recoveryPhrase field.
func TestOversizedRecoverBody(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)

	prose := generateLargeText(oversizeBytes())
	payload, err := json.Marshal(map[string]string{
		"username":       "stress-user",
		"recoveryPhrase": prose,
		"newPassword":    "x",
	})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	t.Logf("POST /api/v0/auth/recover with ~%d byte JSON body", len(payload))

	r := c.exchange(http.MethodPost, "/api/v0/auth/recover", payload, map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "oversized recover", r, false)
}

// TestOversizedSearchQuery hits authenticated search with a very long query
// string when credentials are available; otherwise skips.
func TestOversizedSearchQuery(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	c.ensureSession(t)

	// Keep URL under common proxy limits while still being "huge" for a query.
	q := generateLargeText(32 << 10) // 32 KiB
	path := "/api/v0/files/search?query=" + url.QueryEscape(q)
	t.Logf("GET files/search with ~%d char query", len(q))

	r := c.exchange(http.MethodGet, path, nil, nil)
	assertGraceful(t, "oversized search query", r, false)
}

// TestOversizedContentSearch similarly hammers FTS content search.
func TestOversizedContentSearch(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	c.ensureSession(t)

	q := generateLargeText(16 << 10)
	path := "/api/v0/files/search/content?q=" + url.QueryEscape(q)
	t.Logf("GET files/search/content with ~%d char q", len(q))

	r := c.exchange(http.MethodGet, path, nil, nil)
	assertGraceful(t, "oversized content search", r, false)
}

// TestOversizedRawBody posts a non-JSON multi-megabyte body with a JSON content
// type to login — parsers should reject without 5xx.
func TestOversizedRawBody(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)

	raw := []byte(generateLargeText(oversizeBytes()))
	t.Logf("POST /api/v0/auth/login with %d bytes of raw prose as body", len(raw))

	r := c.exchange(http.MethodPost, "/api/v0/auth/login", raw, map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "oversized raw body", r, false)
}

// TestOversizedAlbumName posts a huge album name when authenticated.
func TestOversizedAlbumName(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	c.ensureSession(t)

	name := generateLargeText(256 << 10) // 256 KiB name
	payload, err := json.Marshal(map[string]string{"name": name})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	t.Logf("POST /api/v0/albums with ~%d byte name", len(name))

	resp, err := c.do(http.MethodPost, "/api/v0/albums", bytes.NewReader(payload), map[string]string{
		"Content-Type": "application/json",
	})
	if err != nil {
		assertGraceful(t, "oversized album name", result{err: err}, false)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		// The server accepted the name; delete the album so reruns start clean.
		var created struct {
			ID int64 `json:"id"`
		}
		if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&created); err == nil && created.ID != 0 {
			t.Cleanup(func() {
				r := c.exchange(http.MethodDelete, fmt.Sprintf("/api/v0/albums/%d", created.ID), nil, nil)
				if r.err != nil || r.status >= 300 {
					t.Logf("cleanup: deleting album %d: status=%d err=%v", created.ID, r.status, r.err)
				}
			})
		}
	}
	// Creating may succeed or reject; either is fine if not a 5xx storm.
	assertGraceful(t, "oversized album name", result{status: resp.StatusCode}, false)
}

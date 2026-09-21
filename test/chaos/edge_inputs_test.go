//go:build chaos

package chaos

import (
	"encoding/json"
	"net/http"
	"net/url"
	"testing"
)

// Edge-input cases: empty, whitespace, and long unicode where the API accepts
// strings. Expect 4xx (or empty success), never 5xx storms.

func TestEdgeLoginEmptyBody(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	r := c.exchange(http.MethodPost, "/api/v0/auth/login", []byte{}, map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "empty login body", r, false)
}

func TestEdgeLoginWhitespaceCredentials(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	payload, _ := json.Marshal(map[string]string{
		"username": "   \t\n  ",
		"password": "   ",
	})
	r := c.exchange(http.MethodPost, "/api/v0/auth/login", payload, map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "whitespace login", r, false)
}

func TestEdgeLoginUnicodeCredentials(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	// Mixed scripts + combining marks + emoji via escapes (keeps cspell quiet).
	username := "user\u7528\u6237\u65e5\u672c\u8a9e\u0627\u0644\u0639\u0631\u0628\u064a\u0629\U0001F1FA\U0001F1E6\u0301\u200B"
	password := "pass\u043f\u0430\u0440\u043e\u043b\u044c\U0001F510\xef\xbb\xbf" // trailing byte order mark
	payload, _ := json.Marshal(map[string]string{
		"username": username,
		"password": password,
	})
	r := c.exchange(http.MethodPost, "/api/v0/auth/login", payload, map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "unicode login", r, false)
}

func TestEdgeLoginMalformedJSON(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	r := c.exchange(http.MethodPost, "/api/v0/auth/login", []byte(`{"username":`), map[string]string{
		"Content-Type": "application/json",
	})
	assertGraceful(t, "malformed JSON login", r, false)
}

func TestEdgeAuthStatusWeirdAccept(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	r := c.exchange(http.MethodGet, "/api/v0/auth/status", nil, map[string]string{
		"Accept":          "text/html, application/xml;q=0.9, */*;q=0.1",
		"Accept-Language": "xx-QQ, zz;q=0",
		"X-Forwarded-For": "😄, not-an-ip",
	})
	assertGraceful(t, "weird headers on status", r, false)
	if r.err == nil && r.status != http.StatusOK {
		t.Fatalf("auth/status should remain 200 under weird Accept headers, got %d", r.status)
	}
}

func TestEdgeSearchEmptyAndWhitespace(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	c.ensureSession(t)

	cases := []struct {
		name string
		path string
	}{
		{"empty query", "/api/v0/files/search?query="},
		{"whitespace query", "/api/v0/files/search?query=" + url.QueryEscape("   \t  ")},
		{"empty content q", "/api/v0/files/search/content?q="},
		{"whitespace content q", "/api/v0/files/search/content?q=" + url.QueryEscape("  ")},
		{"unicode content q", "/api/v0/files/search/content?q=" + url.QueryEscape("\U0001F4F7 \u691c\u7d22 \u0442\u0435\u0441\u0442")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := c.exchange(http.MethodGet, tc.path, nil, nil)
			assertGraceful(t, tc.name, r, false)
		})
	}
}

// TestEdgeProtectedWithoutAuth needs a backend that has finished
// /api/v0/auth/setup: before setup the auth middleware lets every /api route
// through. make test/chaos/local runs setup first.
func TestEdgeProtectedWithoutAuth(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	if !c.setupComplete(t) {
		t.Skip("backend has not run /api/v0/auth/setup, so no route is protected yet; run `make test/chaos/local` or finish setup first")
	}
	// Explicitly clear any env-provided auth for this case.
	c.token, c.cookie, c.user, c.pass = "", "", "", ""

	for _, path := range []string{
		"/api/v0/files",
		"/api/v0/health",
		"/api/v0/version",
		"/api/v0/photos",
	} {
		t.Run(path, func(t *testing.T) {
			r := c.exchange(http.MethodGet, path, nil, nil)
			if r.err != nil {
				t.Fatalf("%s: %v", path, r.err)
			}
			if r.status != http.StatusUnauthorized {
				t.Fatalf("%s: want 401 without auth, got %d", path, r.status)
			}
		})
	}
}

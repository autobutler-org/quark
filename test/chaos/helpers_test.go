//go:build chaos

package chaos

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	defaultBaseURL       = "http://127.0.0.1:8080"
	defaultTimeout       = 30 * time.Second
	defaultOversizeBytes = 2 << 20 // ~2 MiB — Anna Karenina–scale text generated at runtime
	defaultConcurrency   = 32
	defaultBursts        = 8
	// max5xxFraction is the fraction of responses that may be 5xx before a
	// concurrent burst is considered a resilience failure.
	max5xxFraction = 0.10
)

// sharedSession holds a token/cookie obtained once in TestMain when
// credentials are configured. Authenticated cases reuse it so a later
// invalid-login rate-limit burst cannot poison ensureSession logins.
var sharedSession struct {
	mu     sync.RWMutex
	token  string
	cookie string
}

// TestMain warms a shared auth session before any test runs. Login-burst
// cases are expected to trip 429 on /auth/login; that must not break
// authenticated cases that already hold a session.
func TestMain(m *testing.M) {
	if err := warmSharedSession(); err != nil {
		log.Printf("stress: shared session warm-up skipped: %v", err)
	}
	os.Exit(m.Run())
}

func warmSharedSession() error {
	token := env("QUARK_ACCESS_TOKEN", "QUARK_TOKEN")
	if token != "" {
		sharedSession.mu.Lock()
		sharedSession.token = token
		sharedSession.mu.Unlock()
		return nil
	}
	user := env("QUARK_USER", "QUARK_USERNAME")
	pass := env("QUARK_PASSWORD")
	if user == "" || pass == "" {
		return nil // no credentials; auth cases will skip
	}
	c := &client{
		http: &http.Client{
			Timeout: requestTimeout(),
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
		base: baseURL(),
		user: user,
		pass: pass,
	}
	tok, cookie, err := c.loginWithRetry(6)
	if err != nil {
		return err
	}
	sharedSession.mu.Lock()
	sharedSession.token = tok
	sharedSession.cookie = cookie
	sharedSession.mu.Unlock()
	log.Printf("stress: warmed shared session for authenticated cases (token=%v cookie=%v)", tok != "", cookie != "")
	return nil
}

func applySharedSession(c *client) {
	sharedSession.mu.RLock()
	defer sharedSession.mu.RUnlock()
	if c.token == "" && sharedSession.token != "" {
		c.token = sharedSession.token
	}
	if c.cookie == "" && sharedSession.cookie != "" {
		c.cookie = sharedSession.cookie
	}
}

// env picks the first non-empty value among keys.
func env(keys ...string) string {
	for _, k := range keys {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
	}
	return ""
}

func baseURL() string {
	if v := env("QUARK_BASE_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	return defaultBaseURL
}

func requestTimeout() time.Duration {
	if v := env("QUARK_STRESS_TIMEOUT"); v != "" {
		d, err := time.ParseDuration(v)
		if err == nil && d > 0 {
			return d
		}
	}
	return defaultTimeout
}

func oversizeBytes() int {
	if v := env("QUARK_STRESS_OVERSIZE_BYTES"); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil && n > 0 {
			return n
		}
	}
	return defaultOversizeBytes
}

func concurrency() int {
	if v := env("QUARK_STRESS_CONCURRENCY"); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil && n > 0 {
			return n
		}
	}
	return defaultConcurrency
}

func bursts() int {
	if v := env("QUARK_STRESS_BURSTS"); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil && n > 0 {
			return n
		}
	}
	return defaultBursts
}

type client struct {
	http   *http.Client
	base   string
	token  string
	user   string
	pass   string
	cookie string
}

func newClient(t *testing.T) *client {
	t.Helper()
	c := &client{
		http: &http.Client{
			Timeout: requestTimeout(),
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
		base:  baseURL(),
		token: env("QUARK_ACCESS_TOKEN", "QUARK_TOKEN"),
		user:  env("QUARK_USER", "QUARK_USERNAME"),
		pass:  env("QUARK_PASSWORD"),
	}
	applySharedSession(c)
	return c
}

// requireBackend fails the test when /api/v0/auth/status is unreachable, so a
// backend that never started cannot pass as a run of skipped tests.
func (c *client) requireBackend(t *testing.T) {
	t.Helper()
	resp, err := c.do(http.MethodGet, "/api/v0/auth/status", nil, nil)
	if err != nil {
		t.Fatalf("backend unreachable at %s (%v); start with `make watch/backend` or `quark serve`", c.base, err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body) //nolint:errcheck
}

// setupComplete reports whether /api/v0/auth/status says setup has run.
func (c *client) setupComplete(t *testing.T) bool {
	t.Helper()
	resp, err := c.do(http.MethodGet, "/api/v0/auth/status", nil, nil)
	if err != nil {
		t.Fatalf("auth/status: %v", err)
	}
	defer resp.Body.Close()
	var status struct {
		Setup bool `json:"setup"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&status); err != nil {
		t.Fatalf("auth/status: decode: %v", err)
	}
	return status.Setup
}

func (c *client) hasAuth() bool {
	return c.token != "" || (c.user != "" && c.pass != "")
}

// ensureSession logs in when credentials are set and no token/cookie yet.
// Prefers the TestMain-warmed shared session so authenticated cases do not
// depend on surviving a prior invalid-login 429 burst. Skips when auth is
// unset. Retries with backoff if login still returns 429.
func (c *client) ensureSession(t *testing.T) {
	t.Helper()
	applySharedSession(c)
	if c.token != "" || c.cookie != "" {
		return
	}
	if c.user == "" || c.pass == "" {
		t.Skip("QUARK_USER/QUARK_PASSWORD or QUARK_ACCESS_TOKEN unset; skipping authenticated case")
	}
	tok, cookie, err := c.loginWithRetry(8)
	if err != nil {
		t.Fatalf("login failed after retries: %v", err)
	}
	c.token, c.cookie = tok, cookie
	// Publish for later tests in this process (best-effort).
	sharedSession.mu.Lock()
	if sharedSession.token == "" && tok != "" {
		sharedSession.token = tok
	}
	if sharedSession.cookie == "" && cookie != "" {
		sharedSession.cookie = cookie
	}
	sharedSession.mu.Unlock()
}

// loginWithRetry POSTs valid credentials, backing off on 429 (auth rate limit).
// Product rate limiting is expected after invalid-login bursts; the suite must
// wait rather than treat 429 as a hard harness failure.
func (c *client) loginWithRetry(maxAttempts int) (token, cookie string, err error) {
	if maxAttempts < 1 {
		maxAttempts = 1
	}
	body, _ := json.Marshal(map[string]string{
		"username": c.user,
		"password": c.pass,
	})
	var lastStatus int
	var lastBody string
	backoff := 200 * time.Millisecond
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		payload := bytes.NewReader(body)
		resp, reqErr := c.do(http.MethodPost, "/api/v0/auth/login", payload, map[string]string{
			"Content-Type": "application/json",
		})
		if reqErr != nil {
			err = fmt.Errorf("login request failed: %w", reqErr)
			return "", "", err
		}
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		resp.Body.Close()
		lastStatus = resp.StatusCode
		lastBody = truncate(string(raw), 200)
		if resp.StatusCode == http.StatusTooManyRequests {
			if attempt == maxAttempts {
				break
			}
			time.Sleep(backoff)
			if backoff < 4*time.Second {
				backoff *= 2
			}
			continue
		}
		if resp.StatusCode != http.StatusOK {
			return "", "", fmt.Errorf("login returned %d: %s", resp.StatusCode, lastBody)
		}
		for _, ck := range resp.Cookies() {
			if ck.Name == "session" && ck.Value != "" {
				cookie = ck.Value
				break
			}
		}
		var parsed struct {
			Data struct {
				Token string `json:"token"`
			} `json:"data"`
			Token string `json:"token"`
		}
		_ = json.Unmarshal(raw, &parsed)
		if parsed.Data.Token != "" {
			token = parsed.Data.Token
		} else if parsed.Token != "" {
			token = parsed.Token
		}
		if token == "" && cookie == "" {
			return "", "", fmt.Errorf("login succeeded but no token or session cookie returned")
		}
		return token, cookie, nil
	}
	return "", "", fmt.Errorf("login still rate-limited after %d attempts (last %d: %s)", maxAttempts, lastStatus, lastBody)
}

func (c *client) do(method, path string, body io.Reader, headers map[string]string) (*http.Response, error) {
	req, err := http.NewRequest(method, c.base+path, body)
	if err != nil {
		return nil, err
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if c.token != "" && req.Header.Get("Authorization") == "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	if c.cookie != "" {
		req.AddCookie(&http.Cookie{Name: "session", Value: c.cookie})
	}
	return c.http.Do(req)
}

type result struct {
	status int
	err    error
}

func (c *client) exchange(method, path string, body []byte, headers map[string]string) result {
	var r io.Reader
	if body != nil {
		r = bytes.NewReader(body)
	}
	resp, err := c.do(method, path, r, headers)
	if err != nil {
		return result{err: err}
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, io.LimitReader(resp.Body, 8<<20)) //nolint:errcheck
	return result{status: resp.StatusCode}
}

// assertGraceful documents that status (or transport error) is an acceptable
// defensive outcome for chaos inputs: client/timeout/reset, 2xx, or 4xx is
// fine. A 404 fails, because it means the route is gone and the case tested
// nothing.
func assertGraceful(t *testing.T, label string, r result, allow5xx bool) {
	t.Helper()
	if r.err != nil {
		// Timeouts, connection resets, and unexpected EOF are acceptable under
		// oversized/burst load — the server refused or dropped without hanging
		// the suite forever (client timeout bounds the wait).
		t.Logf("%s: transport error (acceptable under stress): %v", label, r.err)
		return
	}
	code := r.status
	switch {
	case code == http.StatusNotFound:
		t.Fatalf("%s: got 404; the route is missing, so this case tested nothing", label)
	case code >= 200 && code < 500:
		return
	case allow5xx && code >= 500 && code < 600:
		t.Logf("%s: got %d (logged; allowed for this case)", label, code)
		return
	case code >= 500:
		t.Fatalf("%s: unexpected server error %d (want graceful 2xx/4xx/413/429 or transport fail)", label, code)
	default:
		t.Fatalf("%s: unexpected status %d", label, code)
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// generateLargeText builds ~size bytes of printable prose at runtime so we
// never commit a novel-sized fixture. Pattern is intentionally boring.
func generateLargeText(size int) string {
	const chunk = "All happy families are alike; each unhappy family is unhappy in its own way. "
	var b strings.Builder
	b.Grow(size + len(chunk))
	for b.Len() < size {
		b.WriteString(chunk)
	}
	return b.String()[:size]
}

type statusHist struct {
	mu  sync.Mutex
	n   map[int]int
	err int
}

func newStatusHist() *statusHist {
	return &statusHist{n: make(map[int]int)}
}

func (h *statusHist) add(r result) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if r.err != nil {
		h.err++
		return
	}
	h.n[r.status]++
}

func (h *statusHist) total() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	sum := h.err
	for _, c := range h.n {
		sum += c
	}
	return sum
}

func (h *statusHist) count5xx() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	sum := 0
	for code, c := range h.n {
		if code >= 500 && code < 600 {
			sum += c
		}
	}
	return sum
}

// assertBurst fails a burst that collected nothing, hit a missing route, or
// saw more than max5xxFraction server errors.
func (h *statusHist) assertBurst(t *testing.T, label string) {
	t.Helper()
	total := h.total()
	five := h.count5xx()
	t.Logf("%s: total=%d hist=[%s]", label, total, h.summary())
	if total == 0 {
		t.Fatalf("%s: no responses collected", label)
	}
	h.mu.Lock()
	notFound := h.n[http.StatusNotFound]
	h.mu.Unlock()
	if notFound > 0 {
		t.Fatalf("%s: %d responses were 404; a route in the burst is missing", label, notFound)
	}
	if float64(five)/float64(total) > max5xxFraction {
		t.Fatalf("%s: 5xx storm: %d/%d exceeded %.0f%% threshold", label, five, total, 100*max5xxFraction)
	}
}

func (h *statusHist) summary() string {
	h.mu.Lock()
	defer h.mu.Unlock()
	var parts []string
	if h.err > 0 {
		parts = append(parts, fmt.Sprintf("transport_err=%d", h.err))
	}
	for code, c := range h.n {
		parts = append(parts, fmt.Sprintf("%d=%d", code, c))
	}
	return strings.Join(parts, " ")
}

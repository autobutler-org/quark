package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// usersJSON is `headscale users list -o json` from v0.28: encoding/json over
// the generated structs, so IDs are numbers and timestamps are objects.
const usersJSON = `[
	{"id": 3, "name": "someone-else"},
	{"id": 7, "name": "quark", "created_at": {"seconds": 1767225600}}
]`

// keyJSON is `headscale preauthkeys create -o json` from v0.28.
const keyJSON = `{"user": {"id": 7, "name": "quark"}, "id": 12, "key": "hskey-auth-abc", "expiration": {"seconds": 1767229200}}`

// fakeCLI answers the two headscale commands the service runs with canned
// output, and fails the test on any other command line.
func fakeCLI(t *testing.T, users string) {
	t.Helper()
	prior := runHeadscale
	t.Cleanup(func() { runHeadscale = prior })
	runHeadscale = func(_ context.Context, args ...string) ([]byte, error) {
		switch strings.Join(args, " ") {
		case "users list -o json":
			return []byte(users), nil
		case "preauthkeys create --user 7 --expiration 1h -o json":
			return []byte(keyJSON), nil
		default:
			t.Errorf("unexpected headscale command: %q", args)
			return nil, errors.New("unexpected command")
		}
	}
}

// setup configures the service and clears the rate limiter.
func setup(t *testing.T, users string) {
	t.Helper()
	fakeCLI(t, users)
	headscaleUser = "quark"
	sharedSecret = "shared"
	keyExpiry = time.Hour
	rateMu.Lock()
	rateStore = make(map[string]*rateLimitEntry)
	rateMu.Unlock()
}

func provision(secret, deviceID, remoteAddr, realIP string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/provision", strings.NewReader(`{"device_id":"`+deviceID+`"}`))
	req.RemoteAddr = remoteAddr
	req.Header.Set("X-Provisioning-Secret", secret)
	if realIP != "" {
		req.Header.Set("X-Real-IP", realIP)
	}
	w := httptest.NewRecorder()
	handleProvision(w, req)
	return w
}

func TestProvision_MintsKeyForResolvedUserID(t *testing.T) {
	setup(t, usersJSON)

	w := provision("shared", "device-1", "203.0.113.5:4000", "")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d; want 200: %s", w.Code, w.Body.String())
	}
	var resp provisionResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil || resp.AuthKey != "hskey-auth-abc" {
		t.Errorf("response = %s; want auth_key hskey-auth-abc", w.Body.String())
	}
}

func TestProvision_UnknownUserFails(t *testing.T) {
	for name, users := range map[string]string{
		"other users only": `[{"id": 3, "name": "someone-else"}]`,
		"no users":         `null`,
	} {
		t.Run(name, func(t *testing.T) {
			setup(t, users)
			if _, err := createPreAuthKey(context.Background()); err == nil || !strings.Contains(err.Error(), "headscale users create quark") {
				t.Errorf("createPreAuthKey() = %v; want an error saying how to create the user", err)
			}
			if w := provision("shared", "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusInternalServerError {
				t.Errorf("status = %d; want 500", w.Code)
			}
		})
	}
}

func TestCreatePreAuthKey_CLIFailure(t *testing.T) {
	setup(t, usersJSON)
	runHeadscale = func(context.Context, ...string) ([]byte, error) {
		return nil, errors.New("headscale users list failed (stderr is in the log): exit status 1")
	}
	if _, err := createPreAuthKey(context.Background()); err == nil || !strings.Contains(err.Error(), "exit status 1") {
		t.Errorf("createPreAuthKey() = %v; want the CLI failure", err)
	}
	if w := provision("shared", "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusInternalServerError {
		t.Errorf("status = %d; want 500", w.Code)
	}
}

// TestCreatePreAuthKey_UnparsableKeepsKeyOutOfError verifies a create whose
// output does not parse fails without echoing that output, which may hold a
// key, into the error the handler logs.
func TestCreatePreAuthKey_UnparsableKeepsKeyOutOfError(t *testing.T) {
	setup(t, usersJSON)
	runHeadscale = func(_ context.Context, args ...string) ([]byte, error) {
		if args[0] == "users" {
			return []byte(usersJSON), nil
		}
		return []byte(`hskey-auth-leaked not json`), nil
	}
	_, err := createPreAuthKey(context.Background())
	if err == nil || strings.Contains(err.Error(), "hskey-auth-leaked") {
		t.Errorf("createPreAuthKey() = %v; want an error without the output", err)
	}
}

// TestRunHeadscale_RealProcess runs the real exec path against stand-in
// binaries: stdout is returned, and a non-zero exit or a missing binary is an
// error rather than a panic.
func TestRunHeadscale_RealProcess(t *testing.T) {
	prior := headscaleBin
	t.Cleanup(func() { headscaleBin = prior })

	headscaleBin = "echo"
	out, err := runHeadscale(context.Background(), "users", "list")
	if err != nil || strings.TrimSpace(string(out)) != "users list" {
		t.Errorf("runHeadscale(echo) = %q, %v; want the args echoed", out, err)
	}

	headscaleBin = "false"
	if _, err := runHeadscale(context.Background(), "users", "list"); err == nil || !strings.Contains(err.Error(), "headscale users list failed") {
		t.Errorf("runHeadscale(false) = %v; want a failure naming the command", err)
	}

	headscaleBin = "/nonexistent/headscale"
	if _, err := runHeadscale(context.Background(), "users", "list"); err == nil {
		t.Error("runHeadscale(missing binary) = nil error; want one")
	}
}

func TestCappedBuffer(t *testing.T) {
	b := &cappedBuffer{max: 3}
	for _, chunk := range []string{"ab", "xyz", "gh"} {
		if n, err := b.Write([]byte(chunk)); n != len(chunk) || err != nil {
			t.Fatalf("Write(%q) = %d, %v; want every byte accepted", chunk, n, err)
		}
	}
	if b.buf.String() != "abx" || !b.overflow {
		t.Errorf("buffer = %q, overflow %v; want abx and overflow", b.buf.String(), b.overflow)
	}
}

func TestProvision_RejectsWrongSecret(t *testing.T) {
	setup(t, usersJSON)

	for _, secret := range []string{"", "wrong"} {
		if w := provision(secret, "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusUnauthorized {
			t.Errorf("secret %q: status = %d; want 401", secret, w.Code)
		}
	}
}

func TestProvision_RateLimitsPerDevice(t *testing.T) {
	setup(t, usersJSON)

	for i := range maxRequestsPerHour {
		if w := provision("shared", "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusOK {
			t.Fatalf("request %d: status = %d; want 200", i+1, w.Code)
		}
	}
	if w := provision("shared", "device-1", "203.0.113.5:4000", ""); w.Code != http.StatusTooManyRequests {
		t.Errorf("request over the limit: status = %d; want 429", w.Code)
	}
}

// TestProvision_RateLimitsPerClientBehindProxy verifies that behind nginx on
// loopback each quark gets its own IP bucket from X-Real-IP, and that the
// header is ignored from a non-loopback peer, which could otherwise forge it.
func TestProvision_RateLimitsPerClientBehindProxy(t *testing.T) {
	setup(t, usersJSON)

	for i := range maxRequestsPerHour {
		if w := provision("shared", fmt.Sprintf("device-a%d", i), "127.0.0.1:5000", "198.51.100.1"); w.Code != http.StatusOK {
			t.Fatalf("request %d: status = %d; want 200", i+1, w.Code)
		}
	}
	if w := provision("shared", "device-b", "127.0.0.1:5000", "198.51.100.2"); w.Code != http.StatusOK {
		t.Errorf("a second client behind the proxy was limited: status = %d; want 200", w.Code)
	}
	if w := provision("shared", "device-c", "127.0.0.1:5000", "198.51.100.1"); w.Code != http.StatusTooManyRequests {
		t.Errorf("the first client over its limit: status = %d; want 429", w.Code)
	}
}

func TestClientIP(t *testing.T) {
	cases := []struct {
		name, remoteAddr, realIP, want string
	}{
		{"direct peer", "203.0.113.5:4000", "", "203.0.113.5"},
		{"direct peer forging the header", "203.0.113.5:4000", "198.51.100.1", "203.0.113.5"},
		{"loopback proxy", "127.0.0.1:4000", "198.51.100.1", "198.51.100.1"},
		{"ipv6 loopback proxy", "[::1]:4000", "198.51.100.1", "198.51.100.1"},
		{"loopback without the header", "127.0.0.1:4000", "", "127.0.0.1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/provision", nil)
			req.RemoteAddr = tc.remoteAddr
			if tc.realIP != "" {
				req.Header.Set("X-Real-IP", tc.realIP)
			}
			if got := clientIP(req); got != tc.want {
				t.Errorf("clientIP() = %q; want %q", got, tc.want)
			}
		})
	}
}

func TestParseKeyExpiry(t *testing.T) {
	cases := []struct {
		in      string
		want    time.Duration
		wantErr bool
	}{
		{"", time.Hour, false},
		{"1", time.Hour, false},
		{"24", 24 * time.Hour, false},
		{"0", 0, true},
		{"-3", 0, true},
		{"1h", 0, true},
		{"soon", 0, true},
	}
	for _, tc := range cases {
		got, err := parseKeyExpiry(tc.in)
		if (err != nil) != tc.wantErr || got != tc.want {
			t.Errorf("parseKeyExpiry(%q) = %v, %v; want %v, error %v", tc.in, got, err, tc.want, tc.wantErr)
		}
	}
}

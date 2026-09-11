// Command provisioning mints single-use Headscale pre-auth keys for quarks that
// POST /provision with the shared secret (#1876). It runs on the Headscale VM
// as the headscale user and shells out to the local headscale CLI, which talks
// to the server over its unix socket, so no Headscale API key is involved.
//
// Environment:
//
//	PROVISIONING_SECRET            required; matches QUARK_PROVISIONING_SECRET in quark releases
//	HEADSCALE_USER                 user keys are minted for (default quark)
//	HEADSCALE_BIN                  headscale CLI (default headscale, looked up on PATH)
//	PROVISIONING_LISTEN_ADDR       listen address (default :8081)
//	PROVISIONING_KEY_EXPIRY_HOURS  key lifetime in whole hours (default 1)
package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	// headscaleBin is the headscale CLI. The service runs on the Headscale VM
	// as the headscale user, so the CLI reaches the server over its unix
	// socket and needs no API key.
	headscaleBin string
	// headscaleUser is the Headscale user every key is minted for.
	headscaleUser string
	sharedSecret  string
	keyExpiry     time.Duration
)

const (
	// maxRequestBytes caps a /provision body; a real one is a 64-char device ID.
	maxRequestBytes = 1024
	// maxCLIOutputBytes caps what is kept of the CLI's stdout and stderr.
	maxCLIOutputBytes = 64 * 1024
	// cliTimeout bounds both CLI calls a key takes, so a wedged headscale
	// fails the request instead of piling up processes.
	cliTimeout = 15 * time.Second
)

type provisionRequest struct {
	DeviceID string `json:"device_id"`
}

type provisionResponse struct {
	AuthKey string `json:"auth_key"`
}

type errorResponse struct {
	Error string `json:"error"`
}

// rateLimitEntry tracks timestamps for both device ID and IP rate limiting.
type rateLimitEntry struct {
	Timestamps []time.Time
}

var (
	rateMu    sync.Mutex
	rateStore = make(map[string]*rateLimitEntry)
	// lastPrune tracks when we last swept stale entries from rateStore.
	lastPrune time.Time
)

const (
	maxRequestsPerHour = 5
	pruneInterval      = 10 * time.Minute
)

// pruneRateStore removes entries that have had no activity in the past hour.
// Must be called with rateMu held.
func pruneRateStore(now time.Time) {
	if now.Sub(lastPrune) < pruneInterval {
		return
	}
	cutoff := now.Add(-1 * time.Hour)
	for key, entry := range rateStore {
		active := false
		for _, t := range entry.Timestamps {
			if t.After(cutoff) {
				active = true
				break
			}
		}
		if !active {
			delete(rateStore, key)
		}
	}
	lastPrune = now
}

// checkRateLimit returns true if the request should be allowed, false if rate-limited.
// It rate-limits by both source IP and device_id, taking the stricter result.
// Both keys are checked before any timestamps are recorded to avoid partial updates
// when one key is over limit and the other is not.
func checkRateLimit(sourceIP, deviceID string) bool {
	rateMu.Lock()
	defer rateMu.Unlock()

	now := time.Now()
	cutoff := now.Add(-1 * time.Hour)

	pruneRateStore(now)

	keys := []string{"ip:" + sourceIP, "device:" + deviceID}
	filtered := make([][]time.Time, len(keys))

	for i, key := range keys {
		entry, ok := rateStore[key]
		if !ok {
			filtered[i] = []time.Time{}
			continue
		}
		f := make([]time.Time, 0, len(entry.Timestamps))
		for _, t := range entry.Timestamps {
			if t.After(cutoff) {
				f = append(f, t)
			}
		}
		filtered[i] = f
		if len(f) >= maxRequestsPerHour {
			entry.Timestamps = f
			return false
		}
	}

	for i, key := range keys {
		entry, ok := rateStore[key]
		if !ok {
			rateStore[key] = &rateLimitEntry{Timestamps: append(filtered[i], now)}
			continue
		}
		entry.Timestamps = append(filtered[i], now)
	}

	return true
}

// headscaleUserJSON and headscalePreAuthKeyJSON are the parts of the CLI's
// `-o json` output the service reads. The CLI marshals the generated protobuf
// structs with encoding/json, not protojson: field names are the proto names,
// and uint64 IDs are JSON numbers.
type headscaleUserJSON struct {
	ID   uint64 `json:"id"`
	Name string `json:"name"`
}

type headscalePreAuthKeyJSON struct {
	Key string `json:"key"`
}

// runHeadscale runs the headscale CLI with args, without a shell, and returns
// its stdout. Stderr goes to the log. It is a var so tests can answer with
// canned output instead of a real headscale.
var runHeadscale = func(ctx context.Context, args ...string) ([]byte, error) {
	name := strings.Join(args[:min(2, len(args))], " ")
	cmd := exec.CommandContext(ctx, headscaleBin, args...)
	stdout := &cappedBuffer{max: maxCLIOutputBytes}
	stderr := &cappedBuffer{max: maxCLIOutputBytes}
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	err := cmd.Run()
	if stderr.buf.Len() > 0 {
		log.Printf("headscale %s: stderr: %s", name, bytes.TrimSpace(stderr.buf.Bytes()))
	}
	if errors.Is(err, exec.ErrNotFound) {
		return nil, fmt.Errorf("headscale CLI not found at %q; install headscale or set HEADSCALE_BIN", headscaleBin)
	}
	if err != nil {
		return nil, fmt.Errorf("headscale %s failed (stderr is in the log): %w", name, err)
	}
	if stdout.overflow {
		return nil, fmt.Errorf("headscale %s printed over %d bytes", name, maxCLIOutputBytes)
	}
	return stdout.buf.Bytes(), nil
}

// cappedBuffer keeps the first max bytes written to it and drops the rest, so
// a runaway CLI cannot grow the service's heap.
type cappedBuffer struct {
	buf      bytes.Buffer
	max      int
	overflow bool
}

func (b *cappedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	if room := b.max - b.buf.Len(); n > room {
		b.overflow = true
		p = p[:max(room, 0)]
	}
	b.buf.Write(p)
	// Report every byte taken: a short count would make exec fail the copy.
	return n, nil
}

// resolveUserID looks up headscaleUser's numeric ID, which is what
// `preauthkeys create --user` takes in Headscale v0.28.
func resolveUserID(ctx context.Context) (uint64, error) {
	out, err := runHeadscale(ctx, "users", "list", "-o", "json")
	if err != nil {
		return 0, err
	}
	var users []headscaleUserJSON
	if err := json.Unmarshal(out, &users); err != nil {
		return 0, fmt.Errorf("parse `headscale users list` output: %w", err)
	}
	for _, u := range users {
		if u.Name == headscaleUser && u.ID != 0 {
			return u.ID, nil
		}
	}
	return 0, fmt.Errorf("headscale user %q does not exist; create it with `headscale users create %s`, or set HEADSCALE_USER", headscaleUser, headscaleUser)
}

// createPreAuthKey mints a single-use, non-ephemeral key for headscaleUser.
// The key is never logged: it is not in any error, and only stderr is.
func createPreAuthKey(ctx context.Context) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, cliTimeout)
	defer cancel()

	userID, err := resolveUserID(ctx)
	if err != nil {
		return "", err
	}
	out, err := runHeadscale(ctx,
		"preauthkeys", "create",
		"--user", strconv.FormatUint(userID, 10),
		"--expiration", fmt.Sprintf("%dh", int(keyExpiry/time.Hour)),
		"-o", "json",
	)
	if err != nil {
		return "", err
	}
	var key headscalePreAuthKeyJSON
	if err := json.Unmarshal(out, &key); err != nil {
		// Not %w and not the output: the output may hold the key.
		return "", errors.New("could not parse `headscale preauthkeys create` output as JSON")
	}
	if key.Key == "" {
		return "", errors.New("`headscale preauthkeys create` returned no key")
	}
	return key.Key, nil
}

// clientIP is the address the rate limiter counts against. Behind nginx on
// loopback every request arrives from 127.0.0.1, which would put every quark
// in one bucket, so X-Real-IP is used then. It is ignored from anywhere else,
// where a caller could set it to dodge the limit.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() {
		if forwarded := strings.TrimSpace(r.Header.Get("X-Real-IP")); forwarded != "" {
			return forwarded
		}
	}
	return host
}

// parseKeyExpiry reads PROVISIONING_KEY_EXPIRY_HOURS as whole hours. Empty
// means one hour.
func parseKeyExpiry(hours string) (time.Duration, error) {
	if hours == "" {
		return time.Hour, nil
	}
	n, err := strconv.Atoi(hours)
	if err != nil || n <= 0 {
		return 0, fmt.Errorf("PROVISIONING_KEY_EXPIRY_HOURS must be a whole number of hours above zero, got %q", hours)
	}
	return time.Duration(n) * time.Hour, nil
}

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// writeJSON sends v as the JSON response body. The status line is already on the
// wire by the time encoding can fail, so a failure can only be logged.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("failed to write response: %v", err)
	}
}

func handleProvision(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	// Authenticate caller via shared secret (constant-time to prevent timing attacks).
	provided := r.Header.Get("X-Provisioning-Secret")
	if subtle.ConstantTimeCompare([]byte(provided), []byte(sharedSecret)) != 1 {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "unauthorized"})
		return
	}

	var req provisionRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRequestBytes)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}

	if req.DeviceID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "device_id is required"})
		return
	}

	if !checkRateLimit(clientIP(r), req.DeviceID) {
		writeJSON(w, http.StatusTooManyRequests, errorResponse{Error: "rate limit exceeded, max 5 requests per hour"})
		return
	}

	key, err := createPreAuthKey(r.Context())
	if err != nil {
		log.Printf("failed to create pre-auth key: %v", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to provision key"})
		return
	}

	writeJSON(w, http.StatusOK, provisionResponse{AuthKey: key})
}

func main() {
	headscaleUser = envOr("HEADSCALE_USER", "quark")
	headscaleBin = envOr("HEADSCALE_BIN", "headscale")
	if _, err := exec.LookPath(headscaleBin); err != nil {
		log.Fatalf("headscale CLI not found at %q; install headscale or set HEADSCALE_BIN to its path", headscaleBin)
	}

	sharedSecret = os.Getenv("PROVISIONING_SECRET")
	if sharedSecret == "" {
		log.Fatal("PROVISIONING_SECRET environment variable is required; it must match the QUARK_PROVISIONING_SECRET quark releases are built with")
	}

	var err error
	keyExpiry, err = parseKeyExpiry(os.Getenv("PROVISIONING_KEY_EXPIRY_HOURS"))
	if err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/provision", handleProvision)

	addr := envOr("PROVISIONING_LISTEN_ADDR", ":8081")
	log.Printf("provisioning service listening on %s, minting keys for headscale user %q", addr, headscaleUser)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

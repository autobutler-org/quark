//go:build stress

package stress

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/autobutler-org/quark/pkg/util/authutil"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

// config is the run, read from the environment so the Makefile target and a
// hand run against a dev backend use the same knobs.
type config struct {
	base      string
	adminUser string
	adminPass string
	// levels are the simulated client counts, run in order against the same
	// server.
	levels   []int
	duration time.Duration
	// poll is the app's auto-refresh interval (15 s by default in the app).
	poll time.Duration
	// accounts is how many member accounts the clients are spread over. Each
	// one's auth key is an Argon2id run here, so this stays far below the
	// client count.
	accounts int
	// uploadersPer100 clients upload one small file into uploadDir every
	// uploadEvery.
	uploadersPer100 int
	uploadEvery     time.Duration
	uploadDir       string
	// pid is the server's process, sampled for RSS and threads when set.
	pid    int
	report string
}

func loadConfig() (config, error) {
	cfg := config{
		base:            strings.TrimRight(envOr("QUARK_BASE_URL", "http://127.0.0.1:8080"), "/"),
		adminUser:       os.Getenv("QUARK_USER"),
		adminPass:       os.Getenv("QUARK_PASSWORD"),
		duration:        durationEnv("STRESS_DURATION", 30*time.Second),
		poll:            durationEnv("STRESS_POLL", 15*time.Second),
		accounts:        intEnv("STRESS_ACCOUNTS", 20),
		uploadersPer100: intEnv("STRESS_UPLOADERS_PER_100", 1),
		uploadEvery:     durationEnv("STRESS_UPLOAD_EVERY", 5*time.Second),
		uploadDir:       envOr("STRESS_UPLOAD_DIR", "groups/everyone"),
		pid:             intEnv("QUARK_PID", 0),
		report:          os.Getenv("STRESS_REPORT"),
	}
	for _, field := range strings.Split(envOr("STRESS_USERS", "100,500,2000"), ",") {
		n, err := strconv.Atoi(strings.TrimSpace(field))
		if err != nil || n < 1 {
			return cfg, fmt.Errorf("STRESS_USERS: %q is not a positive count", field)
		}
		cfg.levels = append(cfg.levels, n)
	}
	if cfg.adminUser == "" || cfg.adminPass == "" {
		return cfg, errors.New("QUARK_USER and QUARK_PASSWORD must name an admin account")
	}
	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func intEnv(key string, fallback int) int {
	n, err := strconv.Atoi(envOr(key, strconv.Itoa(fallback)))
	if err != nil {
		return fallback
	}
	return n
}

func durationEnv(key string, fallback time.Duration) time.Duration {
	d, err := time.ParseDuration(envOr(key, fallback.String()))
	if err != nil || d <= 0 {
		return fallback
	}
	return d
}

// account is a signed-in member whose session several clients share. The
// server's per-request cost is the same whichever session a request carries.
type account struct {
	username string
	token    string
}

// api is the harness's own client for setup: creating and signing in
// accounts. Simulated clients each get their own transport instead.
type api struct {
	base string
	http *http.Client
}

func (a api) postJSON(path, token string, body any) (int, []byte, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return 0, nil, err
	}
	req, err := http.NewRequest(http.MethodPost, a.base+path, bytes.NewReader(encoded))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := a.http.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return resp.StatusCode, raw, err
}

// awaitLimiter runs call until it is not answered 429, waiting out the per-IP
// auth limiter: every account here asks from loopback.
func awaitLimiter(call func() (int, []byte, error)) (int, []byte, error) {
	backoff := 250 * time.Millisecond
	for attempt := 0; ; attempt++ {
		status, raw, err := call()
		if err != nil || status != http.StatusTooManyRequests || attempt == 11 {
			return status, raw, err
		}
		time.Sleep(backoff)
		backoff = min(2*backoff, 4*time.Second)
	}
}

// authKey is the key the Quark takes in password's place (#2430): the
// account's salt from GET /auth/salt, and authutil.DeriveKey over the password
// with it, the derivation quark auth-key runs (#2713).
func (a api) authKey(username, password string) (string, error) {
	status, raw, err := awaitLimiter(func() (int, []byte, error) {
		resp, err := a.http.Get(a.base + "/api/v0/auth/salt?username=" + url.QueryEscape(username))
		if err != nil {
			return 0, nil, err
		}
		defer resp.Body.Close()
		raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		return resp.StatusCode, raw, err
	})
	if err != nil {
		return "", err
	}
	var answer struct {
		Salt string `json:"salt"`
	}
	if err := json.Unmarshal(raw, &answer); err != nil || status != http.StatusOK {
		return "", fmt.Errorf("salt for %s: %d %s", username, status, raw)
	}
	result, err := authutil.DeriveKey(authutil.DeriveKeyParams{Secret: password, Salt: answer.Salt})
	return result.Key, err
}

// login signs in with an auth key.
func (a api) login(username, authKey string) (string, error) {
	status, raw, err := awaitLimiter(func() (int, []byte, error) {
		return a.postJSON("/api/v0/auth/login", "", map[string]string{"username": username, "authKey": authKey})
	})
	if err != nil {
		return "", err
	}
	if status != http.StatusOK {
		return "", fmt.Errorf("login %s: %d %s", username, status, raw)
	}
	var parsed struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil || parsed.Token == "" {
		return "", fmt.Errorf("login %s: no token in %s", username, raw)
	}
	return parsed.Token, nil
}

// ensureAccounts creates the member accounts, or reuses them on a rerun, and
// signs each in once.
func ensureAccounts(a api, adminToken string, n int) ([]account, error) {
	const password = "stress-member-password"
	accounts := make([]account, 0, n)
	for i := 0; i < n; i++ {
		username := fmt.Sprintf("stress%03d", i)
		authKey, err := a.authKey(username, password)
		if err != nil {
			return nil, err
		}
		status, raw, err := a.postJSON("/api/v0/admin/users", adminToken, map[string]string{"username": username, "authKey": authKey})
		if err != nil {
			return nil, err
		}
		if status != http.StatusCreated && status != http.StatusConflict {
			return nil, fmt.Errorf("create %s: %d %s", username, status, raw)
		}
		token, err := a.login(username, authKey)
		if err != nil {
			return nil, err
		}
		accounts = append(accounts, account{username: username, token: token})
	}
	return accounts, nil
}

// routeStats is what one route answered during a level.
type routeStats struct {
	latencies []time.Duration
	statuses  map[int]int
	failures  int
}

// recorder collects every request of a level. A run of a few thousand clients
// makes tens of thousands of requests, so keeping each latency is cheap.
type recorder struct {
	mu     sync.Mutex
	routes map[string]*routeStats
}

func newRecorder() *recorder { return &recorder{routes: map[string]*routeStats{}} }

func (r *recorder) observe(route string, status int, elapsed time.Duration, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	stats, ok := r.routes[route]
	if !ok {
		stats = &routeStats{statuses: map[int]int{}}
		r.routes[route] = stats
	}
	if err != nil {
		stats.failures++
		return
	}
	stats.statuses[status]++
	stats.latencies = append(stats.latencies, elapsed)
}

// client is one simulated app instance: one browser tab or phone.
type client struct {
	cfg     config
	account account
	http    *http.Client
	agent   string
	rec     *recorder
	counts  *levelCounts

	// lastDevices is when the devices status was last fetched; the app caches
	// it for 10 s (StorageService._deviceCacheTtl).
	lastDevices time.Time
	// owed is a refresh asked for while one was running or inside the 1 s
	// debounce, as AutoRefreshMixin.manualRefresh does.
	owed chan struct{}
	bg   sync.WaitGroup
}

// levelCounts are the level's totals that are not per route.
type levelCounts struct {
	socketsOpen     atomic.Int64
	socketsPeak     atomic.Int64
	socketFailures  atomic.Int64
	socketDrops     atomic.Int64
	eventsReceived  atomic.Int64
	uploadEvents    atomic.Int64
	uploadsOK       atomic.Int64
	refreshes       atomic.Int64
	eventRefreshAsk atomic.Int64
	// waiting is requests sent and not yet answered; what is left when the
	// level ends is how far behind the server fell.
	waiting atomic.Int64
}

func newClient(cfg config, acct account, id int, rec *recorder, counts *levelCounts) *client {
	return &client{
		cfg:     cfg,
		account: acct,
		// dart:io's HttpClient: a 15 s idle timeout and, by default, no
		// per-host cap; a browser holds 6.
		http: &http.Client{
			Timeout: 60 * time.Second,
			Transport: &http.Transport{
				MaxIdleConnsPerHost: 6,
				IdleConnTimeout:     15 * time.Second,
			},
		},
		// A distinct agent per client, so connected_devices grows the way it
		// does with real devices.
		agent:  fmt.Sprintf("quark-stress/%d", id),
		rec:    rec,
		counts: counts,
		owed:   make(chan struct{}, 1),
	}
}

func (c *client) get(ctx context.Context, route, path string) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.cfg.base+path, nil)
	if err != nil {
		return
	}
	c.send(ctx, route, req)
}

func (c *client) send(ctx context.Context, route string, req *http.Request) {
	req.Header.Set("Authorization", "Bearer "+c.account.token)
	req.Header.Set("User-Agent", c.agent)
	started := time.Now()
	c.counts.waiting.Add(1)
	resp, err := c.http.Do(req)
	defer c.counts.waiting.Add(-1)
	if err != nil {
		// The level ending cancels whatever is in flight; that is not the
		// server's failure.
		if ctx.Err() == nil {
			c.rec.observe(route, 0, 0, err)
		}
		return
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	c.rec.observe(route, resp.StatusCode, time.Since(started), nil)
	if route == "upload" && resp.StatusCode/100 == 2 {
		c.counts.uploadsOK.Add(1)
	}
}

// refresh is FileBrowserPage.refresh: health and shared roots on their own,
// the devices status (cached 10 s), then the listing and the recent strip.
func (c *client) refresh(ctx context.Context) {
	c.counts.refreshes.Add(1)
	c.bg.Add(2)
	go func() { defer c.bg.Done(); c.get(ctx, "health", "/api/v0/health") }()
	go func() { defer c.bg.Done(); c.get(ctx, "access/mine", "/api/v0/access/mine") }()
	if time.Since(c.lastDevices) >= 10*time.Second {
		c.get(ctx, "storage/devices/status", "/api/v0/storage/devices/status")
		c.lastDevices = time.Now()
	}
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		c.get(ctx, "files (list home)", "/api/v0/files?rootDir="+url.QueryEscape("users/"+c.account.username))
	}()
	go func() { defer wg.Done(); c.get(ctx, "files/recent", "/api/v0/files/recent?limit=20") }()
	wg.Wait()
}

// pollLoop is AutoRefreshMixin: a refresh at start, one per poll interval, and
// owed ones from events, never two within a second and never two at once.
func (c *client) pollLoop(ctx context.Context) {
	// Real clients do not tick in lockstep.
	ticker := time.NewTicker(c.cfg.poll + time.Duration(rand.Int64N(int64(c.cfg.poll/10)+1)))
	defer ticker.Stop()
	var lastStart time.Time
	for {
		if wait := time.Second - time.Since(lastStart); wait > 0 {
			select {
			case <-ctx.Done():
				return
			case <-time.After(wait):
			}
		}
		lastStart = time.Now()
		c.refresh(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-c.owed:
		}
	}
}

// eventLoop holds the events socket, asks for a refresh on every listing
// event as the Files page does, and reconnects after 2 s when dropped.
func (c *client) eventLoop(ctx context.Context) {
	wsURL := strings.Replace(c.cfg.base, "http", "ws", 1) + "/api/v0/events?token=" + url.QueryEscape(c.account.token)
	for ctx.Err() == nil {
		dialCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		conn, _, err := websocket.Dial(dialCtx, wsURL, &websocket.DialOptions{
			HTTPHeader: http.Header{"User-Agent": []string{c.agent}},
		})
		cancel()
		if err != nil {
			if ctx.Err() == nil {
				c.counts.socketFailures.Add(1)
			}
		} else {
			open := c.counts.socketsOpen.Add(1)
			for {
				peak := c.counts.socketsPeak.Load()
				if open <= peak || c.counts.socketsPeak.CompareAndSwap(peak, open) {
					break
				}
			}
			c.readEvents(ctx, conn)
			c.counts.socketsOpen.Add(-1)
			_ = conn.CloseNow()
			if ctx.Err() == nil {
				c.counts.socketDrops.Add(1)
			}
		}
		select {
		case <-ctx.Done():
		case <-time.After(2 * time.Second):
		}
	}
}

func (c *client) readEvents(ctx context.Context, conn *websocket.Conn) {
	for {
		var evt struct {
			Kind string `json:"kind"`
		}
		if err := wsjson.Read(ctx, conn, &evt); err != nil {
			return
		}
		c.counts.eventsReceived.Add(1)
		switch evt.Kind {
		case "upload":
			c.counts.uploadEvents.Add(1)
			fallthrough
		case "delete", "move", "new_folder", "access_changed":
			c.counts.eventRefreshAsk.Add(1)
			select {
			case c.owed <- struct{}{}:
			default:
			}
		}
	}
}

// uploadLoop puts a small file into the shared folder every uploadEvery.
func (c *client) uploadLoop(ctx context.Context, id int) {
	payload := bytes.Repeat([]byte("q"), 4<<10)
	for n := 0; ; n++ {
		jitter := time.Duration(rand.Int64N(int64(c.cfg.uploadEvery/2) + 1))
		select {
		case <-ctx.Done():
			return
		case <-time.After(c.cfg.uploadEvery/2 + jitter):
		}
		var body bytes.Buffer
		form := multipart.NewWriter(&body)
		part, err := form.CreateFormFile("files", fmt.Sprintf("stress-%d-%d.txt", id, n))
		if err != nil {
			return
		}
		_, _ = part.Write(payload)
		_ = form.Close()
		req, err := http.NewRequestWithContext(ctx, http.MethodPost,
			c.cfg.base+"/api/v0/files/upload/"+c.cfg.uploadDir+"?keepBoth=true", &body)
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", form.FormDataContentType())
		c.send(ctx, "upload", req)
	}
}

// sampleProcess reads the server's resident memory and thread count from
// /proc once a second and keeps the peaks.
func sampleProcess(ctx context.Context, pid int, peakRSSKiB, peakThreads *atomic.Int64) {
	if pid == 0 {
		return
	}
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		raw, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", pid))
		if err == nil {
			for _, line := range strings.Split(string(raw), "\n") {
				fields := strings.Fields(line)
				if len(fields) < 2 {
					continue
				}
				value, _ := strconv.ParseInt(fields[1], 10, 64)
				switch fields[0] {
				case "VmRSS:":
					storeMax(peakRSSKiB, value)
				case "Threads:":
					storeMax(peakThreads, value)
				}
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func storeMax(peak *atomic.Int64, value int64) {
	for {
		current := peak.Load()
		if value <= current || peak.CompareAndSwap(current, value) {
			return
		}
	}
}

func percentile(sorted []time.Duration, p float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	return sorted[min(len(sorted)-1, int(float64(len(sorted))*p))]
}

// summarize renders a level as Markdown, the form capacity.md quotes.
func summarize(n int, elapsed time.Duration, rec *recorder, counts *levelCounts, waiting, peakRSSKiB, peakThreads int64) string {
	var out strings.Builder
	fmt.Fprintf(&out, "\n### %d clients, %s\n\n", n, elapsed.Round(time.Second))
	out.WriteString("| Route | Requests | req/s | p50 | p95 | p99 | max | Non-2xx | Transport errors |\n")
	out.WriteString("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |\n")
	names := make([]string, 0, len(rec.routes))
	for name := range rec.routes {
		names = append(names, name)
	}
	sort.Strings(names)
	var total, failed int
	for _, name := range names {
		stats := rec.routes[name]
		sort.Slice(stats.latencies, func(i, j int) bool { return stats.latencies[i] < stats.latencies[j] })
		var bad []string
		for status, count := range stats.statuses {
			if status/100 != 2 {
				bad = append(bad, fmt.Sprintf("%d×%d", count, status))
				failed += count
			}
		}
		sort.Strings(bad)
		count := len(stats.latencies)
		total += count + stats.failures
		failed += stats.failures
		fmt.Fprintf(&out, "| %s | %d | %.1f | %s | %s | %s | %s | %s | %d |\n",
			name, count, float64(count)/elapsed.Seconds(),
			ms(percentile(stats.latencies, 0.50)), ms(percentile(stats.latencies, 0.95)),
			ms(percentile(stats.latencies, 0.99)), ms(percentile(stats.latencies, 1)),
			strings.Join(bad, ", "), stats.failures)
	}
	uploads := counts.uploadsOK.Load()
	fmt.Fprintf(&out, "\nTotal %d requests (%.1f req/s), %d failed or non-2xx. "+
		"Sockets: peak %d open, %d failed to open, %d dropped by the server. "+
		"%d requests still waiting when the level ended. "+
		"Events received: %d. Refreshes: %d (%d asked for by events). "+
		"Uploads: %d; upload events delivered: %d of %d possible (%.0f%%).",
		total, float64(total)/elapsed.Seconds(), failed,
		counts.socketsPeak.Load(), counts.socketFailures.Load(), counts.socketDrops.Load(),
		waiting, counts.eventsReceived.Load(), counts.refreshes.Load(), counts.eventRefreshAsk.Load(),
		uploads, counts.uploadEvents.Load(), uploads*int64(n), deliveryPercent(counts.uploadEvents.Load(), uploads*int64(n)))
	if peakRSSKiB > 0 {
		fmt.Fprintf(&out, " Server peak RSS %.0f MiB, %d threads.", float64(peakRSSKiB)/1024, peakThreads)
	}
	out.WriteString("\n")
	return out.String()
}

func deliveryPercent(delivered, possible int64) float64 {
	if possible == 0 {
		return 100
	}
	return 100 * float64(delivered) / float64(possible)
}

func ms(d time.Duration) string {
	return fmt.Sprintf("%.0f ms", float64(d)/float64(time.Millisecond))
}

// awaitIdle waits, up to a minute, until the server answers the status route
// within a second, so one level's backlog does not land on the next.
func awaitIdle(base string) {
	probe := &http.Client{Timeout: time.Second}
	deadline := time.Now().Add(time.Minute)
	for time.Now().Before(deadline) {
		resp, err := probe.Get(base + "/api/v0/auth/status")
		if err == nil {
			_, _ = io.Copy(io.Discard, resp.Body)
			_ = resp.Body.Close()
			return
		}
		time.Sleep(time.Second)
	}
}

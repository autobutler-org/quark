//go:build multiinstance

package multiinstance

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

const (
	adminUser     = "admin"
	adminPassword = "multi-instance-admin-password"
)

// knownBroken marks a case that fails until issue lands. It skips while the
// case fails and fails once it passes, so the marker cannot outlive the fix:
// the pull request that fixes the case removes the marker, and from then on a
// regression fails CI.
func knownBroken(t *testing.T, issue int, err error) {
	t.Helper()
	if err != nil {
		t.Skipf("known broken until #%d: %v", issue, err)
	}
	t.Fatalf("now passes: remove the knownBroken(#%d) marker so a regression fails CI", issue)
}

// binary is the build under test. The Makefile passes an absolute path; the
// default is ./build/quark seen from this package's directory.
func binary(t *testing.T) string {
	t.Helper()
	path := os.Getenv("QUARK_BINARY")
	if path == "" {
		path = "../../build/quark"
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(abs); err != nil {
		t.Fatalf("no Quark binary at %s (%v). Run `make build/backend`, or set QUARK_BINARY", abs, err)
	}
	return abs
}

// instance is one `quark serve` process with a data directory of its own,
// whose files directory is a symlink to the cluster's shared one. The access
// checks resolve the files root with filepath.EvalSymlinks, so the link stands
// in for a shared mount.
type instance struct {
	name string
	home string
	port int
	cmd  *exec.Cmd
	done chan struct{}
}

func (in *instance) url() string { return "http://127.0.0.1:" + strconv.Itoa(in.port) }

func (in *instance) logPath() string { return filepath.Join(in.home, "server.log") }

// stop signals the process and waits for it to exit, killing it after 30 s.
func (in *instance) stop(sig os.Signal) {
	if in.cmd == nil || in.cmd.Process == nil {
		return
	}
	_ = in.cmd.Process.Signal(sig)
	select {
	case <-in.done:
	case <-time.After(30 * time.Second):
		_ = in.cmd.Process.Kill()
		<-in.done
	}
}

// cluster is the instances, the database and files directory they share, and
// the load balancer in front of them.
type cluster struct {
	t         *testing.T
	dbURL     string
	shared    string
	instances []*instance
	lb        *balancer
	admin     string
}

// newCluster starts n instances of bin one after another, puts a balancer in
// front of them, and sets the install up with an admin account.
func newCluster(t *testing.T, n int, bin string) *cluster {
	t.Helper()
	c := &cluster{t: t, dbURL: dbtest.PostgresURL(t), shared: filepath.Join(t.TempDir(), "files")}
	if err := os.MkdirAll(c.shared, 0o755); err != nil {
		t.Fatal(err)
	}
	c.lb = newBalancer(t)
	t.Cleanup(func() {
		for _, in := range c.instances {
			in.stop(syscall.SIGKILL)
		}
		if t.Failed() {
			for _, in := range c.instances {
				logTail(t, in)
			}
		}
	})
	for i := range n {
		c.add(fmt.Sprintf("q%d", i), bin)
	}
	c.admin = c.setup()
	return c
}

// add starts a new instance and puts it behind the balancer.
func (c *cluster) add(name, bin string) *instance {
	c.t.Helper()
	home := c.t.TempDir()
	// storageutil.GetDataDirForDevice's choice for a user that is not quark.
	dataDir := filepath.Join(home, "quark", "data")
	if runtime.GOOS == "darwin" {
		dataDir = filepath.Join(home, "Library", "Application Support", "Quark", "data")
	}
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		c.t.Fatal(err)
	}
	if err := os.Symlink(c.shared, filepath.Join(dataDir, "files")); err != nil {
		c.t.Fatal(err)
	}
	in := &instance{name: name, home: home, port: freePort(c.t)}
	c.instances = append(c.instances, in)
	c.start(in, bin)
	c.lb.add(in.url())
	return in
}

// start runs bin as in and waits until it answers.
func (c *cluster) start(in *instance, bin string) {
	c.t.Helper()
	logFile, err := os.OpenFile(in.logPath(), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		c.t.Fatal(err)
	}
	cmd := exec.Command(bin, "serve")
	cmd.Env = append(os.Environ(),
		"HOME="+in.home,
		"PORT="+strconv.Itoa(in.port),
		"HTTPS_PORT=",
		"QUARK_INSECURE=true",
		"GIN_MODE=release",
		"QUARK_DB_BACKEND=postgres",
		"QUARK_DATABASE_URL="+c.dbURL,
	)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		c.t.Fatalf("start %s: %v", in.name, err)
	}
	done := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		_ = logFile.Close()
		close(done)
	}()
	in.cmd, in.done = cmd, done
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-done:
			logTail(c.t, in)
			c.t.Fatalf("%s exited before it answered", in.name)
		default:
		}
		if healthy(in.url()) {
			return
		}
		time.Sleep(250 * time.Millisecond)
	}
	logTail(c.t, in)
	c.t.Fatalf("%s did not answer on %s within 90s", in.name, in.url())
}

// restart stops in gracefully and starts bin in its place, on the same data
// directory and port.
func (c *cluster) restart(in *instance, bin string) {
	c.t.Helper()
	in.stop(syscall.SIGTERM)
	c.start(in, bin)
}

func logTail(t *testing.T, in *instance) {
	t.Helper()
	raw, err := os.ReadFile(in.logPath())
	if err != nil {
		return
	}
	lines := strings.Split(strings.TrimRight(string(raw), "\n"), "\n")
	t.Logf("last lines of %s's log:\n%s", in.name, strings.Join(lines[max(0, len(lines)-40):], "\n"))
}

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func healthy(base string) bool {
	resp, err := (&http.Client{Timeout: time.Second}).Get(base + "/api/v0/auth/status")
	if err != nil {
		return false
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// balancer is round-robin with no affinity over the backends that answered
// their last health check, the way a cloud load balancer behaves. Websockets
// pass through httputil.ReverseProxy as upgrades.
type balancer struct {
	mu       sync.Mutex
	backends []*backend
	next     atomic.Uint64
	server   *httptest.Server
}

type backend struct {
	target  *url.URL
	healthy atomic.Bool
	hits    atomic.Int64
}

func newBalancer(t *testing.T) *balancer {
	lb := &balancer{}
	proxy := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(lb.pick())
			r.SetXForwarded()
		},
		ErrorHandler: func(w http.ResponseWriter, _ *http.Request, err error) {
			http.Error(w, err.Error(), http.StatusBadGateway)
		},
	}
	lb.server = httptest.NewServer(proxy)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(func() {
		cancel()
		lb.server.Close()
	})
	go lb.check(ctx)
	return lb
}

func (lb *balancer) url() string { return lb.server.URL }

func (lb *balancer) add(raw string) {
	target, _ := url.Parse(raw)
	b := &backend{target: target}
	b.healthy.Store(true)
	lb.mu.Lock()
	defer lb.mu.Unlock()
	lb.backends = append(lb.backends, b)
}

// pick takes the next healthy backend, or the next one at all when none is.
func (lb *balancer) pick() *url.URL {
	lb.mu.Lock()
	defer lb.mu.Unlock()
	n := uint64(len(lb.backends))
	start := lb.next.Add(1)
	for i := range n {
		if b := lb.backends[(start+i)%n]; b.healthy.Load() {
			b.hits.Add(1)
			return b.target
		}
	}
	b := lb.backends[start%n]
	b.hits.Add(1)
	return b.target
}

// check health-checks every backend four times a second.
func (lb *balancer) check(ctx context.Context) {
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		lb.mu.Lock()
		backends := append([]*backend(nil), lb.backends...)
		lb.mu.Unlock()
		for _, b := range backends {
			b.healthy.Store(healthy(b.target.String()))
		}
	}
}

// response is one exchange's outcome.
type response struct {
	status int
	header http.Header
	body   []byte
}

var httpClient = &http.Client{Timeout: 30 * time.Second}

// call sends one request. Bodies here are small and bounded by the test.
func call(method, rawURL, token string, body []byte, header map[string]string) (response, error) {
	req, err := http.NewRequest(method, rawURL, bytes.NewReader(body))
	if err != nil {
		return response{}, err
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for k, v := range header {
		req.Header.Set(k, v)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return response{}, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	return response{status: resp.StatusCode, header: resp.Header, body: raw}, err
}

func callJSON(method, rawURL, token string, in, out any) (response, error) {
	encoded, err := json.Marshal(in)
	if err != nil {
		return response{}, err
	}
	r, err := call(method, rawURL, token, encoded, map[string]string{"Content-Type": "application/json"})
	if err != nil || out == nil || r.status/100 != 2 {
		return r, err
	}
	return r, json.Unmarshal(r.body, out)
}

// authKey is what the Quark takes in a password's place (#2430): the salt
// from GET /auth/salt and authutil.DeriveKey over the password.
func authKey(t *testing.T, base, username, password string) string {
	t.Helper()
	r, err := call(http.MethodGet, base+"/api/v0/auth/salt?username="+url.QueryEscape(username), "", nil, nil)
	if err != nil || r.status != http.StatusOK {
		t.Fatalf("salt for %s: %v %d %s", username, err, r.status, r.body)
	}
	var answer struct {
		Salt string `json:"salt"`
	}
	if err := json.Unmarshal(r.body, &answer); err != nil {
		t.Fatal(err)
	}
	key, err := authutil.DeriveKey(authutil.DeriveKeyParams{Secret: password, Salt: answer.Salt})
	if err != nil {
		t.Fatal(err)
	}
	return key.Key
}

type tokenAnswer struct {
	Token string `json:"token"`
}

// setup creates the admin account through the first instance and returns
// its session token.
func (c *cluster) setup() string {
	c.t.Helper()
	base := c.instances[0].url()
	var answer tokenAnswer
	r, err := callJSON(http.MethodPost, base+"/api/v0/auth/setup", "",
		map[string]string{"username": adminUser, "authKey": authKey(c.t, base, adminUser, adminPassword)}, &answer)
	if err != nil || r.status/100 != 2 || answer.Token == "" {
		c.t.Fatalf("setup: %v %d %s", err, r.status, r.body)
	}
	return answer.Token
}

// member creates an account through base and returns its id and auth key.
func (c *cluster) member(base, username, password string) (int64, string) {
	c.t.Helper()
	key := authKey(c.t, base, username, password)
	var created struct {
		ID int64 `json:"id"`
	}
	r, err := callJSON(http.MethodPost, base+"/api/v0/admin/users", c.admin,
		map[string]string{"username": username, "authKey": key}, &created)
	if err != nil || r.status != http.StatusCreated {
		c.t.Fatalf("create %s: %v %d %s", username, err, r.status, r.body)
	}
	return created.ID, key
}

func login(base, username, key string) (response, string, error) {
	var answer tokenAnswer
	r, err := callJSON(http.MethodPost, base+"/api/v0/auth/login", "",
		map[string]string{"username": username, "authKey": key}, &answer)
	return r, answer.Token, err
}

// upload puts one file into dir through base, replacing what is there.
func upload(base, token, dir, name string, content []byte) error {
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	part, err := form.CreateFormFile("files", name)
	if err != nil {
		return err
	}
	if _, err := part.Write(content); err != nil {
		return err
	}
	if err := form.Close(); err != nil {
		return err
	}
	r, err := call(http.MethodPost, base+"/api/v0/files/upload/"+dir+"?overwrite=true", token, body.Bytes(),
		map[string]string{"Content-Type": form.FormDataContentType()})
	if err != nil {
		return err
	}
	if r.status != http.StatusOK {
		return fmt.Errorf("upload %s/%s through %s: %d %s", dir, name, base, r.status, r.body)
	}
	return nil
}

// download reads a file through base, with a bearer token or, when token is
// empty, a download token in query.
func download(base, token, filePath, query string) (response, error) {
	return call(http.MethodGet, base+"/api/v0/files/download?filePath="+url.QueryEscape(filePath)+query, token, nil, nil)
}

// expectFile downloads filePath through base and compares it with want.
func expectFile(base, token, filePath string, want []byte) error {
	r, err := download(base, token, filePath, "")
	if err != nil {
		return err
	}
	if r.status != http.StatusOK {
		return fmt.Errorf("download %s through %s: %d %s", filePath, base, r.status, r.body)
	}
	if !bytes.Equal(r.body, want) {
		return fmt.Errorf("download %s through %s: %d bytes, not the %d written", filePath, base, len(r.body), len(want))
	}
	return nil
}

// eventually retries check every 250 ms until it succeeds or within passes.
func eventually(within time.Duration, check func() error) error {
	deadline := time.Now().Add(within)
	for {
		err := check()
		if err == nil || time.Now().After(deadline) {
			return err
		}
		time.Sleep(250 * time.Millisecond)
	}
}

//go:build multiinstance

package multiinstance

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
)

const home = "users/" + adminUser

// TestSessionsAreShared: a session made on one instance is good on the other,
// and signing out on one ends it on both. Sessions are rows in the shared
// database, so this holds today.
func TestSessionsAreShared(t *testing.T) {
	c := newCluster(t, 2, binary(t))
	a, b := c.instances[0].url(), c.instances[1].url()

	_, key := c.member(a, "alice", "alice-password")
	r, token, err := login(a, "alice", key)
	if err != nil || r.status != http.StatusOK {
		t.Fatalf("login on %s: %v %d %s", a, err, r.status, r.body)
	}
	if r, err := call(http.MethodGet, b+"/api/v0/access/mine", token, nil, nil); err != nil || r.status != http.StatusOK {
		t.Fatalf("a session made on %s, used on %s: %v %d %s", a, b, err, r.status, r.body)
	}
	if r, err := call(http.MethodPost, b+"/api/v0/auth/logout", token, nil, nil); err != nil || r.status/100 != 2 {
		t.Fatalf("logout on %s: %v %d %s", b, err, r.status, r.body)
	}
	if r, err := call(http.MethodGet, a+"/api/v0/access/mine", token, nil, nil); err != nil || r.status != http.StatusUnauthorized {
		t.Fatalf("a session ended on %s, used on %s: %v %d, want 401", b, a, err, r.status)
	}
}

// TestSharedFileWrites (#2968's done-when): two instances writing and reading
// one folder on the shared files directory see no lost writes, no partial
// reads and no staging files left behind. Writes are temp-and-rename beside
// the target, and each instance stages in its own data directory, so this
// holds today.
func TestSharedFileWrites(t *testing.T) {
	c := newCluster(t, 2, binary(t))
	a, b := c.instances[0].url(), c.instances[1].url()

	// Each instance writes its own files at once; each file is read back
	// through the other instance.
	const perInstance = 20
	errs := make(chan error, 2*perInstance)
	var wg sync.WaitGroup
	for i, writer := range []string{a, b} {
		reader := []string{b, a}[i]
		for n := range perInstance {
			wg.Add(1)
			go func() {
				defer wg.Done()
				name := fmt.Sprintf("w%d-%02d.txt", i, n)
				content := []byte(strings.Repeat(name, 1000))
				if err := upload(writer, c.admin, home, name, content); err != nil {
					errs <- err
					return
				}
				errs <- expectFile(reader, c.admin, home+"/"+name, content)
			}()
		}
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Error(err)
		}
	}

	// One instance keeps replacing a file with versions of one repeated byte
	// while the other reads it: every read must be one whole version.
	const size = 256 << 10
	version := func(n int) []byte { return bytes.Repeat([]byte{byte('a' + n%26)}, size) }
	if err := upload(a, c.admin, home, "overwritten.bin", version(0)); err != nil {
		t.Fatal(err)
	}
	var writing atomic.Bool
	writing.Store(true)
	writeErr := make(chan error, 1)
	go func() {
		defer writing.Store(false)
		for n := 1; n <= 30; n++ {
			if err := upload(a, c.admin, home, "overwritten.bin", version(n)); err != nil {
				writeErr <- err
				return
			}
		}
		writeErr <- nil
	}()
	for reads := 0; writing.Load() || reads == 0; reads++ {
		r, err := download(b, c.admin, home+"/overwritten.bin", "")
		if err != nil || r.status != http.StatusOK {
			t.Fatalf("read during overwrites: %v %d %s", err, r.status, r.body)
		}
		if len(r.body) != size || !bytes.Equal(r.body, bytes.Repeat(r.body[:1], size)) {
			t.Fatalf("partial read during overwrites: %d bytes, not one whole version of %d", len(r.body), size)
		}
	}
	if err := <-writeErr; err != nil {
		t.Fatal(err)
	}

	// A write stages beside its target as .vfs-write-*; none may outlive it.
	err := filepath.WalkDir(c.shared, func(path string, d os.DirEntry, err error) error {
		if err == nil && strings.HasPrefix(d.Name(), ".vfs-write-") {
			t.Errorf("staging file left on the share: %s", path)
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
}

type job struct {
	ID       int64  `json:"id"`
	Status   string `json:"status"`
	Attempts int64  `json:"attempts"`
	Error    string `json:"error"`
}

func (j job) finished() bool {
	return j.Status == "completed" || j.Status == "failed" || j.Status == "canceled"
}

func getJob(base, token string, id int64) (job, error) {
	var j job
	r, err := callJSON(http.MethodGet, fmt.Sprintf("%s/api/v0/jobs/%d", base, id), token, nil, &j)
	if err == nil && r.status != http.StatusOK {
		err = fmt.Errorf("job %d through %s: %d %s", id, base, r.status, r.body)
	}
	return j, err
}

// TestJobOwnership (#2966's done-when): starting a second instance leaves a
// running job with its owner, and a job whose owner is killed mid-run is run
// again and finished by another instance once the lease (60 s without a
// heartbeat) runs out.
//
// The rescan is held running by a named pipe in the library: opening it
// blocks until a writer opens it too, so the job stays running for as long as
// the test needs it to and cannot finish before either check.
func TestJobOwnership(t *testing.T) {
	c := newCluster(t, 1, binary(t))
	owner := c.instances[0]

	// The first start queues a rescan of its own; it must be done before the
	// pipe appears, or it would be the job the pipe holds.
	err := eventually(time.Minute, func() error {
		var jobs []job
		r, err := callJSON(http.MethodGet, owner.url()+"/api/v0/jobs?kind=music_rescan", c.admin, nil, &jobs)
		if err == nil && r.status != http.StatusOK {
			err = fmt.Errorf("list the music rescan jobs: %d %s", r.status, r.body)
		}
		if err == nil && len(jobs) == 0 {
			err = fmt.Errorf("the first start has not queued its rescan yet")
		}
		for _, j := range jobs {
			if err == nil && !j.finished() {
				err = fmt.Errorf("the first start's rescan %d is still %s", j.ID, j.Status)
			}
		}
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	pipe := filepath.Join(c.shared, "hold.mp3")
	if err := syscall.Mkfifo(pipe, 0o644); err != nil {
		t.Fatal(err)
	}

	var queued job
	r, err := callJSON(http.MethodPost, owner.url()+"/api/v0/music/rescan", c.admin, struct{}{}, &queued)
	if err != nil || r.status != http.StatusAccepted || queued.ID == 0 {
		t.Fatalf("queue a music rescan on %s: %v %d %s", owner.name, err, r.status, r.body)
	}
	// expect polls the job until it is want or within passes, and fails the
	// test at once if it finishes some other way.
	expect := func(base, want string, within time.Duration) job {
		t.Helper()
		var j job
		err := eventually(within, func() error {
			var err error
			if j, err = getJob(base, c.admin, queued.ID); err != nil {
				return err
			}
			if j.finished() && j.Status != want {
				t.Fatalf("job %d finished %s (%s) while it was meant to be %s", j.ID, j.Status, j.Error, want)
			}
			if j.Status != want {
				return fmt.Errorf("job %d is %s (%s), want %s", j.ID, j.Status, j.Error, want)
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
		return j
	}
	stillRunning := func(base, when string) {
		t.Helper()
		j, err := getJob(base, c.admin, queued.ID)
		if err != nil {
			t.Fatal(err)
		}
		if j.Status != "running" || j.Attempts != 1 {
			t.Fatalf("%s, job %d is %s on attempt %d (%s), want still running on its first",
				when, j.ID, j.Status, j.Attempts, j.Error)
		}
	}
	expect(owner.url(), "running", time.Minute)

	// The late instance's first heartbeat, and the next one, are when it
	// would take or fail a job it does not own.
	late := c.add("late", binary(t))
	for end := time.Now().Add(15 * time.Second); time.Now().Before(end); time.Sleep(time.Second) {
		stillRunning(late.url(), "after "+late.name+" started")
	}

	owner.stop(syscall.SIGKILL)
	stillRunning(late.url(), "right after "+owner.name+" was killed")
	// Let every reader the pipe holds go, the late instance's own startup
	// scan among them, and take the pipe away so the rerun is not held too.
	// Opening a FIFO read-write does not block; the readers read EOF once it
	// is closed.
	hold, err := os.OpenFile(pipe, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(pipe); err != nil {
		t.Fatal(err)
	}
	if err := hold.Close(); err != nil {
		t.Fatal(err)
	}

	// The lease, a heartbeat for the beat that finds it lapsed, and slack.
	j := expect(late.url(), "completed", 2*time.Minute)
	if j.Attempts < 2 {
		t.Fatalf("job %d completed on attempt %d, so no other instance ran it after %s was killed",
			j.ID, j.Attempts, owner.name)
	}
}

// TestEventsCrossInstances (#2965's done-when): a file uploaded through one
// instance appears live on a socket held by the other, and an access change
// made through one takes effect on both.
func TestEventsCrossInstances(t *testing.T) {
	c := newCluster(t, 2, binary(t))
	a, b := c.instances[0].url(), c.instances[1].url()
	memberID, key := c.member(a, "bob", "bob-password")
	_, memberToken, err := login(a, "bob", key)
	if err != nil {
		t.Fatal(err)
	}
	knownBroken(t, 2965, eventsCrossInstances(c, a, b, memberID, memberToken))
}

func eventsCrossInstances(c *cluster, a, b string, memberID int64, memberToken string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, strings.Replace(b, "http", "ws", 1)+"/api/v0/events?token="+url.QueryEscape(c.admin), nil)
	if err != nil {
		return fmt.Errorf("events socket on %s: %w", b, err)
	}
	defer conn.CloseNow()
	seen := make(chan struct{})
	go func() {
		for {
			var evt struct {
				Kind string `json:"kind"`
			}
			if wsjson.Read(ctx, conn, &evt) != nil {
				return
			}
			if evt.Kind == "upload" {
				close(seen)
				return
			}
		}
	}()
	if err := upload(a, c.admin, home, "live.txt", []byte("live")); err != nil {
		return err
	}
	select {
	case <-seen:
	case <-time.After(10 * time.Second):
		return fmt.Errorf("an upload through %s sent no upload event to a socket on %s within 10s", a, b)
	}

	// Bob is refused on b first, so b has loaded his access before the grant.
	shared := home + "/live.txt"
	if r, err := download(b, memberToken, shared, ""); err != nil || r.status == http.StatusOK {
		return fmt.Errorf("bob read %s before it was shared: %v %d", shared, err, r.status)
	}
	r, err := callJSON(http.MethodPut, a+"/api/v0/access", c.admin,
		map[string]any{"relPath": shared, "userId": memberID, "level": "read"}, nil)
	if err != nil || r.status != http.StatusOK {
		return fmt.Errorf("share %s through %s: %v %d %s", shared, a, err, r.status, r.body)
	}
	return eventually(10*time.Second, func() error {
		return expectFile(b, memberToken, shared, []byte("live"))
	})
}

// TestChunkedUploadSplitAcrossInstances (#2967's done-when): a resumable
// upload whose chunks land on alternating instances completes.
func TestChunkedUploadSplitAcrossInstances(t *testing.T) {
	c := newCluster(t, 2, binary(t))
	knownBroken(t, 2967, chunkedUploadSplit(c, c.instances[0].url(), c.instances[1].url()))
}

func chunkedUploadSplit(c *cluster, a, b string) error {
	const chunk = 64 << 10
	content := bytes.Repeat([]byte("chunked!"), 3*chunk/8)
	var session struct {
		SessionID string `json:"sessionId"`
	}
	r, err := callJSON(http.MethodPost, a+"/api/v0/files/upload-session", c.admin,
		map[string]any{"rootDir": home, "fileName": "chunked.bin", "totalSize": len(content)}, &session)
	if err != nil || r.status != http.StatusOK {
		return fmt.Errorf("open a session on %s: %v %d %s", a, err, r.status, r.body)
	}
	for i, base := range []string{a, b, a} {
		start := i * chunk
		end := min(start+chunk, len(content))
		r, err := call(http.MethodPut, base+"/api/v0/files/upload-session/"+session.SessionID, c.admin, content[start:end],
			map[string]string{
				"Content-Type":  "application/octet-stream",
				"Content-Range": fmt.Sprintf("bytes %d-%d/%d", start, end-1, len(content)),
			})
		if err != nil || r.status != http.StatusOK {
			return fmt.Errorf("chunk %d through %s: %v %d %s", i, base, err, r.status, r.body)
		}
	}
	return expectFile(b, c.admin, home+"/chunked.bin", content)
}

// TestDownloadTokenAcrossInstances (#2967's done-when): a download token
// issued by one instance is honored by the other, as a browser link behind a
// load balancer needs.
func TestDownloadTokenAcrossInstances(t *testing.T) {
	c := newCluster(t, 2, binary(t))
	a, b := c.instances[0].url(), c.instances[1].url()
	content := []byte("downloaded through a token")
	if err := upload(a, c.admin, home, "token.txt", content); err != nil {
		t.Fatal(err)
	}
	var issued struct {
		Token string `json:"token"`
	}
	r, err := callJSON(http.MethodPost, a+"/api/v0/files/download-token?filePath="+url.QueryEscape(home+"/token.txt"), c.admin, struct{}{}, &issued)
	if err != nil || r.status != http.StatusOK || issued.Token == "" {
		t.Fatalf("issue a download token on %s: %v %d %s", a, err, r.status, r.body)
	}
	got, err := download(b, "", home+"/token.txt", "&downloadToken="+url.QueryEscape(issued.Token))
	if err == nil && (got.status != http.StatusOK || !bytes.Equal(got.body, content)) {
		err = fmt.Errorf("a token issued by %s, used on %s: %d %s", a, b, got.status, got.body)
	}
	knownBroken(t, 2967, err)
}

// TestLoginLockoutAcrossInstances (#2967's done-when): failures spread over
// two instances lock an account out after as many as one instance allows
// (ratelimitutil.DefaultPairThreshold).
func TestLoginLockoutAcrossInstances(t *testing.T) {
	const threshold = 5
	c := newCluster(t, 2, binary(t))
	a, b := c.instances[0].url(), c.instances[1].url()
	_, key := c.member(a, "carol", "carol-password")
	wrong := authKey(t, a, "carol", "not-carol-password")
	for i := range threshold {
		base := []string{a, b}[i%2]
		r, _, err := login(base, "carol", wrong)
		if err != nil || r.status != http.StatusUnauthorized {
			t.Fatalf("wrong key %d through %s: %v %d %s", i, base, err, r.status, r.body)
		}
		// Stay under the per-address auth rate limit, which answers 429 too.
		time.Sleep(300 * time.Millisecond)
	}
	r, _, err := login(b, "carol", key)
	if err == nil && r.status != http.StatusTooManyRequests {
		err = fmt.Errorf("the right key after %d failures split over two instances: %d, want 429 as on one", threshold, r.status)
	}
	knownBroken(t, 2967, err)
}

// TestRollingUpgrade (#2970's done-when): replacing each instance in turn,
// from the previous release to the build under test, under load through the
// balancer, answers every request.
func TestRollingUpgrade(t *testing.T) {
	previous := os.Getenv("QUARK_PREVIOUS_BINARY")
	if previous == "" {
		t.Skip("QUARK_PREVIOUS_BINARY is unset: point it at the previous release's quark binary " +
			"(CI downloads it from the latest GitHub release)")
	}
	c := newCluster(t, 2, previous)
	next := binary(t)
	knownBroken(t, 2970, rollingUpgrade(c, next))
}

func rollingUpgrade(c *cluster, next string) error {
	ctx, cancel := context.WithCancel(context.Background())
	var mu sync.Mutex
	var failures []string
	var requests atomic.Int64
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for ctx.Err() == nil {
				r, err := call(http.MethodGet, c.lb.url()+"/api/v0/files?rootDir="+url.QueryEscape(home), c.admin, nil, nil)
				requests.Add(1)
				if err != nil || r.status != http.StatusOK {
					mu.Lock()
					failures = append(failures, fmt.Sprintf("%v %d %s", err, r.status, bytes.TrimSpace(r.body)))
					mu.Unlock()
				}
			}
		}()
	}
	for _, in := range c.instances {
		time.Sleep(3 * time.Second)
		c.restart(in, next)
	}
	time.Sleep(3 * time.Second)
	cancel()
	wg.Wait()
	if len(failures) > 0 {
		return fmt.Errorf("%d of %d requests failed during the upgrade, first: %s",
			len(failures), requests.Load(), strings.Join(failures[:min(5, len(failures))], "; "))
	}
	return nil
}

// TestBalancerSpreadsRequests guards the harness itself: with no affinity,
// requests through the balancer reach every instance, so the rolling upgrade
// loads both.
func TestBalancerSpreadsRequests(t *testing.T) {
	c := newCluster(t, 2, binary(t))
	for range 10 {
		r, err := call(http.MethodGet, c.lb.url()+"/api/v0/auth/status", "", nil, nil)
		if err != nil || r.status != http.StatusOK {
			t.Fatalf("status through the balancer: %v %d %s", err, r.status, r.body)
		}
	}
	for _, b := range c.lb.backends {
		if b.hits.Load() == 0 {
			t.Errorf("the balancer sent nothing to %s in 10 requests", b.target)
		}
	}
}

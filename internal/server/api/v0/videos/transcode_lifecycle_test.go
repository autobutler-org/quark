package v0_videos_test

// cspell:words galadriel

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	v0_videos "github.com/autobutler-org/quark/internal/server/api/v0/videos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/transcodeutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
)

// These tests follow a Convert from the formats list to a finished, canceled,
// or failed job through the HTTP routes the app calls (#3425). A live review
// saw every POST /videos/transcode answer 500 with no job behind it, which no
// formats-only or handler-only test could catch.

// webmFixture is AV1 and Opus, which an M4V cannot hold.
const webmFixture = "../../../../../pkg/util/videoutil/testdata/av1-opus.webm"

// recorder collects every event the bus delivers from the moment it starts,
// so a remux's progress events never back up behind a test that is waiting.
type recorder struct {
	mu     sync.Mutex
	events []eventbus.Event
}

func (h harness) record(t *testing.T) *recorder {
	t.Helper()
	r := &recorder{}
	go func() {
		for e := range h.events {
			r.mu.Lock()
			r.events = append(r.events, e)
			r.mu.Unlock()
		}
	}()
	return r
}

// jobEvents are the job_* events for job id, in order.
func (r *recorder) jobEvents(id int64) []eventbus.Event {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []eventbus.Event
	for _, e := range r.events {
		if job, ok := e.Data.(jobutil.Job); ok && job.ID == id && strings.HasPrefix(string(e.Kind), "job_") {
			out = append(out, e)
		}
	}
	return out
}

// uploads are the paths of the upload events seen so far.
func (r *recorder) uploads() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []string
	for _, e := range r.events {
		if e.Kind == eventbus.EventUpload {
			out = append(out, e.Path)
		}
	}
	return out
}

// send sends a request with an optional JSON body.
func (h harness) send(method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

// waitForStatus polls GET /jobs/{id} until the job reaches want, failing if it
// settles anywhere else or takes too long.
func (h harness) waitForStatus(t *testing.T, id int64, want jobutil.Status) jobutil.Job {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for {
		w := h.get(fmt.Sprintf("/api/v0/jobs/%d", id))
		if w.Code != http.StatusOK {
			t.Fatalf("GET /jobs/%d returned %d: %s", id, w.Code, w.Body.String())
		}
		var job jobutil.Job
		if err := json.Unmarshal(w.Body.Bytes(), &job); err != nil {
			t.Fatal(err)
		}
		if job.Status == want {
			return job
		}
		finished := job.Status != jobutil.StatusPending && job.Status != jobutil.StatusRunning
		if finished || time.Now().After(deadline) {
			t.Fatalf("job = %+v, want %s", job, want)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// listedFormats is what GET /videos/transcode/formats offers for rel.
func (h harness) listedFormats(t *testing.T, rel string) []string {
	t.Helper()
	w := h.get("/api/v0/videos/transcode/formats?relPath=" + rel + "&serial=" + testSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("formats for %s returned %d: %s", rel, w.Code, w.Body.String())
	}
	var body struct {
		Formats []struct {
			Format string `json:"format"`
		} `json:"formats"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, f := range body.Formats {
		out = append(out, f.Format)
	}
	return out
}

// listedJobIDs is the ids GET /jobs?kind=video-transcode shows the caller.
func (h harness) listedJobIDs(t *testing.T) []int64 {
	t.Helper()
	w := h.get("/api/v0/jobs?kind=" + transcodeutil.Kind)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /jobs returned %d: %s", w.Code, w.Body.String())
	}
	var jobs []jobutil.Job
	if err := json.Unmarshal(w.Body.Bytes(), &jobs); err != nil {
		t.Fatal(err)
	}
	ids := []int64{}
	for _, j := range jobs {
		ids = append(ids, j.ID)
	}
	return ids
}

func (h harness) metadata(t *testing.T, rel string) v0_videos.VideoMetadataJSON {
	t.Helper()
	w := h.get("/api/v0/videos/metadata?relPath=" + rel + "&serial=" + testSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("metadata for %s returned %d: %s", rel, w.Code, w.Body.String())
	}
	var body v0_videos.VideoMetadataJSON
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	return body
}

func (h harness) hash(t *testing.T, rel string) [sha256.Size]byte {
	t.Helper()
	f, err := os.Open(filepath.Join(h.filesDir, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, f); err != nil {
		t.Fatal(err)
	}
	return [sha256.Size]byte(sum.Sum(nil))
}

func (h harness) exists(rel string) bool {
	_, err := os.Stat(filepath.Join(h.filesDir, filepath.FromSlash(rel)))
	return err == nil
}

// staged is what a conversion has left in the disk's staging dir.
func (h harness) staged(t *testing.T) []string {
	t.Helper()
	left, err := filepath.Glob(filepath.Join(h.dataDir, "tmp", "transcode-jobs", "transcode-*"))
	if err != nil {
		t.Fatal(err)
	}
	return left
}

// kinds lists the kinds of events, for a failure message and for counting.
func kinds(events []eventbus.Event) []eventbus.EventKind {
	out := make([]eventbus.EventKind, 0, len(events))
	for _, e := range events {
		out = append(out, e.Kind)
	}
	return out
}

func isTerminal(kind eventbus.EventKind) bool {
	return kind == eventbus.EventJobCompleted || kind == eventbus.EventJobFailed || kind == eventbus.EventJobCanceled
}

// waitForTerminalEvent waits until the job's events include a terminal one,
// so a test can check nothing else came after.
func (r *recorder) waitForTerminalEvent(t *testing.T, id int64) []eventbus.Event {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for {
		events := r.jobEvents(id)
		if slices.ContainsFunc(events, func(e eventbus.Event) bool { return isTerminal(e.Kind) }) {
			return events
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %d published %v, no terminal event", id, kinds(events))
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// TestConvertCreatesAJobForEveryListedFormat posts exactly the relPath,
// serial, and format the formats list offers, for the two targets tried in the
// live review, and gets a 202 with a job the jobs list shows: never a 500 with
// nothing queued.
func TestConvertCreatesAJobForEveryListedFormat(t *testing.T) {
	h := newHarness(t)
	const rel = "users/galadriel/long-90s.mp4"
	h.writeClip(t, rel)

	listed := h.listedFormats(t, rel)
	for _, format := range []string{"mkv", "m4v"} {
		t.Run(format, func(t *testing.T) {
			if !slices.Contains(listed, format) {
				t.Fatalf("formats for %s = %v, want %s listed", rel, listed, format)
			}
			id := acceptedJobID(t, h.post(transcodeBody(rel, format, "original")))
			job := h.job(t, id)
			if job.Kind != transcodeutil.Kind || job.Status != jobutil.StatusPending || job.Lane != transcodeutil.LaneCopy {
				t.Errorf("job = %+v, want a pending %s job in the copy lane", job, transcodeutil.Kind)
			}
			if serial, relPath := job.Source(); serial != testSerial || relPath != rel {
				t.Errorf("job source = %s %s, want %s %s", serial, relPath, testSerial, rel)
			}
			if ids := h.listedJobIDs(t); !slices.Contains(ids, id) {
				t.Errorf("GET /jobs lists %v, want job %d", ids, id)
			}
		})
	}
}

// TestConvertJobIsListedOnlyForItsOwner queues a conversion as one account and
// lists the jobs as it, as another account, and as an admin.
func TestConvertJobIsListedOnlyForItsOwner(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "alice/clip.mp4")
	owner, other := h.user(t, "alice"), h.user(t, "bob")
	h.grant(t, owner, "alice", accessutil.Write)
	h.grant(t, other, "bob", accessutil.Write)

	*h.principal = accessutil.Principal{UserID: owner}
	id := acceptedJobID(t, h.post(transcodeBody("alice/clip.mp4", "mkv", "original")))
	if ids := h.listedJobIDs(t); !slices.Equal(ids, []int64{id}) {
		t.Errorf("the owner's jobs list = %v, want [%d]", ids, id)
	}
	*h.principal = accessutil.Principal{UserID: other}
	if ids := h.listedJobIDs(t); len(ids) != 0 {
		t.Errorf("another account's jobs list = %v, want none", ids)
	}
	if w := h.get(fmt.Sprintf("/api/v0/jobs/%d", id)); w.Code != http.StatusNotFound {
		t.Errorf("another account's GET /jobs/%d = %d, want 404", id, w.Code)
	}
	*h.principal = accessutil.System
	if ids := h.listedJobIDs(t); !slices.Equal(ids, []int64{id}) {
		t.Errorf("an admin's jobs list = %v, want [%d]", ids, id)
	}
}

// TestConvertRunsToAPlayableFile runs real remuxes to the end. Each job goes
// queued, started, then progress that only climbs within [0, 1], then one
// completed event at progress 1. The output lands beside the source, reads
// back through GET /videos/metadata as the same video, and is announced with
// an upload event; the source is left byte for byte as it was.
func TestConvertRunsToAPlayableFile(t *testing.T) {
	cases := []struct {
		name, fixture, source, format, output string
	}{
		{"mp4 to mkv", gopFixture, "users/galadriel/long-90s.mp4", "mkv", "users/galadriel/long-90s.mkv"},
		{"mp4 to m4v", gopFixture, "users/galadriel/long-90s.mp4", "m4v", "users/galadriel/long-90s.m4v"},
		{"ts to mp4", tsFixture, "clip.ts", "mp4", "clip.mp4"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			h := newHarness(t)
			events := h.record(t)
			copyFixture(t, c.fixture, filepath.Join(h.filesDir, filepath.FromSlash(c.source)))
			before := h.hash(t, c.source)
			want := h.metadata(t, c.source)
			h.runWorker(t)

			id := acceptedJobID(t, h.post(transcodeBody(c.source, c.format, "original")))
			job := h.waitForStatus(t, id, jobutil.StatusCompleted)
			if job.Progress != 1 || job.Error != "" || job.FinishedAt == nil {
				t.Errorf("completed job = %+v, want progress 1, no error, and a finish time", job)
			}

			seen := events.waitForTerminalEvent(t, id)
			got := kinds(seen)
			if len(got) < 3 || got[0] != eventbus.EventJobQueued || got[1] != eventbus.EventJobStarted ||
				got[len(got)-1] != eventbus.EventJobCompleted {
				t.Errorf("job events = %v, want queued, started, progress, completed", got)
			}
			last := 0.0
			for _, e := range seen {
				p := e.Data.(jobutil.Job).Progress
				if e.Kind == eventbus.EventJobProgress && (p < last || p < 0 || p > 1) {
					t.Errorf("progress went %v -> %v in %v", last, p, got)
				}
				last = max(last, p)
			}
			if final := seen[len(seen)-1].Data.(jobutil.Job).Progress; final != 1 {
				t.Errorf("the completed event carries progress %v, want 1", final)
			}
			// The job is done, so an upload event that is coming has come.
			if uploads := events.uploads(); !slices.Equal(uploads, []string{c.output}) {
				t.Errorf("upload events = %v, want one for %s", uploads, c.output)
			}

			out := h.metadata(t, c.output)
			if out.VideoCodec != want.VideoCodec || out.AudioCodec != want.AudioCodec ||
				out.Width != want.Width || out.Height != want.Height ||
				math.Abs(out.Duration-want.Duration) > 1/want.Framerate {
				t.Errorf("output reads as %+v, want the source's streams %+v", out, want)
			}
			if h.hash(t, c.source) != before {
				t.Error("the conversion changed the source file")
			}
			if left := h.staged(t); len(left) != 0 {
				t.Errorf("staging still holds %v", left)
			}
			// A second event for the job would be a second terminal event.
			time.Sleep(50 * time.Millisecond)
			if again := events.jobEvents(id); len(again) != len(seen) {
				t.Errorf("job events after completing = %v, want nothing after %v", kinds(again), got)
			}
		})
	}
}

// gatedRemux writes a partial output, closes started, and blocks until its
// job is canceled, like a remux of a long video caught halfway.
func gatedRemux(started chan<- struct{}) transcodeutil.RemuxFunc {
	return func(ctx context.Context, p videoutil.RemuxParams) error {
		if _, err := io.WriteString(p.Output, "partial"); err != nil {
			return err
		}
		p.OnProgress(0.5)
		close(started)
		<-ctx.Done()
		return ctx.Err()
	}
}

// TestConvertCancelStopsARunningJob cancels a conversion mid-remux through
// DELETE /jobs/{id}. The job ends canceled with one canceled event, a second
// cancel is a 409 rather than a 500, and nothing of the partial output is left
// beside the source or in staging.
func TestConvertCancelStopsARunningJob(t *testing.T) {
	started := make(chan struct{})
	h := newHarnessWithRemux(t, gatedRemux(started))
	events := h.record(t)
	h.writeClip(t, "clip.mp4")
	h.runWorker(t)

	id := acceptedJobID(t, h.post(transcodeBody("clip.mp4", "mkv", "original")))
	select {
	case <-started:
	case <-time.After(30 * time.Second):
		t.Fatalf("the remux never started: %+v", h.job(t, id))
	}
	if job := h.job(t, id); job.Status != jobutil.StatusRunning {
		t.Fatalf("job = %+v, want running", job)
	}

	w := h.send(http.MethodDelete, fmt.Sprintf("/api/v0/jobs/%d", id), "")
	var canceled jobutil.Job
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &canceled) != nil || canceled.Status != jobutil.StatusCanceled {
		t.Fatalf("cancel returned %d %s, want 200 and a canceled job", w.Code, w.Body.String())
	}
	if w := h.send(http.MethodDelete, fmt.Sprintf("/api/v0/jobs/%d", id), ""); w.Code != http.StatusConflict {
		t.Errorf("a second cancel returned %d %s, want 409", w.Code, w.Body.String())
	}

	// The handler removes its staged file once the remux returns.
	deadline := time.Now().Add(10 * time.Second)
	for len(h.staged(t)) != 0 {
		if time.Now().After(deadline) {
			t.Fatalf("staging still holds %v after the cancel", h.staged(t))
		}
		time.Sleep(10 * time.Millisecond)
	}
	if job := h.job(t, id); job.Status != jobutil.StatusCanceled {
		t.Errorf("job = %+v, want it left canceled", job)
	}
	if h.exists("clip.mkv") {
		t.Error("a canceled conversion left an output beside the source")
	}
	if uploads := events.uploads(); len(uploads) != 0 {
		t.Errorf("a canceled conversion published uploads %v", uploads)
	}
	events.waitForTerminalEvent(t, id)
	time.Sleep(50 * time.Millisecond) // for anything that would follow it
	got := kinds(events.jobEvents(id))
	if terminal := slices.DeleteFunc(slices.Clone(got), func(k eventbus.EventKind) bool { return !isTerminal(k) }); !slices.Equal(terminal, []eventbus.EventKind{eventbus.EventJobCanceled}) {
		t.Errorf("job events = %v, want exactly one terminal event, job_canceled", got)
	}
}

// TestConvertCancelOfAPendingJob cancels a conversion before any worker picks
// it up: it never runs, and starting a worker afterward leaves it canceled.
func TestConvertCancelOfAPendingJob(t *testing.T) {
	ran := make(chan struct{}, 1)
	h := newHarnessWithRemux(t, func(context.Context, videoutil.RemuxParams) error {
		ran <- struct{}{}
		return nil
	})
	h.writeClip(t, "clip.mp4")
	id := acceptedJobID(t, h.post(transcodeBody("clip.mp4", "mkv", "original")))

	if w := h.send(http.MethodDelete, fmt.Sprintf("/api/v0/jobs/%d", id), ""); w.Code != http.StatusOK {
		t.Fatalf("cancel returned %d %s, want 200", w.Code, w.Body.String())
	}
	h.runWorker(t)
	select {
	case <-ran:
		t.Fatal("a canceled job ran")
	case <-time.After(200 * time.Millisecond):
	}
	if job := h.job(t, id); job.Status != jobutil.StatusCanceled {
		t.Errorf("job = %+v, want canceled", job)
	}
}

// TestConvertFailureIsAFailedJobWithAReason breaks the source between the
// POST and the run: deleted, overwritten with bytes that are not a video, or
// replaced with a video whose codecs the target cannot hold. Each job ends
// failed with a diagnostic error and one failed event, leaves no output, and
// a retry is refused with a 422 while the source stays that way, naming the
// reason when the source is there but no longer reads as a video (#4255).
func TestConvertFailureIsAFailedJobWithAReason(t *testing.T) {
	cases := []struct {
		name   string
		format string
		breaks func(t *testing.T, path string)
		reason string
		// retryReason is the reason code the refused retry's 422 carries.
		retryReason videoutil.Reason
	}{
		{"source deleted", "mkv", func(t *testing.T, path string) {
			if err := os.Remove(path); err != nil {
				t.Fatal(err)
			}
		}, transcodeutil.ErrSourceNotFound.Error(), videoutil.ReasonNone},
		{"source no longer a video", "mkv", func(t *testing.T, path string) {
			if err := os.WriteFile(path, []byte("not a video any more"), 0o644); err != nil {
				t.Fatal(err)
			}
		}, "", videoutil.ReasonUnsupportedFormat},
		{"source damaged", "mkv", func(t *testing.T, path string) {
			clip, err := os.ReadFile(gopFixture)
			if err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, clip[:len(clip)/2], 0o644); err != nil {
				t.Fatal(err)
			}
		}, "", videoutil.ReasonDamaged},
		{"source's codecs no longer fit the format", "m4v", func(t *testing.T, path string) {
			copyFixture(t, webmFixture, path)
		}, "", videoutil.ReasonNone},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			h := newHarness(t)
			events := h.record(t)
			h.writeClip(t, "clip.mp4")
			id := acceptedJobID(t, h.post(transcodeBody("clip.mp4", c.format, "original")))
			c.breaks(t, filepath.Join(h.filesDir, "clip.mp4"))
			h.runWorker(t)

			job := h.waitForStatus(t, id, jobutil.StatusFailed)
			if job.Error == "" || !strings.Contains(job.Error, c.reason) {
				t.Errorf("failed job error = %q, want a diagnostic reason containing %q", job.Error, c.reason)
			}
			got := kinds(events.waitForTerminalEvent(t, id))
			if got[len(got)-1] != eventbus.EventJobFailed || slices.ContainsFunc(got[:len(got)-1], isTerminal) {
				t.Errorf("job events = %v, want one terminal event, job_failed", got)
			}
			if h.exists("clip." + c.format) {
				t.Error("a failed conversion left an output beside the source")
			}
			if left := h.staged(t); len(left) != 0 {
				t.Errorf("staging still holds %v", left)
			}
			if uploads := events.uploads(); len(uploads) != 0 {
				t.Errorf("a failed conversion published uploads %v", uploads)
			}
			w := h.send(http.MethodPost, fmt.Sprintf("/api/v0/jobs/%d/retry", id), "")
			if got := refusalOf(t, w.Code, w.Body.Bytes()).Reason; got != string(c.retryReason) {
				t.Errorf("retry reason = %q, want %q (%s)", got, c.retryReason, w.Body.String())
			}
			if job := h.job(t, id); job.Status != jobutil.StatusFailed {
				t.Errorf("a refused retry left the job %+v, want it still failed", job)
			}
		})
	}
}

// TestConvertRemuxFailureNamesTheCause fails the remux itself: the job's
// error carries what went wrong rather than a generic sentence.
func TestConvertRemuxFailureNamesTheCause(t *testing.T) {
	h := newHarnessWithRemux(t, func(_ context.Context, p videoutil.RemuxParams) error {
		_, _ = io.WriteString(p.Output, "partial")
		return errors.New("sprocket: write packet: disk full")
	})
	h.writeClip(t, "clip.mp4")
	h.runWorker(t)

	id := acceptedJobID(t, h.post(transcodeBody("clip.mp4", "mkv", "original")))
	job := h.waitForStatus(t, id, jobutil.StatusFailed)
	if !strings.Contains(job.Error, "disk full") {
		t.Errorf("failed job error = %q, want the remux's cause", job.Error)
	}
	if h.exists("clip.mkv") || len(h.staged(t)) != 0 {
		t.Error("a failed remux left its partial output behind")
	}
}

// user creates an account and returns its id.
func (h harness) user(t *testing.T, name string) int64 {
	t.Helper()
	u, err := h.database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: name, PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	return u.ID
}

// grant gives an account a level on rel on the test disk.
func (h harness) grant(t *testing.T, userID int64, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		DeviceSerial: testSerial,
		RelPath:      rel,
		UserID:       sql.NullInt64{Int64: userID, Valid: true},
		Level:        level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

package v0_jobs_test

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

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_jobs "github.com/autobutler-org/quark/internal/server/api/v0/jobs"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

const (
	testKind    = "test"
	otherKind   = "other"
	testTimeout = 5 * time.Second
)

// blockingHandler fails at once for params mentioning "fail", completes at once
// for params mentioning "complete", and otherwise runs until its job is
// canceled. The Validate hook the harness registers refuses params that
// mention "gone", standing in for a job whose inputs were deleted.
type blockingHandler struct {
	started chan struct{}
	stopped chan struct{}
}

func (b *blockingHandler) run(ctx context.Context, params json.RawMessage, _ func(float64)) error {
	switch {
	case strings.Contains(string(params), "fail"):
		return errors.New("handler failed")
	case strings.Contains(string(params), "complete"):
		return nil
	}
	b.started <- struct{}{}
	<-ctx.Done()
	b.stopped <- struct{}{}
	return ctx.Err()
}

type harness struct {
	engine  *gin.Engine
	queue   *jobutil.Queue
	handler *blockingHandler
}

// newHarness mounts the jobs router over a real temp database. The worker is
// not started, so jobs stay pending unless a test calls runWorker.
func newHarness(t *testing.T) harness {
	t.Helper()
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: dbtest.NewDB(t), EventBus: eventbus.New()})
	handler := &blockingHandler{started: make(chan struct{}, 4), stopped: make(chan struct{}, 4)}
	queue.Register(jobutil.RegisterParams{Kind: testKind, Handler: jobutil.Handler{
		Run: handler.run,
		Validate: func(params json.RawMessage) error {
			if strings.Contains(string(params), "gone") {
				return fmt.Errorf("input is gone")
			}
			return nil
		},
	}})
	queue.Register(jobutil.RegisterParams{Kind: otherKind, Handler: jobutil.Handler{Run: handler.run}})
	deps := deputil.NewDependencies().WithJobQueue(queue)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_jobs.NewRouter())
	return harness{engine: engine, queue: queue, handler: handler}
}

func (h harness) do(method, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func (h harness) enqueue(t *testing.T, name string, params any) jobutil.Job {
	t.Helper()
	res, err := h.queue.Enqueue(context.Background(), jobutil.EnqueueParams{Kind: testKind, Name: name, Params: params})
	if err != nil {
		t.Fatal(err)
	}
	return res.Job
}

func (h harness) cancel(t *testing.T, id int64) {
	t.Helper()
	if _, err := h.queue.Cancel(context.Background(), jobutil.CancelParams{ID: id}); err != nil {
		t.Fatal(err)
	}
}

func (h harness) runWorker(t *testing.T) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.queue.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

func decode[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	return v
}

func wait(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(testTimeout):
		t.Fatalf("timed out waiting for %s", what)
	}
}

func TestListJobsStartsEmpty(t *testing.T) {
	h := newHarness(t)
	w := h.do(http.MethodGet, "/api/v0/jobs?kind="+testKind)
	if w.Code != http.StatusOK || strings.TrimSpace(w.Body.String()) != "[]" {
		t.Fatalf("GET /jobs = %d %s, want 200 []", w.Code, w.Body.String())
	}
}

func TestListJobsRequiresKnownKinds(t *testing.T) {
	h := newHarness(t)
	cases := []struct {
		name     string
		query    string
		wantText string
	}{
		{"missing kind", "", "at least one job kind is required"},
		{"empty kind", "?kind=", "at least one job kind is required"},
		{"unknown kind", "?kind=nope", "known kinds: other, test"},
		{"one unknown among known kinds", "?kind=test&kind=nope", "known kinds: other, test"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w := h.do(http.MethodGet, "/api/v0/jobs"+c.query)
			if w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), c.wantText) {
				t.Errorf("GET /jobs%s = %d %s, want 400 mentioning %q", c.query, w.Code, w.Body.String(), c.wantText)
			}
		})
	}
}

func TestListJobsFiltersByRepeatedKind(t *testing.T) {
	h := newHarness(t)
	h.enqueue(t, "a test job", nil)
	if _, err := h.queue.Enqueue(context.Background(), jobutil.EnqueueParams{Kind: otherKind, Name: "an other job"}); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		query     string
		wantNames []string
	}{
		{"?kind=test", []string{"a test job"}},
		{"?kind=other", []string{"an other job"}},
		{"?kind=test&kind=other", []string{"an other job", "a test job"}},
	}
	for _, c := range cases {
		t.Run(c.query, func(t *testing.T) {
			w := h.do(http.MethodGet, "/api/v0/jobs"+c.query)
			if w.Code != http.StatusOK {
				t.Fatalf("GET /jobs%s returned %d: %s", c.query, w.Code, w.Body.String())
			}
			jobs := decode[[]jobutil.Job](t, w)
			names := make([]string, 0, len(jobs))
			for _, job := range jobs {
				names = append(names, job.Name)
			}
			if strings.Join(names, "|") != strings.Join(c.wantNames, "|") {
				t.Errorf("GET /jobs%s names = %q, want %q", c.query, names, c.wantNames)
			}
		})
	}
}

func TestListGetAndCancelJobs(t *testing.T) {
	h := newHarness(t)
	first := h.enqueue(t, "first", nil)
	h.enqueue(t, "second", nil)

	w := h.do(http.MethodGet, "/api/v0/jobs?kind="+testKind)
	jobs := decode[[]map[string]any](t, w)
	if w.Code != http.StatusOK || len(jobs) != 2 || jobs[0]["name"] != "second" {
		t.Fatalf("GET /jobs = %d %s, want two jobs newest first", w.Code, w.Body.String())
	}
	wantKeys := []string{"id", "kind", "lane", "name", "params", "status", "progress", "attempts", "createdAt", "startedAt", "finishedAt", "error"}
	if params, ok := jobs[0]["params"].(map[string]any); !ok || len(params) != 0 {
		t.Errorf("params for a job enqueued without any = %v, want {}", jobs[0]["params"])
	}
	if len(jobs[0]) != len(wantKeys) {
		t.Errorf("job JSON has %d fields, want %d: %v", len(jobs[0]), len(wantKeys), jobs[0])
	}
	for _, key := range wantKeys {
		if _, ok := jobs[0][key]; !ok {
			t.Errorf("job JSON is missing %q: %v", key, jobs[0])
		}
	}
	if jobs[0]["kind"] != testKind || jobs[0]["status"] != "pending" || jobs[0]["startedAt"] != nil {
		t.Errorf("pending job = %v", jobs[0])
	}

	firstPath := fmt.Sprintf("/api/v0/jobs/%d", first.ID)
	if w := h.do(http.MethodGet, firstPath); w.Code != http.StatusOK || decode[map[string]any](t, w)["name"] != "first" {
		t.Errorf("GET %s = %d %s", firstPath, w.Code, w.Body.String())
	}
	if w := h.do(http.MethodGet, "/api/v0/jobs/999"); w.Code != http.StatusNotFound {
		t.Errorf("GET unknown job returned %d, want 404", w.Code)
	}
	if w := h.do(http.MethodGet, "/api/v0/jobs/abc"); w.Code != http.StatusBadRequest {
		t.Errorf("GET malformed job id returned %d, want 400", w.Code)
	}

	w = h.do(http.MethodDelete, firstPath)
	canceled := decode[map[string]any](t, w)
	if w.Code != http.StatusOK || canceled["status"] != "canceled" || canceled["finishedAt"] == nil {
		t.Fatalf("DELETE %s = %d %s, want 200 canceled", firstPath, w.Code, w.Body.String())
	}
	if w := h.do(http.MethodDelete, firstPath); w.Code != http.StatusConflict {
		t.Errorf("second DELETE returned %d, want 409", w.Code)
	}
	if w := h.do(http.MethodDelete, "/api/v0/jobs/999"); w.Code != http.StatusNotFound {
		t.Errorf("DELETE unknown job returned %d, want 404", w.Code)
	}
}

func TestCancelRunningJob(t *testing.T) {
	h := newHarness(t)
	job := h.enqueue(t, "long", nil)
	h.runWorker(t)
	wait(t, h.handler.started, "the job to start")

	path := fmt.Sprintf("/api/v0/jobs/%d", job.ID)
	w := h.do(http.MethodDelete, path)
	if w.Code != http.StatusOK || decode[map[string]any](t, w)["status"] != "canceled" {
		t.Fatalf("DELETE %s = %d %s, want 200 canceled", path, w.Code, w.Body.String())
	}
	wait(t, h.handler.stopped, "the running handler to see its context canceled")
}

// waitForStatus polls the queue until job id reaches status.
func (h harness) waitForStatus(t *testing.T, id int64, status jobutil.Status) jobutil.Job {
	t.Helper()
	deadline := time.Now().Add(testTimeout)
	for {
		res, err := h.queue.Get(context.Background(), jobutil.GetParams{ID: id})
		if err != nil {
			t.Fatal(err)
		}
		if res.Job.Status == status {
			return res.Job
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %d is %s, want %s", id, res.Job.Status, status)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestRetryJob(t *testing.T) {
	h := newHarness(t)
	failed := h.enqueue(t, "failed", map[string]bool{"fail": true})
	gone := h.enqueue(t, "gone", map[string]bool{"fail": true, "gone": true})
	completed := h.enqueue(t, "completed", map[string]bool{"complete": true})
	canceled := h.enqueue(t, "canceled", nil)
	h.cancel(t, canceled.ID)
	h.runWorker(t)
	before := h.waitForStatus(t, failed.ID, jobutil.StatusFailed)
	h.waitForStatus(t, gone.ID, jobutil.StatusFailed)
	h.waitForStatus(t, completed.ID, jobutil.StatusCompleted)
	running := h.enqueue(t, "running", nil)
	wait(t, h.handler.started, "the running job to start")
	// The worker is busy with running, so these stay pending.
	pending := h.enqueue(t, "pending", nil)

	retryPath := fmt.Sprintf("/api/v0/jobs/%d/retry", failed.ID)
	w := h.do(http.MethodPost, retryPath)
	if w.Code != http.StatusAccepted {
		t.Fatalf("retry of a failed job returned %d, want 202: %s", w.Code, w.Body.String())
	}
	if id := decode[map[string]int64](t, w)["jobId"]; id != failed.ID {
		t.Fatalf("retry jobId = %d, want the same job %d", id, failed.ID)
	}
	after := decode[jobutil.Job](t, h.do(http.MethodGet, fmt.Sprintf("/api/v0/jobs/%d", failed.ID)))
	if before.Error == "" || before.Attempts != 1 || before.StartedAt == nil || before.FinishedAt == nil {
		t.Fatalf("failed job before retry = %+v, want its run recorded", before)
	}
	if after.Status != jobutil.StatusPending || after.Progress != 0 || after.Error != "" ||
		after.StartedAt != nil || after.FinishedAt != nil || !after.CreatedAt.Equal(before.CreatedAt) ||
		after.Attempts != before.Attempts {
		t.Errorf("job after retry = %+v, want it reset to pending with createdAt and attempts kept", after)
	}

	cases := []struct {
		name string
		path string
		want int
	}{
		{"the same job again, now pending", retryPath, http.StatusConflict},
		{"a canceled job", fmt.Sprintf("/api/v0/jobs/%d/retry", canceled.ID), http.StatusConflict},
		{"a completed job", fmt.Sprintf("/api/v0/jobs/%d/retry", completed.ID), http.StatusConflict},
		{"a running job", fmt.Sprintf("/api/v0/jobs/%d/retry", running.ID), http.StatusConflict},
		{"a pending job", fmt.Sprintf("/api/v0/jobs/%d/retry", pending.ID), http.StatusConflict},
		{"an unknown job", "/api/v0/jobs/999/retry", http.StatusNotFound},
		{"a job whose inputs are gone", fmt.Sprintf("/api/v0/jobs/%d/retry", gone.ID), http.StatusUnprocessableEntity},
		{"a malformed id", "/api/v0/jobs/abc/retry", http.StatusBadRequest},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if w := h.do(http.MethodPost, c.path); w.Code != c.want {
				t.Errorf("POST %s returned %d, want %d: %s", c.path, w.Code, c.want, w.Body.String())
			}
		})
	}
}

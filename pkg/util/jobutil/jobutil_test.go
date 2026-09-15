package jobutil

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

const (
	testKind    = "test"
	testTimeout = 5 * time.Second
)

// fakeHandler reports the configured progress, then blocks until the test
// releases it or the job's context is canceled.
type fakeHandler struct {
	progress []float64
	started  chan json.RawMessage
	release  chan error
}

func (f *fakeHandler) run(ctx context.Context, params json.RawMessage, report func(float64)) error {
	f.started <- params
	for _, p := range f.progress {
		report(p)
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-f.release:
		return err
	}
}

type harness struct {
	database *db.DatabaseSqlc
	queue    *Queue
	fake     *fakeHandler
	events   <-chan eventbus.Event
}

func newHarness(t *testing.T, progress ...float64) harness {
	t.Helper()
	database := dbtest.NewDB(t)
	bus := eventbus.New()
	events, unsub := bus.Subscribe("jobutil-test")
	t.Cleanup(unsub)
	fake := &fakeHandler{progress: progress, started: make(chan json.RawMessage, 8), release: make(chan error, 8)}
	queue := NewQueue(NewQueueParams{Database: database, EventBus: bus})
	queue.Register(RegisterParams{Kind: testKind, Handler: Handler{
		Run: fake.run,
		Validate: func(params json.RawMessage) error {
			if strings.Contains(string(params), "gone") {
				return errors.New("input is gone")
			}
			return nil
		},
	}})
	return harness{database: database, queue: queue, fake: fake, events: events}
}

// run starts the worker and stops it when the test ends. The returned func
// stops it early and waits for Run to return.
func (h harness) run(t *testing.T) func() {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.queue.Run(ctx)
	}()
	stop := func() {
		cancel()
		select {
		case <-done:
		case <-time.After(testTimeout):
			t.Fatal("Run did not return after its context was canceled")
		}
	}
	t.Cleanup(stop)
	return stop
}

func (h harness) enqueue(t *testing.T, n int) Job {
	t.Helper()
	res, err := h.queue.Enqueue(context.Background(), EnqueueParams{Kind: testKind, Name: "job", Params: map[string]int{"n": n}})
	if err != nil {
		t.Fatal(err)
	}
	return res.Job
}

// started waits for the fake to start a job and returns the n it was queued with.
func (h harness) started(t *testing.T) int {
	t.Helper()
	select {
	case raw := <-h.fake.started:
		var params struct{ N int }
		if err := json.Unmarshal(raw, &params); err != nil {
			t.Fatalf("decode params %s: %v", raw, err)
		}
		return params.N
	case <-time.After(testTimeout):
		t.Fatal("no job started")
		return 0
	}
}

func (h harness) job(t *testing.T, id int64) Job {
	t.Helper()
	res, err := h.queue.Get(context.Background(), GetParams{ID: id})
	if err != nil {
		t.Fatal(err)
	}
	return res.Job
}

func (h harness) waitStatus(t *testing.T, id int64, want Status) Job {
	t.Helper()
	deadline := time.Now().Add(testTimeout)
	for {
		job := h.job(t, id)
		if job.Status == want {
			return job
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %d is %s, want %s", id, job.Status, want)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func (h harness) expectEvents(t *testing.T, kinds ...eventbus.EventKind) []Job {
	t.Helper()
	jobs := make([]Job, 0, len(kinds))
	for _, want := range kinds {
		select {
		case e := <-h.events:
			if e.Kind != want {
				t.Fatalf("event %d is %s, want %s", len(jobs), e.Kind, want)
			}
			jobs = append(jobs, e.Data.(Job))
		case <-time.After(testTimeout):
			t.Fatalf("timed out waiting for event %s", want)
		}
	}
	return jobs
}

func TestJobRunsAsTheAccountThatQueuedIt(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	user, err := h.database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	seen := make(chan int64, 2)
	h.queue.Register(RegisterParams{Kind: "owned", Handler: Handler{
		Run: func(ctx context.Context, _ json.RawMessage, _ func(float64)) error {
			seen <- UserID(ctx)
			return nil
		},
	}})
	h.run(t)

	for _, want := range []int64{user.ID, 0} {
		res, err := h.queue.Enqueue(ctx, EnqueueParams{Kind: "owned", Name: "job", UserID: want})
		if err != nil {
			t.Fatal(err)
		}
		if res.Job.UserID != want {
			t.Errorf("queued job UserID = %d, want %d", res.Job.UserID, want)
		}
		select {
		case got := <-seen:
			if got != want {
				t.Errorf("UserID(ctx) in the handler = %d, want %d", got, want)
			}
		case <-time.After(testTimeout):
			t.Fatal("the job did not run")
		}
		if stored := h.waitStatus(t, res.Job.ID, StatusCompleted).UserID; stored != want {
			t.Errorf("stored job UserID = %d, want %d", stored, want)
		}
	}
}

func TestJobSource(t *testing.T) {
	for params, want := range map[string][2]string{
		`{"serial":"USB 1","relPath":"videos/a.mkv","format":"mov"}`: {"USB 1", "videos/a.mkv"},
		`{"relPath":"a.mkv"}`: {"", "a.mkv"},
		`{}`:                  {"", ""},
		`[]`:                  {"", ""},
	} {
		serial, relPath := Job{Params: json.RawMessage(params)}.Source()
		if serial != want[0] || relPath != want[1] {
			t.Errorf("Source of %s = %q, %q, want %q, %q", params, serial, relPath, want[0], want[1])
		}
	}
}

func TestEnqueueRejectsUnknownKind(t *testing.T) {
	h := newHarness(t)
	_, err := h.queue.Enqueue(context.Background(), EnqueueParams{Kind: "nope", Name: "job"})
	if !errors.Is(err, ErrUnknownKind) {
		t.Fatalf("Enqueue error = %v, want ErrUnknownKind", err)
	}
	res, err := h.queue.List(context.Background(), ListParams{Kinds: []string{testKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Jobs) != 0 {
		t.Fatalf("an unknown kind stored %d job(s)", len(res.Jobs))
	}
}

func TestListFiltersByRegisteredKinds(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	h.queue.Register(RegisterParams{Kind: "other", Handler: Handler{Run: h.fake.run}})
	h.enqueue(t, 1)
	if _, err := h.queue.Enqueue(ctx, EnqueueParams{Kind: "other", Name: "other job"}); err != nil {
		t.Fatal(err)
	}

	for _, kinds := range [][]string{nil, {""}, {testKind, ""}} {
		if _, err := h.queue.List(ctx, ListParams{Kinds: kinds}); !errors.Is(err, ErrKindRequired) {
			t.Errorf("List(%q) error = %v, want ErrKindRequired", kinds, err)
		}
	}
	_, err := h.queue.List(ctx, ListParams{Kinds: []string{testKind, "nope"}})
	if !errors.Is(err, ErrUnknownKind) || !strings.Contains(err.Error(), "known kinds: other, test") {
		t.Errorf("List with an unknown kind error = %v, want ErrUnknownKind naming the known kinds", err)
	}

	one, err := h.queue.List(ctx, ListParams{Kinds: []string{testKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(one.Jobs) != 1 || one.Jobs[0].Kind != testKind {
		t.Errorf("List(test) = %+v, want only the test job", one.Jobs)
	}
	both, err := h.queue.List(ctx, ListParams{Kinds: []string{testKind, "other"}})
	if err != nil {
		t.Fatal(err)
	}
	if len(both.Jobs) != 2 || both.Jobs[0].Kind != "other" || both.Jobs[1].Kind != testKind {
		t.Errorf("List(test, other) = %+v, want both jobs newest first", both.Jobs)
	}
}

func TestJobJSONMatchesTheContract(t *testing.T) {
	h := newHarness(t)
	job := h.enqueue(t, 1)

	encoded, err := json.Marshal(job)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(encoded, &fields); err != nil {
		t.Fatal(err)
	}
	want := []string{"id", "kind", "lane", "name", "params", "status", "progress", "attempts", "createdAt", "startedAt", "finishedAt", "error"}
	if _, ok := fields["params"].(map[string]any); !ok {
		t.Errorf("params is not a JSON object: %s", encoded)
	}
	if len(fields) != len(want) {
		t.Errorf("job JSON has %d fields, want %d: %s", len(fields), len(want), encoded)
	}
	for _, key := range want {
		if _, ok := fields[key]; !ok {
			t.Errorf("job JSON is missing %q: %s", key, encoded)
		}
	}
	if fields["startedAt"] != nil || fields["finishedAt"] != nil {
		t.Errorf("a pending job has timestamps it has not reached: %s", encoded)
	}
	if fields["attempts"] != float64(0) {
		t.Errorf("a job that never ran has attempts %v, want 0", fields["attempts"])
	}
	if _, err := time.Parse(time.RFC3339, fields["createdAt"].(string)); err != nil {
		t.Errorf("createdAt is not RFC 3339: %v", err)
	}
}

func TestCompletedJobLifecycle(t *testing.T) {
	h := newHarness(t, 0.5)
	queued := h.enqueue(t, 7)
	h.run(t)
	if n := h.started(t); n != 7 {
		t.Fatalf("handler got n=%d, want the params the job was queued with", n)
	}
	h.fake.release <- nil

	jobs := h.expectEvents(t,
		eventbus.EventJobQueued,
		eventbus.EventJobStarted,
		eventbus.EventJobProgress,
		eventbus.EventJobCompleted,
	)
	if jobs[0].Status != StatusPending || jobs[1].Status != StatusRunning || jobs[1].StartedAt == nil {
		t.Errorf("queued/started events = %+v, %+v", jobs[0], jobs[1])
	}
	if jobs[2].Progress != 0.5 {
		t.Errorf("progress event = %v, want 0.5", jobs[2].Progress)
	}
	done := h.job(t, queued.ID)
	if done.Status != StatusCompleted || done.Progress != 1 || done.Attempts != 1 || done.StartedAt == nil || done.FinishedAt == nil {
		t.Errorf("completed job = %+v", done)
	}
}

func TestJobsInOneLaneRunOneAtATimeOldestFirst(t *testing.T) {
	h := newHarness(t)
	first := h.enqueue(t, 1)
	second := h.enqueue(t, 2)
	h.run(t)

	if n := h.started(t); n != 1 {
		t.Fatalf("started job %d first, want 1", n)
	}
	select {
	case <-h.fake.started:
		t.Fatal("a second job started while the first was running")
	case <-time.After(100 * time.Millisecond):
	}
	if status := h.job(t, second.ID).Status; status != StatusPending {
		t.Fatalf("second job is %s while the first runs, want pending", status)
	}

	h.fake.release <- nil
	if n := h.started(t); n != 2 {
		t.Fatalf("started job %d second, want 2", n)
	}
	h.fake.release <- nil
	h.waitStatus(t, second.ID, StatusCompleted)

	res, err := h.queue.List(context.Background(), ListParams{Kinds: []string{testKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Jobs) != 2 || res.Jobs[0].ID != second.ID || res.Jobs[1].ID != first.ID {
		t.Fatalf("List is not newest first: %+v", res.Jobs)
	}
}

func TestCancelPendingJob(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	job := h.enqueue(t, 1)

	res, err := h.queue.Cancel(ctx, CancelParams{ID: job.ID})
	if err != nil {
		t.Fatal(err)
	}
	if res.Job.Status != StatusCanceled || res.Job.FinishedAt == nil {
		t.Fatalf("canceled job = %+v", res.Job)
	}
	h.expectEvents(t, eventbus.EventJobQueued, eventbus.EventJobCanceled)

	if _, err := h.queue.Cancel(ctx, CancelParams{ID: job.ID}); !errors.Is(err, ErrJobFinished) {
		t.Errorf("second Cancel error = %v, want ErrJobFinished", err)
	}
	if _, err := h.queue.Cancel(ctx, CancelParams{ID: 9999}); !errors.Is(err, ErrJobNotFound) {
		t.Errorf("Cancel of unknown job error = %v, want ErrJobNotFound", err)
	}
	if _, err := h.queue.Get(ctx, GetParams{ID: 9999}); !errors.Is(err, ErrJobNotFound) {
		t.Errorf("Get of unknown job error = %v, want ErrJobNotFound", err)
	}

	// The canceled job never runs: the first job the worker starts is the one
	// queued after it.
	h.enqueue(t, 2)
	h.run(t)
	if n := h.started(t); n != 2 {
		t.Fatalf("worker started job %d, want 2", n)
	}
}

func TestCancelRunningJob(t *testing.T) {
	h := newHarness(t)
	job := h.enqueue(t, 1)
	h.run(t)
	h.started(t)

	res, err := h.queue.Cancel(context.Background(), CancelParams{ID: job.ID})
	if err != nil {
		t.Fatal(err)
	}
	if res.Job.Status != StatusCanceled {
		t.Fatalf("canceled job status = %s", res.Job.Status)
	}
	h.expectEvents(t, eventbus.EventJobQueued, eventbus.EventJobStarted, eventbus.EventJobCanceled)

	// The handler's context was canceled, so the worker is free for the next
	// job, and nothing reports the canceled job as failed in between.
	h.enqueue(t, 2)
	h.expectEvents(t, eventbus.EventJobQueued, eventbus.EventJobStarted)
	if status := h.job(t, job.ID).Status; status != StatusCanceled {
		t.Errorf("job status = %s after its handler returned, want canceled", status)
	}
}

func TestHandlerErrorFailsJob(t *testing.T) {
	h := newHarness(t, 0.25)
	job := h.enqueue(t, 1)
	h.run(t)
	h.started(t)
	h.fake.release <- errors.New("encoder exploded")

	jobs := h.expectEvents(t, eventbus.EventJobQueued, eventbus.EventJobStarted, eventbus.EventJobProgress, eventbus.EventJobFailed)
	failed := jobs[3]
	if failed.ID != job.ID || failed.Status != StatusFailed || failed.Error != "encoder exploded" || failed.Progress != 0.25 {
		t.Errorf("failed job = %+v", failed)
	}
}

func TestShutdownMarksRunningJobFailed(t *testing.T) {
	h := newHarness(t)
	job := h.enqueue(t, 1)
	stop := h.run(t)
	h.started(t)

	stop()

	got := h.job(t, job.ID)
	if got.Status != StatusFailed || got.Error != interruptedError {
		t.Errorf("job after shutdown = %+v, want failed as interrupted", got)
	}
}

func TestStartupFailsJobsLeftRunningAndRunsPendingOnes(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	// What a process that died mid-job leaves behind: a row stuck running.
	orphan, err := h.database.Queries.CreateJob(ctx, db.CreateJobParams{Kind: testKind, Name: "orphan", Params: `{"n":1}`})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.database.Queries.ClaimJob(ctx, orphan.ID); err != nil {
		t.Fatal(err)
	}
	h.enqueue(t, 2)

	h.run(t)

	if n := h.started(t); n != 2 {
		t.Fatalf("worker started job %d, want the pending job 2", n)
	}
	got := h.job(t, orphan.ID)
	if got.Status != StatusFailed || got.Error != interruptedError || got.FinishedAt == nil {
		t.Fatalf("orphaned job = %+v, want failed as interrupted", got)
	}
	if _, err := h.queue.Retry(ctx, RetryParams{ID: orphan.ID}); err != nil {
		t.Errorf("an interrupted job is not retryable: %v", err)
	}
}

func TestRetryResetsTheSameJob(t *testing.T) {
	h := newHarness(t, 0.25)
	ctx := context.Background()
	original := h.enqueue(t, 1)
	h.run(t)
	h.started(t)
	h.fake.release <- errors.New("boom")
	failed := h.waitStatus(t, original.ID, StatusFailed)
	if failed.Error != "boom" || failed.Progress != 0.25 || failed.Attempts != 1 || failed.StartedAt == nil || failed.FinishedAt == nil {
		t.Fatalf("failed job = %+v, want its run recorded before the retry", failed)
	}

	res, err := h.queue.Retry(ctx, RetryParams{ID: original.ID})
	if err != nil {
		t.Fatal(err)
	}
	reset := res.Job
	if reset.ID != original.ID || !reset.CreatedAt.Equal(original.CreatedAt) || reset.Status != StatusPending ||
		reset.Progress != 0 || reset.Error != "" || reset.StartedAt != nil || reset.FinishedAt != nil {
		t.Fatalf("retried job = %+v, want job %d reset to pending with its createdAt kept", reset, original.ID)
	}
	if reset.Attempts != 1 {
		t.Errorf("attempts after the retry alone = %d, want it left at 1", reset.Attempts)
	}
	if n := h.started(t); n != 1 {
		t.Fatalf("retry ran with n=%d, want the original params", n)
	}
	if attempts := h.job(t, original.ID).Attempts; attempts != 2 {
		t.Errorf("attempts after running again = %d, want 2", attempts)
	}
	h.expectEvents(t,
		eventbus.EventJobQueued,
		eventbus.EventJobStarted,
		eventbus.EventJobProgress,
		eventbus.EventJobFailed,
		eventbus.EventJobQueued,
		eventbus.EventJobStarted,
	)
	list, err := h.queue.List(ctx, ListParams{Kinds: []string{testKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(list.Jobs) != 1 {
		t.Errorf("a retry left %d jobs, want the one job reused", len(list.Jobs))
	}
}

func TestRetryRefusesJobsThatAreNotFailed(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	canceled := h.enqueue(t, 1)
	if _, err := h.queue.Cancel(ctx, CancelParams{ID: canceled.ID}); err != nil {
		t.Fatal(err)
	}
	running := h.enqueue(t, 2)
	pending := h.enqueue(t, 3)
	h.run(t)
	if n := h.started(t); n != 2 {
		t.Fatalf("started job %d, want 2", n)
	}

	for name, id := range map[string]int64{"canceled": canceled.ID, "running": running.ID, "pending": pending.ID} {
		if _, err := h.queue.Retry(ctx, RetryParams{ID: id}); !errors.Is(err, ErrJobNotRetryable) {
			t.Errorf("Retry of the %s job error = %v, want ErrJobNotRetryable", name, err)
		}
	}
	if _, err := h.queue.Retry(ctx, RetryParams{ID: 9999}); !errors.Is(err, ErrJobNotFound) {
		t.Errorf("Retry of unknown job error = %v, want ErrJobNotFound", err)
	}

	h.fake.release <- nil
	h.waitStatus(t, running.ID, StatusCompleted)
	if _, err := h.queue.Retry(ctx, RetryParams{ID: running.ID}); !errors.Is(err, ErrJobNotRetryable) {
		t.Errorf("Retry of completed job error = %v, want ErrJobNotRetryable", err)
	}

	// A second retry finds the job no longer failed.
	h.started(t)
	h.fake.release <- errors.New("boom")
	h.waitStatus(t, pending.ID, StatusFailed)
	if _, err := h.queue.Retry(ctx, RetryParams{ID: pending.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := h.queue.Retry(ctx, RetryParams{ID: pending.ID}); !errors.Is(err, ErrJobNotRetryable) {
		t.Errorf("second Retry error = %v, want ErrJobNotRetryable", err)
	}
}

func TestRetryRunsTheValidateHook(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	res, err := h.queue.Enqueue(ctx, EnqueueParams{Kind: testKind, Name: "job", Params: map[string]bool{"gone": true}})
	if err != nil {
		t.Fatal(err)
	}
	h.run(t)
	h.started(t)
	h.fake.release <- errors.New("boom")
	h.waitStatus(t, res.Job.ID, StatusFailed)

	if _, err := h.queue.Retry(ctx, RetryParams{ID: res.Job.ID}); !errors.Is(err, ErrRetryRejected) {
		t.Fatalf("Retry error = %v, want ErrRetryRejected", err)
	}
	if status := h.job(t, res.Job.ID).Status; status != StatusFailed {
		t.Errorf("job is %s after a rejected retry, want it left failed", status)
	}
}

func TestProgressIsThrottled(t *testing.T) {
	h := newHarness(t, 0.001, 0.002, 0.5)
	job := h.enqueue(t, 1)
	h.run(t)
	h.started(t)

	jobs := h.expectEvents(t,
		eventbus.EventJobQueued,
		eventbus.EventJobStarted,
		eventbus.EventJobProgress,
		eventbus.EventJobProgress,
	)
	if jobs[2].Progress != 0.001 || jobs[3].Progress != 0.5 {
		t.Errorf("progress events = %v, %v; want 0.001 then 0.5 (0.002 is under the step)", jobs[2].Progress, jobs[3].Progress)
	}
	if saved := h.job(t, job.ID).Progress; saved != 0.5 {
		t.Errorf("saved progress = %v, want 0.5", saved)
	}
	h.fake.release <- nil
	h.expectEvents(t, eventbus.EventJobCompleted)
}

const gatedKind = "gated"

// gatedHandler runs jobs of gatedKind, whose params are {"n": N}. The lane of
// job N is whatever lanes[N] holds when the queue asks, so a test can change
// it before a retry. Job N runs until gates[N] is sent a result or its context
// is canceled.
type gatedHandler struct {
	started chan int
	gates   map[int]chan error

	mu    sync.Mutex
	lanes map[int]string
}

func newGatedHandler(lanes map[int]string) *gatedHandler {
	gates := map[int]chan error{}
	for n := range lanes {
		gates[n] = make(chan error, 1)
	}
	return &gatedHandler{started: make(chan int, len(lanes)), gates: gates, lanes: lanes}
}

func decodeN(raw json.RawMessage) (int, error) {
	var params struct{ N int }
	err := json.Unmarshal(raw, &params)
	return params.N, err
}

func (g *gatedHandler) handler() Handler {
	return Handler{
		Lanes: map[string]int{"encode": 1, "copy": 2},
		Lane: func(_ context.Context, raw json.RawMessage) (string, error) {
			n, err := decodeN(raw)
			if err != nil {
				return "", err
			}
			g.mu.Lock()
			defer g.mu.Unlock()
			if lane, ok := g.lanes[n]; ok {
				return lane, nil
			}
			return "", fmt.Errorf("job %d has no lane", n)
		},
		Run: func(ctx context.Context, raw json.RawMessage, _ func(float64)) error {
			n, err := decodeN(raw)
			if err != nil {
				return err
			}
			g.started <- n
			select {
			case <-ctx.Done():
				return ctx.Err()
			case err := <-g.gates[n]:
				return err
			}
		},
	}
}

func (g *gatedHandler) setLane(n int, lane string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.lanes[n] = lane
}

func (h harness) enqueueGated(t *testing.T, n int) Job {
	t.Helper()
	res, err := h.queue.Enqueue(context.Background(), EnqueueParams{Kind: gatedKind, Name: "gated job", Params: map[string]int{"n": n}})
	if err != nil {
		t.Fatal(err)
	}
	return res.Job
}

// startedSet waits for count jobs to start and returns their ns, sorted.
func startedSet(t *testing.T, started <-chan int, count int) []int {
	t.Helper()
	ns := make([]int, 0, count)
	for range count {
		select {
		case n := <-started:
			ns = append(ns, n)
		case <-time.After(testTimeout):
			t.Fatalf("only %v started, want %d jobs", ns, count)
		}
	}
	slices.Sort(ns)
	return ns
}

// noneStarts checks nothing more starts while the running jobs hold every slot
// the waiting ones could use.
func noneStarts(t *testing.T, started <-chan int) {
	t.Helper()
	select {
	case n := <-started:
		t.Fatalf("job %d started, but its lane was full", n)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestLanesRunUpToTheirLimits(t *testing.T) {
	h := newHarness(t)
	gated := newGatedHandler(map[int]string{1: "encode", 2: "encode", 3: "copy", 4: "copy", 5: "copy"})
	h.queue.Register(RegisterParams{Kind: gatedKind, Handler: gated.handler()})
	jobs := map[int]Job{}
	for n := 1; n <= 5; n++ {
		jobs[n] = h.enqueueGated(t, n)
	}
	if jobs[1].Lane != "encode" || jobs[3].Lane != "copy" {
		t.Fatalf("queued lanes = %q, %q; want encode and copy", jobs[1].Lane, jobs[3].Lane)
	}
	h.run(t)

	// One encode, and two copies beside it: a copy does not wait on the encode.
	if got := startedSet(t, gated.started, 3); !slices.Equal(got, []int{1, 3, 4}) {
		t.Fatalf("started %v first, want the oldest encode and the two oldest copies [1 3 4]", got)
	}
	noneStarts(t, gated.started)

	// A finished copy frees a copy slot, not an encode slot.
	gated.gates[3] <- nil
	if got := startedSet(t, gated.started, 1); got[0] != 5 {
		t.Fatalf("job %d started after a copy finished, want copy 5", got[0])
	}
	noneStarts(t, gated.started)

	// Canceling the running encode frees its slot for the next encode.
	if _, err := h.queue.Cancel(context.Background(), CancelParams{ID: jobs[1].ID}); err != nil {
		t.Fatal(err)
	}
	if got := startedSet(t, gated.started, 1); got[0] != 2 {
		t.Fatalf("job %d started after the encode was canceled, want encode 2", got[0])
	}
	for _, n := range []int{2, 4, 5} {
		gated.gates[n] <- nil
	}
	for _, n := range []int{2, 3, 4, 5} {
		h.waitStatus(t, jobs[n].ID, StatusCompleted)
	}
}

func TestBusyKindDoesNotBlockAnotherKind(t *testing.T) {
	h := newHarness(t)
	gated := newGatedHandler(map[int]string{1: "encode", 2: "encode"})
	h.queue.Register(RegisterParams{Kind: gatedKind, Handler: gated.handler()})
	h.enqueueGated(t, 1)
	h.enqueueGated(t, 2)
	other := h.enqueue(t, 9)
	h.run(t)

	if got := startedSet(t, gated.started, 1); got[0] != 1 {
		t.Fatalf("gated job %d started, want 1", got[0])
	}
	// The test kind's one lane is free even though gated's encode lane is full.
	if n := h.started(t); n != 9 {
		t.Fatalf("test job %d started, want 9", n)
	}
	h.fake.release <- nil
	h.waitStatus(t, other.ID, StatusCompleted)
}

func TestRetryPicksTheLaneAgain(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	gated := newGatedHandler(map[int]string{1: "encode"})
	h.queue.Register(RegisterParams{Kind: gatedKind, Handler: gated.handler()})
	job := h.enqueueGated(t, 1)
	h.run(t)
	startedSet(t, gated.started, 1)
	gated.gates[1] <- errors.New("boom")
	h.waitStatus(t, job.ID, StatusFailed)

	// The inputs changed since the job was queued, so its lane did too.
	gated.setLane(1, "copy")
	res, err := h.queue.Retry(ctx, RetryParams{ID: job.ID})
	if err != nil {
		t.Fatal(err)
	}
	if res.Job.Lane != "copy" {
		t.Errorf("retried job lane = %q, want copy", res.Job.Lane)
	}
	startedSet(t, gated.started, 1)
	gated.gates[1] <- errors.New("boom again")
	h.waitStatus(t, job.ID, StatusFailed)

	gated.setLane(1, "turbo")
	if _, err := h.queue.Retry(ctx, RetryParams{ID: job.ID}); !errors.Is(err, ErrRetryRejected) || !errors.Is(err, ErrUnknownLane) {
		t.Errorf("Retry into an unregistered lane error = %v, want ErrRetryRejected wrapping ErrUnknownLane", err)
	}
	if status := h.job(t, job.ID).Status; status != StatusFailed {
		t.Errorf("job is %s after a refused retry, want it left failed", status)
	}
}

func TestEnqueueRefusesWhatTheLaneHookRefuses(t *testing.T) {
	h := newHarness(t)
	gated := newGatedHandler(map[int]string{1: "turbo"})
	h.queue.Register(RegisterParams{Kind: gatedKind, Handler: gated.handler()})
	ctx := context.Background()

	if _, err := h.queue.Enqueue(ctx, EnqueueParams{Kind: gatedKind, Name: "no lane", Params: map[string]int{"n": 2}}); err == nil {
		t.Error("Enqueue succeeded though the Lane hook failed")
	}
	if _, err := h.queue.Enqueue(ctx, EnqueueParams{Kind: gatedKind, Name: "bad lane", Params: map[string]int{"n": 1}}); !errors.Is(err, ErrUnknownLane) {
		t.Errorf("Enqueue into an unregistered lane error = %v, want ErrUnknownLane", err)
	}
	res, err := h.queue.List(ctx, ListParams{Kinds: []string{gatedKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Jobs) != 0 {
		t.Errorf("refused enqueues stored %d job(s)", len(res.Jobs))
	}
}

func TestShutdownFailsEveryRunningJob(t *testing.T) {
	h := newHarness(t)
	gated := newGatedHandler(map[int]string{1: "encode", 2: "copy", 3: "copy"})
	h.queue.Register(RegisterParams{Kind: gatedKind, Handler: gated.handler()})
	jobs := []Job{h.enqueueGated(t, 1), h.enqueueGated(t, 2), h.enqueueGated(t, 3)}
	stop := h.run(t)
	startedSet(t, gated.started, 3)

	stop()

	for _, job := range jobs {
		if got := h.job(t, job.ID); got.Status != StatusFailed || got.Error != interruptedError {
			t.Errorf("job %d after shutdown = %+v, want failed as interrupted", job.ID, got)
		}
	}
}

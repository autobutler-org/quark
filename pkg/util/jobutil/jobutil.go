// Package jobutil runs background jobs. A job is a row in the jobs table, so
// its history survives a restart and a failed job can be retried; what a job
// does is the Handler registered for its kind. Each kind caps how many of its
// jobs run at once per lane, so kinds never wait on each other and a quick job
// in one lane is not held behind a long one in another.
//
// Every change publishes a job_* event, but the bus drops events for a
// subscriber that falls behind, so clients treat GET /jobs, backed by
// [Queue.List], as the source of truth and the events as a hint to refresh.
package jobutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// Status is where a Job is in its lifecycle.
type Status string

const (
	StatusPending   Status = "pending"
	StatusRunning   Status = "running"
	StatusCompleted Status = "completed"
	StatusFailed    Status = "failed"
	StatusCanceled  Status = "canceled"
)

// Job is a background job as clients see it. A retry reuses the same job, so
// StartedAt and FinishedAt describe its latest run. Elapsed time is derived
// from them rather than stored.
type Job struct {
	ID   int64  `json:"id"`
	Kind string `json:"kind"`
	// Lane is the concurrency lane within Kind the job runs in, such as "copy"
	// for a transcode that only copies streams. It is "" for a kind with one
	// lane.
	Lane string `json:"lane"`
	// Name is display text, such as "Convert vacation.mkv to MOV".
	Name string `json:"name"`
	// Params is the kind-specific JSON object the job was enqueued with, so a
	// client can build its own label from Kind and Params.
	Params   json.RawMessage `json:"params" swaggertype:"object"`
	Status   Status          `json:"status" enums:"pending,running,completed,failed,canceled"`
	Progress float64         `json:"progress"`
	// Attempts is how many times the job has started running: 0 before its
	// first run. A retry leaves it alone; the next run bumps it.
	Attempts int64 `json:"attempts"`
	// CreatedAt is when the job was queued.
	CreatedAt time.Time `json:"createdAt"`
	// StartedAt is null until the job starts running.
	StartedAt *time.Time `json:"startedAt"`
	// FinishedAt is null until the job completes, fails, or is canceled.
	FinishedAt *time.Time `json:"finishedAt"`
	// Error is diagnostic text for a failed job, not copy for a user.
	Error string `json:"error"`
	// UserID is the account that queued the job, whose access it runs with. It
	// is 0 for a job queued by the system or before jobs recorded who queued
	// them, which only admins see (#1979).
	UserID int64 `json:"-"`
}

// Source is the file a job works on, read from the serial and relPath its
// params carry. It is empty for a job whose params name no file.
func (j Job) Source() (serial, relPath string) {
	var source struct {
		Serial  string `json:"serial"`
		RelPath string `json:"relPath"`
	}
	// Params the job could not have been queued with decode to no source.
	_ = json.Unmarshal(j.Params, &source)
	return source.Serial, source.RelPath
}

// WithUserID returns ctx carrying the account a job runs as. The queue sets it
// before calling a Handler.
func WithUserID(ctx context.Context, userID int64) context.Context {
	return context.WithValue(ctx, userIDKey{}, userID)
}

// UserID is the account the job a Handler is running was queued by, or 0 for
// a job with none.
func UserID(ctx context.Context) int64 {
	userID, _ := ctx.Value(userIDKey{}).(int64)
	return userID
}

// HandlerFunc does a job's work. params is the JSON the job was enqueued with.
// It reports progress as a fraction in [0, 1] through report, which must not be
// called after it returns, and it must stop and clean up after itself when ctx
// is canceled. Jobs in different lanes run at the same time, so it must be
// safe to call concurrently.
type HandlerFunc func(ctx context.Context, params json.RawMessage, report func(progress float64)) error

// Handler is what one job kind does.
type Handler struct {
	Run HandlerFunc
	// Validate, when set, is called before a retry is queued, so retrying a
	// job whose inputs are gone fails at once instead of when it runs.
	Validate func(params json.RawMessage) error
	// Lanes caps how many of the kind's jobs run at once in each lane. Nil
	// means the single lane "", one job at a time.
	Lanes map[string]int
	// Lane, when set, picks a job's lane from its params when it is enqueued
	// and again when it is retried, since its inputs may have changed. Nil
	// puts every job in "". An error refuses the enqueue or the retry.
	Lane func(ctx context.Context, params json.RawMessage) (string, error)
}

var (
	// ErrUnknownKind is returned for a kind no Handler is registered for.
	ErrUnknownKind = errors.New("no handler is registered for this job kind")
	// ErrUnknownLane is returned when a kind's Lane hook picks a lane its
	// Lanes has no limit for.
	ErrUnknownLane = errors.New("job kind has no such lane")
	// ErrKindRequired is returned by List when no kind is given.
	ErrKindRequired = errors.New("at least one job kind is required")
	// ErrJobNotFound is returned for an id the jobs table does not hold.
	ErrJobNotFound = errors.New("job not found")
	// ErrJobFinished is returned by Cancel for a job that already completed,
	// failed, or was canceled.
	ErrJobFinished = errors.New("job has already finished")
	// ErrJobNotRetryable is returned by Retry for a job that is not failed,
	// including one another retry has already reset.
	ErrJobNotRetryable = errors.New("only a failed job can be retried")
	// ErrRetryRejected wraps the error a kind's Validate or Lane hook returned
	// for a retry.
	ErrRetryRejected = errors.New("job cannot be retried")
)

// Queue stores jobs in the database and runs them within each kind's lane
// limits. Build it with NewQueue; its methods are safe for concurrent use.
type Queue struct {
	database *db.DatabaseSqlc
	bus      *eventbus.Bus
	wake     chan struct{}

	// mu guards handlers and running, and is held across picking and claiming
	// a job and across canceling one, so the two cannot interleave.
	mu       sync.Mutex
	handlers map[string]Handler
	running  map[int64]runningJob
}

// NewQueueParams configures NewQueue.
type NewQueueParams struct {
	// Database is required.
	Database *db.DatabaseSqlc
	// EventBus receives the job_* events. Nil publishes nothing.
	EventBus *eventbus.Bus
}

// NewQueue returns a queue over the jobs table. Nothing runs until Run is
// called.
func NewQueue(params NewQueueParams) *Queue {
	return &Queue{
		database: params.Database,
		bus:      params.EventBus,
		wake:     make(chan struct{}, 1),
		handlers: map[string]Handler{},
		running:  map[int64]runningJob{},
	}
}

// RegisterParams names a job kind and its Handler.
type RegisterParams struct {
	Kind    string
	Handler Handler
}

// Register sets the Handler for a kind, replacing any earlier one.
func (q *Queue) Register(params RegisterParams) {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.handlers[params.Kind] = params.Handler
}

// EnqueueParams describes a job to queue. Params is encoded as JSON and handed
// back to the kind's Handler when the job runs. The API also returns it to any
// authenticated client, so a kind must never store secrets in it. A kind whose
// job works on a file puts it in Params as "serial" and "relPath", which is
// what Job.Source reads.
type EnqueueParams struct {
	Kind   string
	Name   string
	Params any
	// UserID is the account queueing the job. 0 records none, which leaves the
	// job to admins.
	UserID int64
}

// EnqueueResult carries the newly queued job.
type EnqueueResult struct {
	Job Job
}

// Enqueue stores a pending job in the lane its kind picks, publishes
// job_queued, and wakes the dispatcher. An error from the kind's Lane hook is
// returned wrapped, so callers can match it with errors.Is.
func (q *Queue) Enqueue(ctx context.Context, params EnqueueParams) (EnqueueResult, error) {
	handler, ok := q.handler(params.Kind)
	if !ok {
		return EnqueueResult{}, q.unknownKind(params.Kind)
	}
	encoded, err := json.Marshal(params.Params)
	if err != nil {
		return EnqueueResult{}, fmt.Errorf("encode job params: %w", err)
	}
	lane, err := pickLane(ctx, params.Kind, handler, encoded)
	if err != nil {
		return EnqueueResult{}, err
	}
	row, err := q.database.Queries.CreateJob(ctx, db.CreateJobParams{
		Kind:   params.Kind,
		Name:   params.Name,
		Params: string(encoded),
		Lane:   lane,
		UserID: sql.NullInt64{Int64: params.UserID, Valid: params.UserID != 0},
	})
	if err != nil {
		return EnqueueResult{}, fmt.Errorf("create job: %w", err)
	}
	job := jobFromRow(row)
	q.queued(job)
	return EnqueueResult{Job: job}, nil
}

// GetParams names the job to Get.
type GetParams struct {
	ID int64
}

// GetResult carries the job.
type GetResult struct {
	Job Job
}

// Get returns one job, or ErrJobNotFound.
func (q *Queue) Get(ctx context.Context, params GetParams) (GetResult, error) {
	row, err := q.database.Queries.GetJob(ctx, params.ID)
	if errors.Is(err, sql.ErrNoRows) {
		return GetResult{}, ErrJobNotFound
	}
	if err != nil {
		return GetResult{}, fmt.Errorf("get job: %w", err)
	}
	return GetResult{Job: jobFromRow(row)}, nil
}

// ListParams chooses which kinds to list. Kinds is required, and every entry
// must be a registered kind.
type ListParams struct {
	Kinds []string
}

// ListResult carries the matching jobs, newest first. Jobs is never nil.
type ListResult struct {
	Jobs []Job
}

// List returns every job of the given kinds, newest first. It returns
// ErrKindRequired when Kinds is empty or holds an empty string, and
// ErrUnknownKind, naming the known kinds, for a kind nothing registered.
func (q *Queue) List(ctx context.Context, params ListParams) (ListResult, error) {
	if err := q.checkKinds(params.Kinds); err != nil {
		return ListResult{}, err
	}
	rows, err := q.database.Queries.ListJobs(ctx, params.Kinds)
	if err != nil {
		return ListResult{}, fmt.Errorf("list jobs: %w", err)
	}
	jobs := make([]Job, 0, len(rows))
	for _, row := range rows {
		jobs = append(jobs, jobFromRow(row))
	}
	return ListResult{Jobs: jobs}, nil
}

// CancelParams names the job to Cancel.
type CancelParams struct {
	ID int64
}

// CancelResult carries the job as it stands after canceling.
type CancelResult struct {
	Job Job
}

// Cancel stops a pending or running job and publishes job_canceled. A pending
// job never runs; a running job has its context canceled and its Handler
// cleans up. It returns ErrJobNotFound for an unknown id and ErrJobFinished
// for a job that is already over.
func (q *Queue) Cancel(ctx context.Context, params CancelParams) (CancelResult, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	row, err := q.database.Queries.CancelJob(ctx, params.ID)
	if errors.Is(err, sql.ErrNoRows) {
		if _, getErr := q.Get(ctx, GetParams(params)); getErr != nil {
			return CancelResult{}, getErr
		}
		return CancelResult{}, ErrJobFinished
	}
	if err != nil {
		return CancelResult{}, fmt.Errorf("cancel job: %w", err)
	}
	if running, ok := q.running[params.ID]; ok {
		running.cancel()
	}
	job := jobFromRow(row)
	q.publish(eventbus.EventJobCanceled, job)
	return CancelResult{Job: job}, nil
}

// RetryParams names the job to Retry.
type RetryParams struct {
	ID int64
}

// RetryResult carries the job, reset to pending.
type RetryResult struct {
	Job Job
}

// Retry resets a failed job to pending in the lane its kind picks again,
// clearing its progress, error, and run timestamps while keeping its id and
// CreatedAt, then publishes job_queued and wakes the dispatcher. It returns
// ErrJobNotFound for an unknown id, ErrJobNotRetryable for a job that is not
// failed (or that a racing retry reset first), and ErrRetryRejected when the
// kind's Validate or Lane hook refuses.
func (q *Queue) Retry(ctx context.Context, params RetryParams) (RetryResult, error) {
	row, err := q.database.Queries.GetJob(ctx, params.ID)
	if errors.Is(err, sql.ErrNoRows) {
		return RetryResult{}, ErrJobNotFound
	}
	if err != nil {
		return RetryResult{}, fmt.Errorf("get job: %w", err)
	}
	if Status(row.Status) != StatusFailed {
		return RetryResult{}, ErrJobNotRetryable
	}
	handler, ok := q.handler(row.Kind)
	if !ok {
		return RetryResult{}, q.unknownKind(row.Kind)
	}
	jobParams := json.RawMessage(row.Params)
	if handler.Validate != nil {
		if err := handler.Validate(jobParams); err != nil {
			return RetryResult{}, fmt.Errorf("%w: %w", ErrRetryRejected, err)
		}
	}
	lane, err := pickLane(ctx, row.Kind, handler, jobParams)
	if err != nil {
		return RetryResult{}, fmt.Errorf("%w: %w", ErrRetryRejected, err)
	}
	reset, err := q.database.Queries.RetryJob(ctx, db.RetryJobParams{Lane: lane, ID: params.ID})
	if errors.Is(err, sql.ErrNoRows) {
		return RetryResult{}, ErrJobNotRetryable // another retry reset it first
	}
	if err != nil {
		return RetryResult{}, fmt.Errorf("retry job: %w", err)
	}
	job := jobFromRow(reset)
	q.queued(job)
	return RetryResult{Job: job}, nil
}

// Run is the dispatcher. It first marks jobs a previous process left running
// as failed, then starts the oldest pending job whose lane has a free slot,
// over and over, each on its own goroutine, until none fits. It then sleeps on
// a channel, rather than polling, until a job is queued or one finishes. When
// ctx is canceled, every running job is stopped and marked failed, so it can
// be retried, and Run returns once they all have.
func (q *Queue) Run(ctx context.Context) {
	if err := q.database.Queries.InterruptRunningJobs(ctx, interruptedError); err != nil {
		log.Printf("[jobs] mark interrupted jobs failed: %v", err)
	}
	var jobs sync.WaitGroup
	for ctx.Err() == nil {
		for q.startNext(ctx, &jobs) {
		}
		select {
		case <-ctx.Done():
		case <-q.wake:
		}
	}
	jobs.Wait()
}

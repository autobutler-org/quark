package jobutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"maps"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func jobFromRow(row db.Job) Job {
	params := json.RawMessage(row.Params)
	if s := strings.TrimSpace(row.Params); s == "" || s == "null" {
		params = json.RawMessage("{}")
	}
	return Job{
		ID:         row.ID,
		Kind:       row.Kind,
		Lane:       row.Lane,
		Name:       row.Name,
		Params:     params,
		Status:     Status(row.Status),
		Progress:   row.Progress,
		Attempts:   row.Attempts,
		CreatedAt:  row.CreatedAt,
		StartedAt:  timePtr(row.StartedAt),
		FinishedAt: timePtr(row.FinishedAt),
		Error:      row.Error,
		UserID:     row.UserID.Int64,
	}
}

func timePtr(t sql.NullTime) *time.Time {
	if !t.Valid {
		return nil
	}
	return &t.Time
}

func (q *Queue) handler(kind string) (Handler, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	handler, ok := q.handlers[kind]
	return handler, ok
}

// unknownKind builds ErrUnknownKind naming the kinds that are registered.
func (q *Queue) unknownKind(kind string) error {
	q.mu.Lock()
	known := slices.Sorted(maps.Keys(q.handlers))
	q.mu.Unlock()
	return fmt.Errorf("%w: %q (known kinds: %s)", ErrUnknownKind, kind, strings.Join(known, ", "))
}

// checkKinds validates the kinds a List call filters by.
func (q *Queue) checkKinds(kinds []string) error {
	if len(kinds) == 0 || slices.Contains(kinds, "") {
		return ErrKindRequired
	}
	for _, kind := range kinds {
		if _, ok := q.handler(kind); !ok {
			return q.unknownKind(kind)
		}
	}
	return nil
}

func (q *Queue) publish(kind eventbus.EventKind, job Job) {
	if q.bus != nil {
		q.bus.Publish(eventbus.Event{Kind: kind, Data: job})
	}
}

// queued publishes job_queued for a job that just became pending and wakes the
// dispatcher.
func (q *Queue) queued(job Job) {
	q.publish(eventbus.EventJobQueued, job)
	q.wakeDispatcher()
}

func (q *Queue) wakeDispatcher() {
	select {
	case q.wake <- struct{}{}:
	default: // the dispatcher already has a wake-up waiting
	}
}

// limit is how many jobs may run at once in lane, and whether the Handler has
// that lane at all. A Handler with no Lanes has the one lane "", which runs one
// job at a time.
func (h Handler) limit(lane string) (int, bool) {
	if h.Lanes == nil {
		return 1, lane == ""
	}
	n, ok := h.Lanes[lane]
	return n, ok && n > 0
}

// pickLane asks the kind's Lane hook which lane params belong in and checks
// the kind has a limit for it.
func pickLane(ctx context.Context, kind string, handler Handler, params json.RawMessage) (string, error) {
	lane := ""
	if handler.Lane != nil {
		picked, err := handler.Lane(ctx, params)
		if err != nil {
			return "", fmt.Errorf("choose lane: %w", err)
		}
		lane = picked
	}
	if _, ok := handler.limit(lane); !ok {
		return "", fmt.Errorf("%w: kind %q has no lane %q", ErrUnknownLane, kind, lane)
	}
	return lane, nil
}

// startNext claims the oldest pending job whose lane has a free slot, starts
// it on its own goroutine, and reports whether it started one. It holds the
// lock Cancel takes from reading the running counts through claiming, so no
// two starts can fill the same slot.
// ponytail: it scans every pending job on each start, which is fine for a
// backlog of hundreds; skip full lanes in SQL if backlogs reach thousands.
func (q *Queue) startNext(ctx context.Context, jobs *sync.WaitGroup) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	pending, err := q.database.Queries.ListPendingJobs(ctx)
	if err != nil {
		if ctx.Err() == nil {
			log.Printf("[jobs] list pending jobs: %v", err)
		}
		return false
	}
	busy := map[laneKey]int{}
	for _, running := range q.running {
		busy[running.lane]++
	}
	for _, candidate := range pending {
		lane := laneKey{kind: candidate.Kind, lane: candidate.Lane}
		// A job whose kind or lane is no longer registered gets a slot of one,
		// and fails when it runs rather than waiting forever.
		limit := 1
		if handler, ok := q.handlers[candidate.Kind]; ok {
			if n, known := handler.limit(candidate.Lane); known {
				limit = n
			}
		}
		if busy[lane] >= limit {
			continue
		}
		row, err := q.database.Queries.ClaimJob(ctx, candidate.ID)
		if errors.Is(err, sql.ErrNoRows) {
			continue // canceled since the scan
		}
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("[jobs] claim job %d: %v", candidate.ID, err)
			}
			return false
		}
		jobCtx, cancel := context.WithCancel(ctx)
		q.running[row.ID] = runningJob{lane: lane, cancel: cancel}
		q.publish(eventbus.EventJobStarted, jobFromRow(row))
		jobs.Add(1)
		go func() {
			defer jobs.Done()
			defer cancel()
			q.runJob(ctx, jobCtx, row)
		}()
		return true
	}
	return false
}

// runJob runs one claimed job to its end, records how it ended, and wakes the
// dispatcher, since the job's lane now has a free slot.
func (q *Queue) runJob(ctx, jobCtx context.Context, row db.Job) {
	job := jobFromRow(row)
	report, latest := q.reporter(ctx, job)
	err := q.execute(jobCtx, row, report)
	q.finish(ctx, job.ID, err, latest())
	q.wakeDispatcher()
}

func (q *Queue) execute(ctx context.Context, row db.Job, report func(float64)) error {
	handler, ok := q.handler(row.Kind)
	if !ok {
		return q.unknownKind(row.Kind)
	}
	return handler.Run(WithUserID(ctx, row.UserID.Int64), json.RawMessage(row.Params), report)
}

// reporter returns the progress callback handed to a Handler and a func
// reading the latest fraction it was given. It saves and publishes progress at
// most once per progressInterval unless the fraction has moved by
// progressStep.
func (q *Queue) reporter(ctx context.Context, job Job) (func(float64), func() float64) {
	latest, sent := 0.0, 0.0
	var sentAt time.Time
	report := func(fraction float64) {
		latest = min(max(fraction, 0), 1)
		if latest-sent < progressStep && time.Since(sentAt) < progressInterval {
			return
		}
		sent, sentAt = latest, time.Now()
		updated, err := q.database.Queries.UpdateJobProgress(context.WithoutCancel(ctx), db.UpdateJobProgressParams{
			Progress: latest,
			ID:       job.ID,
		})
		if err != nil {
			log.Printf("[jobs] save progress of job %d: %v", job.ID, err)
			return
		}
		if updated == 0 {
			return // canceled since it started
		}
		snapshot := job
		snapshot.Progress = latest
		q.publish(eventbus.EventJobProgress, snapshot)
	}
	return report, func() float64 { return latest }
}

// finish records how a job's run ended and publishes it. A job canceled while
// its Handler was unwinding is left as Cancel recorded it.
func (q *Queue) finish(ctx context.Context, id int64, runErr error, progress float64) {
	q.mu.Lock()
	defer q.mu.Unlock()
	delete(q.running, id)

	params, kind := finishParams(id, runErr, ctx.Err() != nil, progress)
	// At shutdown ctx is already canceled, and the row still has to be settled.
	row, err := q.database.Queries.FinishJob(context.WithoutCancel(ctx), params)
	if errors.Is(err, sql.ErrNoRows) {
		return
	}
	if err != nil {
		log.Printf("[jobs] finish job %d: %v", id, err)
		return
	}
	q.publish(kind, jobFromRow(row))
}

func finishParams(id int64, runErr error, interrupted bool, progress float64) (db.FinishJobParams, eventbus.EventKind) {
	switch {
	case runErr == nil:
		return db.FinishJobParams{ID: id, Status: string(StatusCompleted), Progress: 1}, eventbus.EventJobCompleted
	case interrupted:
		return db.FinishJobParams{ID: id, Status: string(StatusFailed), Error: interruptedError, Progress: progress}, eventbus.EventJobFailed
	default:
		return db.FinishJobParams{ID: id, Status: string(StatusFailed), Error: runErr.Error(), Progress: progress}, eventbus.EventJobFailed
	}
}

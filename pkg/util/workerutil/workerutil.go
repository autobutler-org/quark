// Package workerutil runs the background worker the server starts beside it: a loop that runs until it is told to
// quit, and a logger for the errors it reports. RunPeriodically runs a maintenance task once per interval however
// many instances share the database.
package workerutil

import (
	"context"
	"crypto/rand"
	"log"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// RunPeriodicallyParams describes a periodic maintenance task.
type RunPeriodicallyParams struct {
	// Queries reaches the database the instances share. Required.
	Queries *db.Queries
	// Name identifies the task across instances: two callers with one Name
	// take turns, so it must be unique to the task.
	Name string
	// Interval is how long after one run starts the next is due.
	Interval time.Duration
	// Run does the task. It is called on RunPeriodically's goroutine.
	Run func()
}

// RunPeriodically runs a task once per Interval across every instance on one
// database (#2966), until ctx is done. It asks for the task's turn at once and
// then every tenth of Interval, and calls Run only when the maintenance_runs
// row says the task last started at least Interval ago and this caller is the
// one that moved it forward. So an instance that starts inside another's
// interval, as each new one does in a rollout, skips the task, and when the
// instance that last ran it is gone another takes the next turn. A turn that
// cannot be asked for is logged and skipped.
func RunPeriodically(ctx context.Context, params RunPeriodicallyParams) {
	owner := rand.Text()
	ticker := time.NewTicker(params.Interval / 10)
	defer ticker.Stop()
	for {
		if claimTurn(ctx, params, owner) {
			params.Run()
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

type Worker interface {
	Process() error
	GetQuitChannel() chan struct{}
	GetErrorChannel() chan error
	LogErrors() error
}

func NewWorker() Worker {
	return &worker{
		quitChannel:  make(chan struct{}),
		errorChannel: make(chan error),
	}
}

func (w *worker) Process() error {
	<-w.quitChannel
	return nil
}

func (w *worker) GetQuitChannel() chan struct{} {
	return w.quitChannel
}

func (w *worker) GetErrorChannel() chan error {
	return w.errorChannel
}

func (w *worker) LogErrors() error {
	for {
		err := <-w.errorChannel
		if err != nil {
			log.Printf("Worker service error: %v\n", err)
		}
	}
}

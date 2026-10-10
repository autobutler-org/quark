package workerutil

import (
	"context"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

////////////////
// Unit tests //
////////////////

func TestNewWorker_ChannelAccessors(t *testing.T) {
	w := NewWorker()
	if w.GetQuitChannel() == nil {
		t.Error("GetQuitChannel returned nil")
	}
	if w.GetErrorChannel() == nil {
		t.Error("GetErrorChannel returned nil")
	}
}

func TestWorker_Process_Quit(t *testing.T) {
	w := NewWorker()
	quit := w.GetQuitChannel()
	done := make(chan struct{})
	go func() {
		err := w.Process()
		if err != nil {
			t.Errorf("Process returned error: %v", err)
		}
		close(done)
	}()
	// Give goroutine time to start
	time.Sleep(10 * time.Millisecond)
	quit <- struct{}{}
	select {
	case <-done:
		// success
	case <-time.After(100 * time.Millisecond):
		t.Error("Process did not exit after quit signal")
	}
}

func TestWorker_LogErrors_ReceivesError(t *testing.T) {
	w := NewWorker()
	errCh := w.GetErrorChannel()
	// Run LogErrors in a goroutine, send an error, and check that it does not panic
	go func() {
		// Give LogErrors time to start
		time.Sleep(10 * time.Millisecond)
		errCh <- logErrorMock{}
		// Give time for log to print
		time.Sleep(10 * time.Millisecond)
	}()
	// LogErrors is an infinite loop, so run it with a timeout
	go func() { w.LogErrors() }()
	// No assertion: just ensure no panic/deadlock
}

type logErrorMock struct{}

func (logErrorMock) Error() string { return "mock error" }

// Two instances ticking on one database run a periodic task once per
// interval between them, not once each (#2966, J7 to J9).
func TestRunPeriodically_RunsOncePerIntervalAcrossInstances(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx, cancel := context.WithCancel(context.Background())
	var runs atomic.Int64
	var instances sync.WaitGroup
	for range 2 {
		instances.Go(func() {
			RunPeriodically(ctx, RunPeriodicallyParams{
				Queries:  database.Queries,
				Name:     "test-task",
				Interval: 2 * time.Second,
				Run:      func() { runs.Add(1) },
			})
		})
	}
	t.Cleanup(func() {
		cancel()
		instances.Wait()
	})

	// The turn is taken on the database's clock, which counts whole seconds,
	// so a second run is more than a second away however the start fell.
	time.Sleep(500 * time.Millisecond)
	if got := runs.Load(); got != 1 {
		t.Fatalf("the task ran %d time(s) in its first interval, want 1", got)
	}
	deadline := time.Now().Add(5 * time.Second)
	for runs.Load() < 2 {
		if time.Now().After(deadline) {
			t.Fatal("the task did not run again in a later interval")
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// An instance that starts inside another's interval, as every new one does in
// a rollout, does not run the task again.
func TestRunPeriodically_SkipsATaskAnotherInstanceJustRan(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	if err := database.Queries.EnsureMaintenanceRun(ctx, "test-task"); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.ClaimMaintenanceRun(ctx, db.ClaimMaintenanceRunParams{
		Owner: "another instance", Name: "test-task", IntervalSeconds: 3600,
	}); err != nil {
		t.Fatal(err)
	}

	runCtx, cancel := context.WithTimeout(ctx, 300*time.Millisecond)
	defer cancel()
	ran := false
	RunPeriodically(runCtx, RunPeriodicallyParams{
		Queries:  database.Queries,
		Name:     "test-task",
		Interval: time.Hour,
		Run:      func() { ran = true },
	})
	if ran {
		t.Error("the task ran again inside the interval another instance ran it in")
	}
}

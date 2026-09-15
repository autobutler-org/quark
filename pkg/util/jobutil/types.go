package jobutil

import (
	"context"
	"time"
)

// ponytail: the jobs table is never pruned, so history grows with every job;
// add retention once someone decides how much of it to keep.
const (
	// interruptedError is the error on a job that was running when its process
	// stopped, whether on a clean shutdown or found at the next startup.
	interruptedError = "interrupted by restart"

	// Progress is saved and published when the fraction has moved by
	// progressStep or progressInterval has passed since it last was.
	progressInterval = time.Second
	progressStep     = 0.01
)

// userIDKey is the context key WithUserID stores the job's account under.
type userIDKey struct{}

// laneKey names a lane. Lanes belong to a kind: one kind's "copy" is not
// another's.
type laneKey struct {
	kind string
	lane string
}

// runningJob is a job the dispatcher started, kept in memory so Cancel can
// reach its context and the dispatcher can count its lane.
type runningJob struct {
	lane   laneKey
	cancel context.CancelFunc
}

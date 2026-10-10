package jobutil

import (
	"context"
	"time"
)

const (
	// interruptedError is the error on a job whose process died while running
	// it for the maxAttempts-th time.
	interruptedError = "interrupted by restart"

	// maxAttempts is how many times a job may start and be left running by a
	// process that died before it is failed rather than queued again, so a
	// job that kills its process does not do it forever.
	maxAttempts = 3

	// An instance beats every defaultHeartbeatInterval, and a running job
	// with no beat for defaultLeaseDuration has lost its owner. The lease is
	// several beats long, so a slow write or two does not cost a job its run.
	defaultHeartbeatInterval = 10 * time.Second
	defaultLeaseDuration     = time.Minute

	// Progress is saved and published when the fraction has moved by
	// progressStep or progressInterval has passed since it last was.
	progressInterval = time.Second
	progressStep     = 0.01
)

// userIDKey is the context key WithUserID stores the job's account under.
type userIDKey struct{}

// jobIDKey is the context key WithJobID stores the running job's id under.
type jobIDKey struct{}

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

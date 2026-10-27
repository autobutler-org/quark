// Package trimutil is the video-trim job kind (#3426): Enqueue validates and
// queues a cut of a video, and the Handler from NewHandler copies the clip
// into a new file beside it when the job runs, without re-encoding. Running
// it as a job puts a trim on the Jobs page with Cancel, like a conversion.
//
// sprocket's Trim reports no progress yet (autobutler-org/sprocket#67), so a
// trim job's progress stays at 0 until it completes and clients show it as
// running without a percentage. When the job completes, its detail holds a
// Result: where the clip landed and where it is shown from.
package trimutil

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// Kind is the jobutil kind trim jobs are stored, registered, and listed
// under. It is the one place the string is spelled.
const Kind = "video-trim"

// LaneCopy is the one lane trim jobs run in, and copyLaneLimit how many run
// at once. A trim copies byte ranges and mostly waits on the disk, as a
// conversion does.
const (
	LaneCopy      = "copy"
	copyLaneLimit = 2
)

var (
	// ErrInvalidRange is returned for a negative start or an end at or before
	// the start.
	ErrInvalidRange = errors.New("invalid trim range")
	// ErrInvalidPath is returned for an empty relPath, the device's root, or a
	// path that escapes it.
	ErrInvalidPath = errors.New("invalid relPath")
	// ErrSourceNotFound is returned when the source is missing, is a folder,
	// or is on a device that is not attached.
	ErrSourceNotFound = errors.New("video not found or not readable")
	// ErrCreatorForbidden fails a job whose creator can no longer read the
	// source or write its folder (#1979).
	ErrCreatorForbidden = errors.New("the account that queued this job can no longer read the video or save files in its folder")
)

// Params is what a trim job stores. StartMs and EndMs are on the source's
// timeline; an EndMs at or past the end of the video keeps the rest of it.
type Params struct {
	RelPath string `json:"relPath"`
	Serial  string `json:"serial"`
	StartMs int64  `json:"startMs"`
	EndMs   int64  `json:"endMs"`
}

// Result is the detail a completed trim job saves.
type Result struct {
	// RelPath is the clip's path on the source's device.
	RelPath string `json:"relPath"`
	// ActualStartMs is where the clip is shown from in the source:
	// videoutil.TrimResult.Start, which is StartMs except where it is a
	// keyframe instead.
	ActualStartMs int64 `json:"actualStartMs"`
}

// TrimFileFunc does the trim. It has the signature of videoutil.TrimFile,
// which is the default; tests pass a fake.
type TrimFileFunc func(ctx context.Context, params videoutil.TrimFileParams) (videoutil.TrimFileResult, error)

// EnqueueParams describes a trim request.
type EnqueueParams struct {
	Queue *jobutil.Queue
	// Registry holds the device files namespaces the source is found in.
	Registry vfs.Registry
	Params   Params
	// UserID is the account queueing the trim, which the job runs as. 0
	// records none.
	UserID int64
}

// EnqueueResult carries the queued job.
type EnqueueResult struct {
	Job jobutil.Job
}

// Enqueue checks the request and queues the job. It returns ErrInvalidRange
// or ErrInvalidPath for a bad request, ErrSourceNotFound when the source is
// missing or its device is not attached, videoutil.ErrNotAVideo when it does
// not probe as a video, and videoutil.ErrStartPastEnd for a start at or past
// its end.
func Enqueue(ctx context.Context, params EnqueueParams) (EnqueueResult, error) {
	src, err := resolveSource(ctx, params.Registry, params.Params)
	if err != nil {
		return EnqueueResult{}, err
	}
	if err := checkStart(ctx, src, params.Params); err != nil {
		return EnqueueResult{}, err
	}
	p := params.Params
	p.RelPath = src.relPath
	result, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   jobName(src),
		Params: p,
		UserID: params.UserID,
	})
	if err != nil {
		return EnqueueResult{}, err
	}
	return EnqueueResult{Job: result.Job}, nil
}

// NewHandlerParams configures NewHandler.
type NewHandlerParams struct {
	// Storage loads a job's creator.
	Storage *storageutil.StorageService
	// Registry holds the device files namespaces sources are read from and
	// clips land in. Without one every job fails with ErrSourceNotFound.
	Registry vfs.Registry
	// Database holds the accounts and access rows a job's creator is checked
	// against, and the job row its Result is saved in.
	Database *db.DatabaseSqlc
	// EventBus receives the upload event for a finished clip. Nil publishes
	// nothing.
	EventBus *eventbus.Bus
	// TrimFile does the trim. Nil means videoutil.TrimFile.
	TrimFile TrimFileFunc
}

// NewHandler returns the jobutil Handler for Kind, in its one lane. Run acts
// as the account that queued the job: it needs read on the source and write
// on its folder, fails with ErrCreatorForbidden or
// accessutil.ErrCreatorInactive otherwise, and makes that account the owner
// of the clip. The clip is written through the namespace's atomic write, so a
// canceled or failed trim leaves no partial file, and a trim canceled just as
// its clip landed removes the clip again. On success Run saves a Result as the
// job's detail and publishes the upload event a new file does. Validate
// refuses a retry whose source no longer exists.
func NewHandler(params NewHandlerParams) jobutil.Handler {
	trimFile := params.TrimFile
	if trimFile == nil {
		trimFile = videoutil.TrimFile
	}
	h := handler{storage: params.Storage, registry: params.Registry, database: params.Database, bus: params.EventBus, trimFile: trimFile}
	return jobutil.Handler{
		Run:      h.run,
		Validate: h.validate,
		Lane:     func(context.Context, json.RawMessage) (string, error) { return LaneCopy, nil },
		Lanes:    map[string]int{LaneCopy: copyLaneLimit},
	}
}

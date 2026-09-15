// Package transcodeutil is the video-transcode job kind: Enqueue validates and
// queues a conversion into any video format, and the Handler from NewHandler
// writes the result into a new file beside the source when the job runs.
package transcodeutil

import (
	"context"
	"errors"
	"fmt"
	"slices"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
)

// Kind is the jobutil kind transcode jobs are stored, registered, and listed
// under. It is the one place the string is spelled.
const Kind = "video-transcode"

// The lanes transcode jobs run in, and how many of each run at once. A
// re-encode already uses every core and a lot of memory, so encodes run one at
// a time. A stream copy mostly waits on the disk and takes seconds, so copies
// get their own lane rather than queueing behind an encode that takes hours.
const (
	LaneEncode = "encode"
	LaneCopy   = "copy"

	encodeLaneLimit = 1
	copyLaneLimit   = 2
)

var (
	// ErrInvalidFormat is returned for a format that is unknown, that this
	// device's ffmpeg cannot write, or that is the source's own format at
	// original quality, which would only copy the file.
	ErrInvalidFormat = errors.New("invalid format")
	// ErrInvalidQuality is returned for a quality other than original or small.
	ErrInvalidQuality = errors.New("quality must be original or small")
	// ErrInvalidPath is returned for an empty relPath or one that escapes the
	// device files directory.
	ErrInvalidPath = errors.New("invalid relPath")
	// ErrSourceNotFound is returned when the source is missing or is not a
	// readable video.
	ErrSourceNotFound = errors.New("video not found or not readable")
	// ErrCreatorForbidden fails a job whose creator can no longer read the
	// source or write its folder (#1979).
	ErrCreatorForbidden = errors.New("the account that queued this job can no longer read the video or save files in its folder")
)

// Params is what a transcode job stores. Paths are resolved again every time
// the job runs, so a retry sees the device's current files directory.
type Params struct {
	RelPath string            `json:"relPath"`
	Serial  string            `json:"serial"`
	Format  videoutil.Format  `json:"format"`
	Quality videoutil.Quality `json:"quality"`
}

// TranscodeFunc does the conversion. It has the signature of
// videoutil.Transcode, which is the default; tests pass a fake.
type TranscodeFunc func(ctx context.Context, params videoutil.TranscodeParams) error

// EnqueueParams describes a transcode request.
type EnqueueParams struct {
	Queue   *jobutil.Queue
	Storage *storageutil.StorageService
	Params  Params
	// UserID is the account queueing the transcode, which the job runs as. 0
	// records none.
	UserID int64
}

// EnqueueResult carries the queued job.
type EnqueueResult struct {
	Job jobutil.Job
}

// Enqueue checks the request and queues the job in LaneCopy when the source's
// streams can be copied into the format, and LaneEncode otherwise. It returns
// ErrInvalidFormat, ErrInvalidQuality, or ErrInvalidPath for a bad request, and
// ErrSourceNotFound when the source does not probe as a video.
func Enqueue(ctx context.Context, params EnqueueParams) (EnqueueResult, error) {
	src, err := resolveSource(params.Storage, params.Params)
	if err != nil {
		return EnqueueResult{}, err
	}
	available, err := videoutil.AvailableFormats()
	if err != nil {
		return EnqueueResult{}, err
	}
	if !slices.Contains(available, params.Params.Format) {
		return EnqueueResult{}, fmt.Errorf("%w: ffmpeg on this device cannot write %s", ErrInvalidFormat, params.Params.Format.Label())
	}

	result, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind: Kind,
		Name: jobName(src, params.Params),
		Params: Params{
			RelPath: src.relPath,
			Serial:  params.Params.Serial,
			Format:  params.Params.Format,
			Quality: params.Params.Quality,
		},
		UserID: params.UserID,
	})
	if err != nil {
		return EnqueueResult{}, err
	}
	return EnqueueResult{Job: result.Job}, nil
}

// NewHandlerParams configures NewHandler.
type NewHandlerParams struct {
	Storage *storageutil.StorageService
	// Database holds the accounts and access rows a job's creator is checked
	// against. A job with a creator fails without one.
	Database *db.DatabaseSqlc
	// EventBus receives the upload event for a finished output. Nil publishes
	// nothing.
	EventBus *eventbus.Bus
	// Transcode does the conversion. Nil means videoutil.Transcode.
	Transcode TranscodeFunc
}

// NewHandler returns the jobutil Handler for Kind, with its encode and copy
// lanes. Run writes the output into the device data dir's tmp/transcode-jobs,
// outside the files tree, moves it beside the source on success without
// replacing any file, removes it on failure or cancel, and publishes the same
// upload event a new file does. Run acts as the account that queued the job:
// it needs read on the source and write on its folder when it starts and again
// just before the output lands, fails with ErrCreatorForbidden or
// accessutil.ErrCreatorInactive otherwise, and makes that account the owner of
// the output. Validate refuses a retry whose source no longer exists, and Lane
// probes the source to choose between the lanes.
func NewHandler(params NewHandlerParams) jobutil.Handler {
	transcode := params.Transcode
	if transcode == nil {
		transcode = videoutil.Transcode
	}
	h := handler{storage: params.Storage, database: params.Database, bus: params.EventBus, transcode: transcode}
	return jobutil.Handler{
		Run:      h.run,
		Validate: h.validate,
		Lane:     h.lane,
		Lanes:    map[string]int{LaneEncode: encodeLaneLimit, LaneCopy: copyLaneLimit},
	}
}

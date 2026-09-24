// Package transcodeutil is the video-transcode job kind: Enqueue validates and
// queues a conversion into another video container, and the Handler from
// NewHandler remuxes the source into a new file beside it when the job runs.
// A conversion copies the streams and never re-encodes them.
package transcodeutil

import (
	"context"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
)

// Kind is the jobutil kind transcode jobs are stored, registered, and listed
// under. It is the one place the string is spelled.
const Kind = "video-transcode"

// LaneCopy is the one lane transcode jobs run in, and copyLaneLimit how many
// run at once. A remux mostly waits on the disk.
const (
	LaneCopy      = "copy"
	copyLaneLimit = 2
)

// QualityOriginal is the one quality a conversion has: the streams are copied
// as they are. Params.Quality may name it or be empty.
const QualityOriginal = "original"

var (
	// ErrInvalidFormat is returned for a format that is unknown, that cannot
	// hold the source's codecs, or that is the source's own, which would only
	// copy the file.
	ErrInvalidFormat = errors.New("invalid format")
	// ErrInvalidQuality is returned for a quality other than original, such as
	// the small quality a re-encode used to offer.
	ErrInvalidQuality = errors.New("quality must be original: a conversion copies the streams and never re-encodes them")
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
	RelPath string           `json:"relPath"`
	Serial  string           `json:"serial"`
	Format  videoutil.Format `json:"format"`
	// Quality is QualityOriginal or empty. It is kept so a request or a queued
	// job from before conversions became remux-only, asking for small, is
	// refused rather than quietly run at full size.
	Quality string `json:"quality,omitempty"`
}

// RemuxFunc does the conversion. It has the signature of videoutil.Remux,
// which is the default; tests pass a fake.
type RemuxFunc func(ctx context.Context, params videoutil.RemuxParams) error

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

// Enqueue checks the request and queues the job. It returns ErrInvalidFormat,
// ErrInvalidQuality, or ErrInvalidPath for a bad request, including a format
// that cannot hold the source's codecs, and ErrSourceNotFound when the source
// does not probe as a video.
func Enqueue(ctx context.Context, params EnqueueParams) (EnqueueResult, error) {
	src, err := resolveSource(params.Storage, params.Params)
	if err != nil {
		return EnqueueResult{}, err
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
	// Remux does the conversion. Nil means videoutil.Remux.
	Remux RemuxFunc
}

// NewHandler returns the jobutil Handler for Kind, in its one lane. Run writes
// the output into the device data dir's tmp/transcode-jobs, outside the files
// tree, moves it beside the source on success without replacing any file,
// removes it on failure or cancel, and publishes the same upload event a new
// file does. Run acts as the account that queued the job:
// it needs read on the source and write on its folder when it starts and again
// just before the output lands, fails with ErrCreatorForbidden or
// accessutil.ErrCreatorInactive otherwise, and makes that account the owner of
// the output. Validate refuses a retry whose source no longer exists, and Lane
// probes the source and refuses a format that cannot hold its codecs, at
// enqueue and again at retry.
func NewHandler(params NewHandlerParams) jobutil.Handler {
	remux := params.Remux
	if remux == nil {
		remux = videoutil.Remux
	}
	h := handler{storage: params.Storage, database: params.Database, bus: params.EventBus, remux: remux}
	return jobutil.Handler{
		Run:      h.run,
		Validate: h.validate,
		Lane:     h.lane,
		Lanes:    map[string]int{LaneCopy: copyLaneLimit},
	}
}

package trimutil

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"path"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// resolveSource checks the range and finds relPath in the files namespace of
// the device with that serial (#2639). A device that is not attached has no
// namespace, so its videos are ErrSourceNotFound rather than whatever the
// internal drive holds at the same path.
func resolveSource(ctx context.Context, registry vfs.Registry, p Params) (source, error) {
	if p.StartMs < 0 {
		return source{}, fmt.Errorf("%w: startMs must be >= 0", ErrInvalidRange)
	}
	if p.EndMs <= p.StartMs {
		return source{}, fmt.Errorf("%w: endMs must be greater than startMs", ErrInvalidRange)
	}
	if p.RelPath == "" {
		return source{}, fmt.Errorf("%w: relPath is required", ErrInvalidPath)
	}
	var fsys vfs.VFS
	if registry != nil {
		fsys, _ = registry.Get(vfs.FilesNamespace(p.Serial))
	}
	if fsys == nil {
		return source{}, fmt.Errorf("%w: no attached device has serial %q", ErrSourceNotFound, p.Serial)
	}
	info, err := fsys.Stat(ctx, p.RelPath)
	switch {
	case errors.Is(err, vfs.ErrPermissionDenied):
		return source{}, ErrInvalidPath
	case err != nil:
		return source{}, fmt.Errorf("%w: %s: %w", ErrSourceNotFound, p.RelPath, err)
	case info.Path == "":
		return source{}, ErrInvalidPath
	case info.IsDir:
		return source{}, fmt.Errorf("%w: %s is a folder", ErrSourceNotFound, p.RelPath)
	}
	return source{fsys: fsys, serial: p.Serial, relPath: info.Path}, nil
}

// checkStart probes the source, so a file that is not a video or a start past
// its end is refused when the trim is asked for rather than when it runs.
func checkStart(ctx context.Context, src source, p Params) error {
	video, err := videoutil.OpenSource(ctx, videoutil.OpenSourceParams{FS: src.fsys, Path: src.relPath})
	if err != nil {
		return fmt.Errorf("%w: %s: %w", ErrSourceNotFound, src.relPath, err)
	}
	defer video.Close()
	info, err := videoutil.ProbeSource(ctx, video)
	if err != nil {
		return err
	}
	if ms(p.StartMs) >= info.Duration {
		return fmt.Errorf("%w: start %d ms, video %d ms", videoutil.ErrStartPastEnd, p.StartMs, info.Duration.Milliseconds())
	}
	return nil
}

// jobName is the job's display text: "Trim clip.mov".
func jobName(src source) string {
	return "Trim " + path.Base(src.relPath)
}

func ms(v int64) time.Duration {
	return time.Duration(v) * time.Millisecond
}

func decodeParams(raw json.RawMessage) (Params, error) {
	var p Params
	if err := json.Unmarshal(raw, &p); err != nil {
		return Params{}, fmt.Errorf("decode trim params: %w", err)
	}
	return p, nil
}

// validate refuses a retry whose source no longer resolves to a file, or
// whose device is no longer attached.
func (h handler) validate(raw json.RawMessage) error {
	p, err := decodeParams(raw)
	if err != nil {
		return err
	}
	_, err = resolveSource(context.Background(), h.registry, p)
	return err
}

func (h handler) run(ctx context.Context, raw json.RawMessage, _ func(float64)) error {
	p, err := decodeParams(raw)
	if err != nil {
		return err
	}
	src, err := resolveSource(ctx, h.registry, p)
	if err != nil {
		return err
	}
	creator, err := h.checkCreator(ctx, p, src)
	if err != nil {
		return err
	}

	// No progress is reported: sprocket's Trim has no progress hook yet
	// (autobutler-org/sprocket#67), and a guess would be a number that lies.
	clip, err := h.trimFile(ctx, videoutil.TrimFileParams{
		FS:    src.fsys,
		Path:  src.relPath,
		Start: ms(p.StartMs),
		End:   ms(p.EndMs),
	})
	if err != nil {
		return err
	}
	// A cancel that arrived as the clip landed still leaves nothing behind.
	if err := ctx.Err(); err != nil {
		if delErr := src.fsys.Delete(context.WithoutCancel(ctx), clip.Path, vfs.DeleteOptions{}); delErr != nil {
			slog.Error("trim: could not remove the clip of a canceled trim", "path", clip.Path, "serial", p.Serial, "err", delErr)
		}
		return err
	}

	// The creator owns the clip, as they would a file they uploaded (#1904).
	// It has already landed, so a failure is logged rather than failing the
	// job.
	settle := context.WithoutCancel(ctx)
	if _, err := accessutil.GrantOwnerIfNeeded(accessutil.GrantOwnerIfNeededParams{
		Ctx:          settle,
		Database:     h.database,
		Access:       creator,
		DeviceSerial: p.Serial,
		Path:         clip.Path,
	}); err != nil {
		slog.Error("access: could not record the owner of a trimmed clip", "path", clip.Path, "serial", p.Serial, "err", err)
	}
	h.saveResult(settle, Result{RelPath: clip.Path, ActualStartMs: clip.Start.Milliseconds()})

	// The event an uploaded file publishes, so open file browsers, the file
	// index, and the content indexer all see the clip.
	if h.bus != nil {
		h.bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: clip.Path, DeviceSerial: p.Serial})
	}
	return nil
}

// saveResult stores result as the job's detail, which is how a client learns
// the clip's name and actual start. The clip is already there, so a failure is
// logged rather than failing the job.
func (h handler) saveResult(ctx context.Context, result Result) {
	if h.database == nil {
		return
	}
	detail, err := json.Marshal(result)
	if err == nil {
		err = h.database.Queries.UpdateJobDetail(ctx, db.UpdateJobDetailParams{Detail: string(detail), ID: jobutil.JobID(ctx)})
	}
	if err != nil {
		slog.Error("trim: could not save the result of a trim", "job", jobutil.JobID(ctx), "path", result.RelPath, "err", err)
	}
}

// checkCreator loads the access of the account that queued the job, as it
// stands now, and requires read on the source and write on its folder
// (#1979). A job with no creator runs as the system.
func (h handler) checkCreator(ctx context.Context, p Params, src source) (accessutil.Access, error) {
	result, err := accessutil.LoadCreator(accessutil.LoadCreatorParams{
		Ctx:      ctx,
		Database: h.database,
		Storage:  h.storage,
		UserID:   jobutil.UserID(ctx),
	})
	if err != nil {
		return accessutil.Access{}, err
	}
	creator := result.Access
	if !creator.Check(p.Serial, src.relPath, accessutil.Read).Readable ||
		!creator.Check(p.Serial, path.Dir(accessutil.Canonical(src.relPath)), accessutil.Write).Allowed {
		return accessutil.Access{}, ErrCreatorForbidden
	}
	return creator, nil
}

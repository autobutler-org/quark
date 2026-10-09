package transcodeutil

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// stagingDirName is the directory, under a device data dir's tmp area, where
// a remux is written until it finishes. It is deliberately outside the
// files tree, so a partial output never shows up in a listing, and on the same
// device as the output, so moving it into place is a link rather than a copy of
// a file that can be many gigabytes.
const stagingDirName = "transcode-jobs"

// stagingPattern names staged outputs. prepareStaging clears only these.
const stagingPattern = "transcode-*"

// resolveSource checks the format and quality and finds relPath in the files
// namespace of the device with that serial (#2639). A device that is not
// attached has no namespace, so its videos are ErrSourceNotFound rather than
// whatever the internal drive holds at the same path. A path escaping the
// namespace is ErrInvalidPath, and one holding no file ErrSourceNotFound.
func resolveSource(ctx context.Context, registry vfs.Registry, p Params) (source, error) {
	if !p.Format.Valid() {
		return source{}, fmt.Errorf("%w: %q is not a video format this device converts to", ErrInvalidFormat, p.Format)
	}
	if p.Quality != "" && p.Quality != QualityOriginal {
		return source{}, ErrInvalidQuality
	}
	if p.RelPath == "" {
		return source{}, fmt.Errorf("%w: relPath is required", ErrInvalidPath)
	}
	if strings.EqualFold(path.Ext(p.RelPath), "."+string(p.Format)) {
		return source{}, fmt.Errorf("%w: the video is already %s", ErrInvalidFormat, p.Format.Label())
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

// open opens the source for reading. A file that has gone is
// ErrSourceNotFound.
func (src source) open(ctx context.Context) (videoutil.Source, error) {
	video, err := videoutil.OpenSource(ctx, videoutil.OpenSourceParams{FS: src.fsys, Path: src.relPath})
	if err != nil {
		return videoutil.Source{}, fmt.Errorf("%w: %s: %w", ErrSourceNotFound, src.relPath, err)
	}
	return video, nil
}

// jobName is the job's display text: "Convert clip.mov to MKV".
func jobName(src source, p Params) string {
	return "Convert " + path.Base(src.relPath) + " to " + p.Format.Label()
}

func decodeParams(raw json.RawMessage) (Params, error) {
	var p Params
	if err := json.Unmarshal(raw, &p); err != nil {
		return Params{}, fmt.Errorf("decode transcode params: %w", err)
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

// lane puts every job in LaneCopy once the source probes as a video whose
// codecs the target format holds, which is the table the formats endpoint
// lists from and Remux acts on.
func (h handler) lane(ctx context.Context, raw json.RawMessage) (string, error) {
	p, err := decodeParams(raw)
	if err != nil {
		return "", err
	}
	src, err := resolveSource(ctx, h.registry, p)
	if err != nil {
		return "", err
	}
	video, err := src.open(ctx)
	if err != nil {
		return "", err
	}
	defer video.Close()
	targets, err := videoutil.Targets(video)
	if err != nil {
		return "", fmt.Errorf("%w: %s", ErrSourceNotFound, p.RelPath)
	}
	if !slices.Contains(targets, p.Format) {
		return "", fmt.Errorf("%w: this video's streams can't be copied into %s", ErrInvalidFormat, p.Format.Label())
	}
	return LaneCopy, nil
}

func (h handler) run(ctx context.Context, raw json.RawMessage, report func(float64)) error {
	p, err := decodeParams(raw)
	if err != nil {
		return err
	}
	src, err := resolveSource(ctx, h.registry, p)
	if err != nil {
		return err
	}
	if _, err := h.checkCreator(ctx, p, src); err != nil {
		return err
	}

	ext := "." + string(p.Format)
	staged, err := h.remuxToStaging(ctx, src, p.Format, ext, report)
	// Cleans up after a failure or cancel; once the move succeeds the staged
	// name is already gone.
	if staged != "" {
		defer func() { _ = os.Remove(staged) }()
	}
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	// Hours may have passed since the job started, so the creator is checked
	// again before anything lands in the files tree.
	creator, err := h.checkCreator(ctx, p, src)
	if err != nil {
		return err
	}
	output, err := moveIntoPlace(ctx, src, staged, ext)
	if err != nil {
		return err
	}

	// The creator owns the output, as they would a file they uploaded (#1904).
	// It has already landed, so a failure is logged rather than failing the
	// job: the creator still reaches it through the write access that let it
	// land.
	if _, err := accessutil.GrantOwnerIfNeeded(accessutil.GrantOwnerIfNeededParams{
		Ctx:          context.WithoutCancel(ctx),
		Database:     h.database,
		Access:       creator,
		DeviceSerial: p.Serial,
		Path:         output,
	}); err != nil {
		slog.Error("access: could not record the owner of a converted video", "path", output, "serial", p.Serial, "err", err)
	}

	// The event a restored or uploaded file publishes, so open file browsers,
	// the file index, and the content indexer all see the new file.
	if h.bus != nil {
		h.bus.Publish(eventbus.Event{
			Kind:         eventbus.EventUpload,
			Path:         output,
			DeviceSerial: p.Serial,
		})
	}
	return nil
}

// remuxToStaging remuxes the source into a new file in its device's staging
// dir and returns that file's host path, which is set whenever the file was
// created, failure or not, so the caller can remove it.
func (h handler) remuxToStaging(ctx context.Context, src source, format videoutil.Format, ext string, report func(float64)) (string, error) {
	video, err := src.open(ctx)
	if err != nil {
		return "", err
	}
	defer video.Close()
	staging, err := prepareStaging(stagingDataDir(h.storage, src.serial))
	if err != nil {
		return "", err
	}
	file, err := os.CreateTemp(staging, stagingPattern+ext)
	if err != nil {
		return "", fmt.Errorf("create staging file: %w", err)
	}
	err = h.remux(ctx, videoutil.RemuxParams{
		Source:     video,
		Output:     file,
		Format:     format,
		OnProgress: report,
	})
	return file.Name(), errors.Join(err, file.Close())
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

// stagingDataDir is the data dir of the device with this serial, which holds
// its tmp area: on the same filesystem as its files, so moving a staged
// output into place is a link rather than a copy. A device the storage
// service cannot report stages under the system data dir; the move then
// copies.
func stagingDataDir(storage *storageutil.StorageService, serial string) string {
	if storage != nil {
		if device, err := storage.FindManagedDeviceBySerial(serial); err == nil && device != nil && device.DataDir != "" {
			return device.DataDir
		}
	}
	return storageutil.GetDataDir()
}

// prepareStaging returns the staging directory under dataDir's tmp area,
// emptied of outputs an earlier process left behind. Two jobs run at the same
// time, so only files older than this process are removed: anything
// newer may be another job's output still being written. Clearing here rather
// than at startup covers every device without enumerating them.
func prepareStaging(dataDir string) (string, error) {
	dir := filepath.Join(dataDir, "tmp", stagingDirName)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("create staging dir: %w", err)
	}
	// Glob fails only on a malformed pattern, and stagingPattern is constant.
	leftovers, _ := filepath.Glob(filepath.Join(dir, stagingPattern))
	for _, leftover := range leftovers {
		if info, err := os.Stat(leftover); err == nil && info.ModTime().Before(processStart) {
			_ = os.Remove(leftover)
		}
	}
	return dir, nil
}

// moveIntoPlace moves the staged output beside the source under the first free
// name, never replacing a file, and returns its path in the namespace. The
// name is chosen now, when the remux is done, and by trying it rather than
// looking first, so it reflects files that appeared while the remux ran.
// MoveFileIn hard-links when it can and otherwise streams a copy through a
// hidden write temp, the same way a finished upload lands.
func moveIntoPlace(ctx context.Context, src source, staged, ext string) (string, error) {
	mover, ok := src.fsys.(vfs.FileMover)
	if !ok {
		return "", errors.New("move transcoded file into place: the namespace cannot take a staged file")
	}
	name := path.Base(src.relPath)
	out, err := videoutil.PlaceUnderFreeName(videoutil.PlaceUnderFreeNameParams{
		Dir:  path.Dir(src.relPath),
		Name: strings.TrimSuffix(name, path.Ext(name)) + ext,
		Place: func(p string) error {
			return mover.MoveFileIn(ctx, staged, p, vfs.WriteOptions{IfNoneMatch: "*"})
		},
	})
	if err != nil {
		return "", fmt.Errorf("move transcoded file into place: %w", err)
	}
	return out, nil
}

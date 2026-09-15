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
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// stagingDirName is the directory, under a device data dir's tmp area, where
// ffmpeg writes a transcode until it finishes. It is deliberately outside the
// files tree, so a partial output never shows up in a listing, and on the same
// device as the output, so moving it into place is a link rather than a copy of
// a file that can be many gigabytes.
const stagingDirName = "transcode-jobs"

// stagingPattern names staged outputs. prepareStaging clears only these.
const stagingPattern = "transcode-*"

// probeTimeout bounds how long choosing a job's lane waits on ffprobe.
const probeTimeout = 10 * time.Second

// maxMoveAttempts bounds how often moveIntoPlace picks a new name after a file
// takes the one it chose. Each retry means yet another file appeared at that
// exact name in the moment since it was checked.
const maxMoveAttempts = 5

// resolveSource checks the format and quality and turns relPath into a path
// inside the files directory of the device with that serial, or the system
// files directory when no device has it.
func resolveSource(storage *storageutil.StorageService, p Params) (source, error) {
	if !p.Format.Valid() {
		return source{}, fmt.Errorf("%w: %q is not a video format this device converts to", ErrInvalidFormat, p.Format)
	}
	if !p.Quality.Valid() {
		return source{}, ErrInvalidQuality
	}
	if p.RelPath == "" {
		return source{}, fmt.Errorf("%w: relPath is required", ErrInvalidPath)
	}
	if p.Quality == videoutil.QualityOriginal && strings.EqualFold(filepath.Ext(p.RelPath), "."+string(p.Format)) {
		return source{}, fmt.Errorf("%w: the video is already %s; choose small quality to shrink it", ErrInvalidFormat, p.Format.Label())
	}
	filesDir, ok := storage.FindDeviceFilesDirBySerial(p.Serial)
	if !ok {
		systemDir, err := storageutil.GetFilesDir()
		if err != nil {
			return source{}, err
		}
		filesDir = systemDir
	}

	cleanFilesDir := filepath.Clean(filesDir)
	fullPath := filepath.Join(cleanFilesDir, p.RelPath)
	if !strings.HasPrefix(fullPath, cleanFilesDir+string(filepath.Separator)) {
		return source{}, ErrInvalidPath
	}
	return source{filesDir: cleanFilesDir, fullPath: fullPath, relPath: relPath(cleanFilesDir, fullPath)}, nil
}

// jobName is the job's display text: "Convert clip.mkv to MOV", with
// " (small)" when the quality is small.
func jobName(src source, p Params) string {
	name := "Convert " + filepath.Base(src.relPath) + " to " + p.Format.Label()
	if p.Quality == videoutil.QualitySmall {
		name += " (small)"
	}
	return name
}

func relPath(filesDir, path string) string {
	// Both paths are built from filesDir, so Rel cannot fail.
	rel, _ := filepath.Rel(filesDir, path)
	return rel
}

func decodeParams(raw json.RawMessage) (Params, error) {
	var p Params
	if err := json.Unmarshal(raw, &p); err != nil {
		return Params{}, fmt.Errorf("decode transcode params: %w", err)
	}
	return p, nil
}

// validate refuses a retry whose source no longer resolves to a file.
func (h handler) validate(raw json.RawMessage) error {
	p, err := decodeParams(raw)
	if err != nil {
		return err
	}
	src, err := resolveSource(h.storage, p)
	if err != nil {
		return err
	}
	if info, err := os.Stat(src.fullPath); err != nil || !info.Mode().IsRegular() {
		return fmt.Errorf("%w: %s", ErrSourceNotFound, p.RelPath)
	}
	return nil
}

// lane puts a job in LaneCopy when its source's streams can be copied into the
// target format, which is exactly when videoutil.Transcode copies them, and in
// LaneEncode otherwise. It probes the source, so it also refuses one that is
// missing or not a video.
func (h handler) lane(ctx context.Context, raw json.RawMessage) (string, error) {
	p, err := decodeParams(raw)
	if err != nil {
		return "", err
	}
	src, err := resolveSource(h.storage, p)
	if err != nil {
		return "", err
	}
	probeCtx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	info, err := videoutil.Probe(probeCtx, src.fullPath)
	if err != nil {
		return "", fmt.Errorf("%w: %s", ErrSourceNotFound, p.RelPath)
	}
	if videoutil.CanCopy(info, p.Format, p.Quality) {
		return LaneCopy, nil
	}
	return LaneEncode, nil
}

func (h handler) run(ctx context.Context, raw json.RawMessage, report func(float64)) error {
	p, err := decodeParams(raw)
	if err != nil {
		return err
	}
	src, err := resolveSource(h.storage, p)
	if err != nil {
		return err
	}
	if _, err := h.checkCreator(ctx, p, src); err != nil {
		return err
	}

	ext := "." + string(p.Format)
	staging, err := prepareStaging(src.filesDir)
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(staging, stagingPattern+ext)
	if err != nil {
		return fmt.Errorf("create staging file: %w", err)
	}
	staged := file.Name()
	_ = file.Close()
	// Cleans up after a failure or cancel; once the move succeeds the staged
	// name is already gone.
	defer func() { _ = os.Remove(staged) }()

	err = h.transcode(ctx, videoutil.TranscodeParams{
		Source:     src.fullPath,
		Output:     staged,
		Format:     p.Format,
		Quality:    p.Quality,
		OnProgress: report,
	})
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
	final, err := moveIntoPlace(ctx, src, staged, ext)
	if err != nil {
		return err
	}
	output := relPath(src.filesDir, final)

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

// prepareStaging returns the staging directory for the device whose files dir
// is filesDir (ConstructFilesDir puts it directly under the data dir), emptied
// of outputs an earlier process left behind. Jobs in different lanes run at
// the same time, so only files older than this process are removed: anything
// newer may be another job's output still being written. Clearing here rather
// than at startup covers every device without enumerating them.
func prepareStaging(filesDir string) (string, error) {
	dir := filepath.Join(filepath.Dir(filesDir), "tmp", stagingDirName)
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
// name, never replacing a file, and returns where it landed. The output name is
// chosen now, when the encode is done, so it reflects files that appeared while
// ffmpeg ran. LocalVFS.MoveFileIn hard-links when it can and otherwise streams
// a copy through a hidden write temp, the same way a finished upload lands.
// A LocalVFS rooted at the source's files dir serves device serials too, which
// the registered files namespace does not.
func moveIntoPlace(ctx context.Context, src source, staged, ext string) (string, error) {
	fsys, err := vfs.NewLocalVFS(src.filesDir, "")
	if err != nil {
		return "", err
	}
	stem := strings.TrimSuffix(filepath.Base(src.fullPath), filepath.Ext(src.fullPath))
	want := filepath.Join(filepath.Dir(src.fullPath), stem+ext)
	for attempt := 0; attempt < maxMoveAttempts; attempt++ {
		final := storageutil.GetNonConflictingPath(want)
		err := fsys.MoveFileIn(ctx, staged, filepath.ToSlash(relPath(src.filesDir, final)), vfs.WriteOptions{IfNoneMatch: "*"})
		if err == nil {
			return final, nil
		}
		if !errors.Is(err, vfs.ErrConflict) {
			return "", fmt.Errorf("move transcoded file into place: %w", err)
		}
	}
	return "", fmt.Errorf("move transcoded file into place: a new file took the chosen name %d times", maxMoveAttempts)
}

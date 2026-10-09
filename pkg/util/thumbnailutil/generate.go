package thumbnailutil

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
)

// Generate renders the thumbnail for a file on disk and commits it to the
// cache. Video sources get a representative frame extracted with ffmpeg first,
// which then goes through the same image pipeline as a photo.
func Generate(params GenerateParams) (GenerateResult, error) {
	thumbSrcPath := params.SourcePath
	if params.IsVideo {
		framePath, cleanup, err := extractVideoFrame(params.Ctx, params.SourcePath)
		if err != nil {
			return GenerateResult{}, err
		}
		defer cleanup()
		thumbSrcPath = framePath
	}

	result, err := photoutil.GenerateThumbnail(photoutil.GenerateThumbnailParams{
		FilePath: thumbSrcPath,
		Width:    params.Width,
		Height:   params.Height,
	})
	if err != nil {
		return GenerateResult{}, err
	}

	// Apply server-side rotation so the cached thumbnail matches the
	// orientation the user has set.
	if params.RotationQuarters != 0 {
		result.Thumbnail = photoutil.ApplyRotation(result.Thumbnail, params.RotationQuarters)
	}

	// The file was just read whole to decode it, so hashing its bytes reads
	// them back from the page cache.
	if !params.IsVideo && params.Queries != nil {
		if source, err := os.Open(params.SourcePath); err != nil {
			slog.Warn("thumbnail: could not open photo to hash it", "path", params.RelPath, "err", err)
		} else {
			storeHashes(params.Queries, params.Serial, params.RelPath, result.DHash, source)
			source.Close()
		}
	}

	modTime, err := writeCache(params.CachedPath, result.Thumbnail, !params.IsVideo && params.Ext == ".png")
	if err != nil {
		return GenerateResult{}, err
	}
	return GenerateResult{CachedModTime: modTime}, nil
}

// GenerateFromReader renders the thumbnail for an already-open source stream
// and commits it to the cache. A source it cannot decode comes back as
// [ErrUnsupportedSource] so a caller with another way to reach the file can
// fall through to it.
func GenerateFromReader(params GenerateFromReaderParams) (GenerateResult, error) {
	result, err := photoutil.GenerateThumbnailFromReader(params.Reader, params.Ext, params.Width, params.Height)
	if err != nil {
		return GenerateResult{}, fmt.Errorf("%w: %w", ErrUnsupportedSource, err)
	}

	if params.RotationQuarters != 0 {
		result.Thumbnail = photoutil.ApplyRotation(result.Thumbnail, params.RotationQuarters)
	}

	if params.Queries != nil {
		storeHashes(params.Queries, params.Serial, params.RelPath, result.DHash, params.Reader)
	}

	modTime, err := writeCache(params.CachedPath, result.Thumbnail, params.Ext == ".png")
	if err != nil {
		return GenerateResult{}, err
	}
	return GenerateResult{CachedModTime: modTime}, nil
}

// BufferSource holds a source that cannot seek, such as an archive entry, in
// memory so [GenerateFromReader] can take it. It reads at most
// [MaxBufferedSourceBytes]; a larger source is [ErrUnsupportedSource] rather
// than a truncated image.
func BufferSource(r io.Reader) (io.ReadSeeker, error) {
	data, err := io.ReadAll(io.LimitReader(r, MaxBufferedSourceBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > MaxBufferedSourceBytes {
		return nil, fmt.Errorf("%w: source is over %d bytes", ErrUnsupportedSource, MaxBufferedSourceBytes)
	}
	return bytes.NewReader(data), nil
}

// storeHashes records a photo's hashes for duplicate detection. A failure is
// logged rather than returned: it must not cost the caller its thumbnail.
func storeHashes(queries *db.Queries, serial, relPath, dhash string, source io.ReadSeeker) {
	if _, err := photoutil.StorePhotoHashes(photoutil.StorePhotoHashesParams{
		Ctx: context.Background(), Queries: queries,
		Serial: serial, RelPath: relPath, DHash: dhash, Source: source,
	}); err != nil {
		slog.Warn("thumbnail: could not store photo hashes", "path", relPath, "serial", serial, "err", err)
	}
}

// extractVideoFrame writes a representative frame of a video to a temporary
// JPEG and returns its path along with the cleanup that removes it. The
// timestamp is 2s in, or a tenth of the way through a video too short for
// that to land inside it.
func extractVideoFrame(ctx context.Context, videoPath string) (string, func(), error) {
	if !videoutil.Available() {
		return "", nil, ErrFFmpegUnavailable
	}

	probeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	seekTs := 2 * time.Second
	if info, probeErr := videoutil.Probe(probeCtx, videoPath); probeErr == nil {
		if tenth := info.Duration / 10; info.Duration < 20*time.Second && tenth < seekTs {
			seekTs = tenth
		}
	}

	tmpFile, tmpErr := os.CreateTemp("", "vthumb-*.jpg")
	if tmpErr != nil {
		return "", nil, fmt.Errorf("video thumb temp file: %w", tmpErr)
	}
	tmpFile.Close()
	framePath := tmpFile.Name()
	cleanup := func() { os.Remove(framePath) }

	extractCtx, extractCancel := context.WithTimeout(ctx, 30*time.Second)
	defer extractCancel()
	if extractErr := videoutil.ExtractFrame(extractCtx, videoPath, seekTs, framePath); extractErr != nil {
		cleanup()
		return "", nil, fmt.Errorf("extract video frame: %w", extractErr)
	}
	return framePath, cleanup, nil
}

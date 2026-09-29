package thumbnailutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"image"
	// Registers the JPEG decoder an uploaded thumbnail is checked against.
	_ "image/jpeg"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// sizeClient keys the thumbnail a client uploaded. It is the source the
// served tiers are resized from, not a tier itself.
const sizeClient Size = "client"

// maxClientThumbnailEdge is the longest side an uploaded thumbnail may have:
// generous against the 400 clients send, tight enough to refuse a full-size
// photo passed off as a thumbnail.
const maxClientThumbnailEdge = 1024

// NeedsClientRender reports whether a file is one only a client can render a
// thumbnail for: video, whose H.264 and HEVC frames the device does not
// decode, and HEIC. The device answers a missing thumbnail for these with
// clientRender set, so a client knows to render one and PUT it.
func NeedsClientRender(name string) bool {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".heic", ".heif":
		return true
	}
	return storageutil.DetermineFileTypeFromPath(name) == storageutil.FileTypeVideo
}

// clientThumbnailPath is where the thumbnail a client uploaded for a file is
// cached. The path is spelled the way the photo tables key it, so the upload
// and every request find the same entry whatever slashes they carry.
func clientThumbnailPath(serial, relPath string) (string, error) {
	dir, err := CacheDir()
	if err != nil {
		return "", err
	}
	canonical := strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(relPath)), "/")
	return filepath.Join(dir, CacheKey(serial, canonical, 0, sizeClient)), nil
}

// StoreClientThumbnail validates a thumbnail a client rendered and caches it
// as the source of the file's size tiers, replacing any earlier one. A
// photo's thumbnail is hashed for near-duplicate detection on the way in.
func StoreClientThumbnail(params StoreClientThumbnailParams) (StoreClientThumbnailResult, error) {
	target, err := clientThumbnailPath(params.Serial, params.RelPath)
	if err != nil {
		return StoreClientThumbnailResult{}, err
	}
	tmp, err := os.CreateTemp(filepath.Dir(target), filepath.Base(target)+".*.tmp")
	if err != nil {
		return StoreClientThumbnailResult{}, fmt.Errorf("create thumbnail temp file: %w", err)
	}
	tmpPath := tmp.Name()
	committed := false
	defer func() {
		tmp.Close()
		if !committed {
			os.Remove(tmpPath)
		}
	}()

	n, err := io.Copy(tmp, io.LimitReader(params.Reader, MaxClientThumbnailBytes+1))
	if err != nil {
		return StoreClientThumbnailResult{}, fmt.Errorf("write thumbnail: %w", err)
	}
	if n > MaxClientThumbnailBytes {
		return StoreClientThumbnailResult{}, fmt.Errorf("%w: larger than %d bytes", ErrInvalidThumbnail, MaxClientThumbnailBytes)
	}
	if _, err := tmp.Seek(0, io.SeekStart); err != nil {
		return StoreClientThumbnailResult{}, fmt.Errorf("rewind thumbnail: %w", err)
	}
	cfg, format, err := image.DecodeConfig(tmp)
	if err != nil || format != "jpeg" {
		return StoreClientThumbnailResult{}, fmt.Errorf("%w: not a JPEG", ErrInvalidThumbnail)
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > maxClientThumbnailEdge || cfg.Height > maxClientThumbnailEdge {
		return StoreClientThumbnailResult{}, fmt.Errorf("%w: %dx%d is over %d on a side",
			ErrInvalidThumbnail, cfg.Width, cfg.Height, maxClientThumbnailEdge)
	}

	if !params.IsVideo && params.Queries != nil {
		width, height := Dimensions(SizeLg)
		thumb, err := decodeClientThumbnail(tmpPath, width, height)
		if err != nil {
			return StoreClientThumbnailResult{}, fmt.Errorf("%w: %w", ErrInvalidThumbnail, err)
		}
		if err := upsertDHash(params.Queries, params.Serial, params.RelPath, thumb); err != nil {
			return StoreClientThumbnailResult{}, err
		}
	}

	if err := tmp.Close(); err != nil {
		return StoreClientThumbnailResult{}, fmt.Errorf("close thumbnail: %w", err)
	}
	if err := os.Rename(tmpPath, target); err != nil {
		return StoreClientThumbnailResult{}, fmt.Errorf("commit thumbnail: %w", err)
	}
	committed = true
	return StoreClientThumbnailResult{CachedPath: target}, nil
}

// FromClientThumbnail serves a size tier resized from the thumbnail a client
// uploaded for the file. The tier is cached under its usual key and counts as
// stale once the file or its client thumbnail is newer than it. Resizing a
// 400px JPEG is cheap, so this does not wait on the IO semaphore generation
// does.
func FromClientThumbnail(params FromClientThumbnailParams) (FromClientThumbnailResult, error) {
	source, err := clientThumbnailPath(params.Serial, params.RelPath)
	if err != nil {
		return FromClientThumbnailResult{}, err
	}
	info, err := os.Stat(source)
	if errors.Is(err, os.ErrNotExist) {
		return FromClientThumbnailResult{}, nil
	}
	if err != nil {
		return FromClientThumbnailResult{}, fmt.Errorf("stat client thumbnail: %w", err)
	}
	// A thumbnail older than its file shows content the file no longer has.
	if info.ModTime().Before(params.SourceModTime) {
		return FromClientThumbnailResult{}, nil
	}

	prepared, err := Prepare(PrepareParams{
		Queries:    params.Queries,
		Serial:     params.Serial,
		RelPath:    params.RelPath,
		FilePath:   params.FilePath,
		Size:       params.Size,
		SrcModTime: info.ModTime(),
	})
	if err != nil {
		return FromClientThumbnailResult{}, err
	}
	if prepared.Hit {
		return FromClientThumbnailResult{Found: true, CachedPath: prepared.CachedPath, CachedModTime: prepared.CachedModTime}, nil
	}

	thumb, err := decodeClientThumbnail(source, prepared.Width, prepared.Height)
	if err != nil {
		return FromClientThumbnailResult{}, err
	}
	if prepared.RotationQuarters != 0 {
		thumb = photoutil.ApplyRotation(thumb, prepared.RotationQuarters)
	}
	modTime, err := writeCache(prepared.CachedPath, thumb, false)
	if err != nil {
		return FromClientThumbnailResult{}, err
	}
	return FromClientThumbnailResult{Found: true, CachedPath: prepared.CachedPath, CachedModTime: modTime}, nil
}

// StoreClientThumbnails attaches the "thumbnail" part of a multipart body to
// a photo or video the caller may write.
func StoreClientThumbnails(params StoreClientThumbnailsParams) (StoreClientThumbnailsResult, error) {
	fileType := storageutil.DetermineFileTypeFromPath(params.RelPath)
	if fileType != storageutil.FileTypeImage && fileType != storageutil.FileTypeVideo {
		return StoreClientThumbnailsResult{}, ErrNotMedia
	}
	resolved, err := params.Storage.ResolvePath(storageutil.ResolvePathParams{RelPath: params.RelPath, Serial: params.Serial})
	if err != nil {
		return StoreClientThumbnailsResult{}, fmt.Errorf("%w: %w", ErrSourceNotFound, err)
	}
	if info, err := os.Stat(resolved.FullPath); err != nil || info.IsDir() {
		return StoreClientThumbnailsResult{}, ErrSourceNotFound
	}

	for {
		part, err := params.Reader.NextPart()
		if errors.Is(err, io.EOF) {
			return StoreClientThumbnailsResult{}, ErrNoThumbnail
		}
		if err != nil {
			return StoreClientThumbnailsResult{}, fmt.Errorf("%w: %w", ErrInvalidThumbnail, err)
		}
		if part.FormName() != "thumbnail" {
			part.Close()
			continue
		}
		_, err = StoreClientThumbnail(StoreClientThumbnailParams{
			Queries: params.Queries,
			Serial:  params.Serial,
			RelPath: params.RelPath,
			Reader:  part,
			IsVideo: fileType == storageutil.FileTypeVideo,
		})
		part.Close()
		return StoreClientThumbnailsResult{}, err
	}
}

// decodeClientThumbnail decodes a client thumbnail and crops it to a tier.
func decodeClientThumbnail(file string, width, height uint) (image.Image, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, fmt.Errorf("open client thumbnail: %w", err)
	}
	defer f.Close()
	result, err := photoutil.GenerateThumbnailFromReader(f, ".jpg", width, height)
	if err != nil {
		return nil, fmt.Errorf("resize client thumbnail: %w", err)
	}
	return result.Thumbnail, nil
}

// upsertDHash records the perceptual hash near-duplicate detection compares,
// keyed by the path spelled the way the photo tables spell it.
func upsertDHash(queries *db.Queries, serial, relPath string, img image.Image) error {
	if err := queries.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
		DeviceSerial: serial,
		RelPath:      strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(relPath)), "/"),
		Dhash:        sql.NullString{String: photoutil.DHashHex(img), Valid: true},
	}); err != nil {
		return fmt.Errorf("store perceptual hash: %w", err)
	}
	return nil
}

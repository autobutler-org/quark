package thumbnailutil

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// cacheVersion is bumped whenever the thumbnail generation algorithm
// changes, so that stale cached thumbnails are automatically regenerated.
// v3: HEIC/HEIF thumbnails were rotated twice, once by libheif and once from
// the EXIF tag (#1798). The already-sideways entries are only rewritten when
// the key moves, because a cache entry newer than its source is a hit.
const cacheVersion = "v3"

// CacheDir returns the path to the thumbnail cache directory, creating it if
// it doesn't exist.
func CacheDir() (string, error) {
	dir := filepath.Join(storageutil.GetDataDir(), "cache", "thumbnails")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create thumbnail cache directory: %w", err)
	}
	return dir, nil
}

// CacheKey computes a SHA-256 hex digest of the given serial, file path,
// rotation, and size so that each combination produces a distinct cache entry.
func CacheKey(serial, filePath string, rotationQuarters int64, size Size) string {
	h := sha256.Sum256([]byte(fmt.Sprintf("%s:%s/%s:r%d:s%s", cacheVersion, serial, filePath, rotationQuarters, size)))
	return fmt.Sprintf("%x", h)
}

// Prepare resolves a thumbnail request to its cache entry: the user's
// server-side rotation, the target dimensions, and whether the entry on disk
// is still newer than the source. Rotation and size are part of the key, so
// each combination gets its own entry.
func Prepare(params PrepareParams) (PrepareResult, error) {
	var rotationQuarters int64
	if rq, err := params.Queries.GetPhotoRotation(
		context.Background(),
		db.GetPhotoRotationParams{DeviceSerial: params.Serial, RelPath: params.RelPath},
	); err == nil {
		rotationQuarters = rq
	} else if !errors.Is(err, sql.ErrNoRows) {
		return PrepareResult{}, fmt.Errorf("get photo rotation: %w", err)
	}

	dir, err := CacheDir()
	if err != nil {
		return PrepareResult{}, err
	}
	cachedPath := filepath.Join(dir, CacheKey(params.Serial, params.FilePath, rotationQuarters, params.Size))
	width, height := Dimensions(params.Size)

	result := PrepareResult{
		CachedPath:       cachedPath,
		RotationQuarters: rotationQuarters,
		Width:            width,
		Height:           height,
	}
	if cachedInfo, cacheErr := os.Stat(cachedPath); cacheErr == nil {
		result.CachedModTime = cachedInfo.ModTime()
		result.Hit = cachedInfo.ModTime().After(params.SrcModTime)
	}
	return result, nil
}

// OpenCached opens a committed cache entry for the caller to stream. It hands
// back the *os.File rather than the bytes so the response can be served with
// http.ServeContent, which brings Content-Length and range support along and
// keeps the entry off the heap (#1723). The caller owns the file.
func OpenCached(cachedPath string) (*os.File, error) {
	f, err := os.Open(cachedPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read cached thumbnail: %w", err)
	}
	return f, nil
}

// writeCache encodes img and commits it to cachedPath through a temporary
// file, so a reader never sees a half-written thumbnail. It returns the
// committed entry's modification time, which the ETag is derived from.
func writeCache(cachedPath string, img image.Image, encodePNG bool) (time.Time, error) {
	tmpPath := cachedPath + ".tmp"
	f, err := os.Create(tmpPath)
	if err != nil {
		return time.Time{}, fmt.Errorf("failed to create cache file: %w", err)
	}

	if encodePNG {
		err = png.Encode(f, img)
	} else {
		err = jpeg.Encode(f, img, &jpeg.Options{Quality: 85})
	}
	f.Close()
	if err != nil {
		os.Remove(tmpPath)
		return time.Time{}, fmt.Errorf("failed to encode thumbnail to cache: %w", err)
	}

	if err := os.Rename(tmpPath, cachedPath); err != nil {
		os.Remove(tmpPath)
		return time.Time{}, fmt.Errorf("failed to commit cache file: %w", err)
	}

	info, err := os.Stat(cachedPath)
	if err != nil {
		return time.Time{}, err
	}
	return info.ModTime(), nil
}

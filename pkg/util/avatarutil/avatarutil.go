// Package avatarutil stores, serves and removes profile pictures. An upload is
// spooled to disk under a size cap, decoded, center-cropped and resized to
// [Size]x[Size], and re-encoded; only that re-encoded file is kept, so nothing
// the uploader embedded (EXIF, GPS) survives. Pictures live in the Quark's
// data directory as avatars/<user id>.jpg or .png, outside every user's home,
// and the file's modification time is the version clients cache against.
package avatarutil

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
)

// MaxUploadBytes caps an upload before it is decoded.
const MaxUploadBytes int64 = 10 << 20

// MaxPixels caps a source image's decoded size. A 10 MiB PNG can declare a
// canvas that would take gigabytes to decode.
// ponytail: fixed cap, well above any phone camera's default resolution.
const MaxPixels = 64_000_000

// Size is the edge length of a stored picture, in pixels.
const Size = 256

var (
	// ErrTooLarge reports an upload over MaxUploadBytes.
	ErrTooLarge = errors.New("the picture is larger than 10 MiB")
	// ErrNotImage reports an upload that is not a decodable image, or one
	// whose dimensions exceed MaxPixels.
	ErrNotImage = errors.New("the upload is not a supported image")
	// ErrNotFound reports a user with no picture.
	ErrNotFound = errors.New("no profile picture")
)

// SaveParams is a new picture for a user.
type SaveParams struct {
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
	UserID  int64
	// Source streams the uploaded image. At most MaxUploadBytes+1 bytes are
	// read from it.
	Source io.Reader
}

// SaveResult reports the stored picture.
type SaveResult struct {
	// UpdatedAt is the stored file's modification time, the picture's version.
	UpdatedAt time.Time
}

// OpenParams names the user whose picture to open.
type OpenParams struct {
	DataDir string
	UserID  int64
}

// OpenResult is an open picture. The caller closes File.
type OpenResult struct {
	File        *os.File
	UpdatedAt   time.Time
	ContentType string
}

// StatParams names the user whose picture to look up.
type StatParams struct {
	DataDir string
	UserID  int64
}

// StatResult says whether a user has a picture and which version.
type StatResult struct {
	Exists    bool
	UpdatedAt time.Time
}

// RemoveParams names the user whose picture to remove.
type RemoveParams struct {
	DataDir string
	UserID  int64
}

// RemoveResult reports whether there was a picture to remove.
type RemoveResult struct {
	Removed bool
}

// RemoveAllParams locates every stored picture.
type RemoveAllParams struct {
	DataDir string
}

// Dir returns the directory pictures are stored in.
func Dir(dataDir string) string {
	return filepath.Join(dataDir, "avatars")
}

// Save replaces a user's picture with the image read from Source. An upload
// over MaxUploadBytes is ErrTooLarge and one that does not decode is
// ErrNotImage; in both cases the previous picture is left alone.
func Save(params SaveParams) (SaveResult, error) {
	dir := Dir(params.DataDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return SaveResult{}, fmt.Errorf("create avatars directory: %w", err)
	}

	// Spooled to the data directory, not /tmp, which is RAM on some devices.
	spool, err := os.CreateTemp(dir, ".upload-*")
	if err != nil {
		return SaveResult{}, fmt.Errorf("create upload spool: %w", err)
	}
	defer os.Remove(spool.Name())
	defer spool.Close()

	n, err := io.Copy(spool, io.LimitReader(params.Source, MaxUploadBytes+1))
	if err != nil {
		return SaveResult{}, fmt.Errorf("read upload: %w", err)
	}
	if n > MaxUploadBytes {
		return SaveResult{}, ErrTooLarge
	}

	ext, err := sniffImage(spool)
	if err != nil {
		return SaveResult{}, err
	}

	keep, drop := ".jpg", ".png"
	if ext == ".png" {
		keep, drop = ".png", ".jpg"
	}
	target := filepath.Join(dir, fmt.Sprintf("%d%s", params.UserID, keep))
	generated, err := thumbnailutil.GenerateFromReader(thumbnailutil.GenerateFromReaderParams{
		Reader:     spool,
		Ext:        ext,
		Width:      Size,
		Height:     Size,
		CachedPath: target,
	})
	if errors.Is(err, thumbnailutil.ErrUnsupportedSource) {
		return SaveResult{}, fmt.Errorf("%w: %w", ErrNotImage, err)
	}
	if err != nil {
		return SaveResult{}, err
	}
	if err := os.Remove(filepath.Join(dir, fmt.Sprintf("%d%s", params.UserID, drop))); err != nil && !os.IsNotExist(err) {
		return SaveResult{}, fmt.Errorf("remove previous picture: %w", err)
	}
	return SaveResult{UpdatedAt: generated.CachedModTime}, nil
}

// Stat reports whether a user has a picture and its version.
func Stat(params StatParams) (StatResult, error) {
	_, info, err := find(params.DataDir, params.UserID)
	if errors.Is(err, ErrNotFound) {
		return StatResult{}, nil
	}
	if err != nil {
		return StatResult{}, err
	}
	return StatResult{Exists: true, UpdatedAt: info.ModTime()}, nil
}

// Open opens a user's picture for streaming, or returns ErrNotFound.
func Open(params OpenParams) (OpenResult, error) {
	path, info, err := find(params.DataDir, params.UserID)
	if err != nil {
		return OpenResult{}, err
	}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return OpenResult{}, ErrNotFound
	}
	if err != nil {
		return OpenResult{}, fmt.Errorf("open picture: %w", err)
	}
	return OpenResult{
		File:        f,
		UpdatedAt:   info.ModTime(),
		ContentType: thumbnailutil.ContentTypeForExt(filepath.Ext(path)),
	}, nil
}

// Remove deletes a user's picture. A user with none is not an error.
func Remove(params RemoveParams) (RemoveResult, error) {
	var result RemoveResult
	for _, ext := range []string{".jpg", ".png"} {
		err := os.Remove(filepath.Join(Dir(params.DataDir), fmt.Sprintf("%d%s", params.UserID, ext)))
		if err == nil {
			result.Removed = true
		} else if !os.IsNotExist(err) {
			return result, fmt.Errorf("remove picture: %w", err)
		}
	}
	return result, nil
}

// RemoveAll deletes every stored picture, for a Quark whose accounts are
// reset and whose ids will be handed out again.
func RemoveAll(params RemoveAllParams) error {
	if err := os.RemoveAll(Dir(params.DataDir)); err != nil {
		return fmt.Errorf("remove pictures: %w", err)
	}
	return nil
}

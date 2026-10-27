package thumbnailutil

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/audiotagutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// PrepareCover resolves a track's cover thumbnail to its cache entry. The
// entry is keyed by the picture's hash and the size, not the track's path, so
// every track of an album shares one entry per size, and since the key is the
// content, an entry that exists is a hit. A track the library has no row for,
// or whose row names no cover, is [ErrNoCover].
func PrepareCover(params PrepareCoverParams) (PrepareCoverResult, error) {
	row, err := params.Queries.GetMusicTrack(params.Ctx, db.GetMusicTrackParams{
		Serial: params.Serial, RelPath: params.RelPath,
	})
	if errors.Is(err, sql.ErrNoRows) || (err == nil && (row.CoverSource == "" || row.CoverKey == "")) {
		return PrepareCoverResult{}, ErrNoCover
	}
	if err != nil {
		return PrepareCoverResult{}, fmt.Errorf("get music track: %w", err)
	}

	dir, err := CacheDir()
	if err != nil {
		return PrepareCoverResult{}, err
	}
	width, height := Dimensions(params.Size)
	result := PrepareCoverResult{
		CachedPath:  filepath.Join(dir, coverCacheKey(row.CoverKey, params.Size)),
		CoverSource: row.CoverSource,
		CoverKey:    row.CoverKey,
		Width:       width,
		Height:      height,
		Resize:      ResizeFor(params.Size),
	}
	if cachedInfo, cacheErr := os.Stat(result.CachedPath); cacheErr == nil {
		result.CachedModTime = cachedInfo.ModTime()
		result.Hit = true
	}
	return result, nil
}

// GenerateCover renders a track's cover from the source [PrepareCover]
// found: the picture embedded in the track, re-read through audiotagutil's
// bounded tag reader, or the image beside it in its folder, streamed through
// the namespace. The picture must still hash to the key the library recorded,
// since other tracks share the entry; one that does not is [ErrNoCover] until
// the library rereads the track. A picture that will not decode is
// [ErrUnsupportedSource].
func GenerateCover(params GenerateCoverParams) (GenerateResult, error) {
	source, ext, closeSource, err := openCover(params)
	if err != nil {
		return GenerateResult{}, err
	}
	defer closeSource()
	result, err := photoutil.GenerateThumbnailFromReader(source, ext, params.Width, params.Height, params.Resize)
	if err != nil {
		return GenerateResult{}, fmt.Errorf("%w: %w", ErrUnsupportedSource, err)
	}
	modTime, err := writeCache(params.CachedPath, result.Thumbnail, false)
	if err != nil {
		return GenerateResult{}, err
	}
	return GenerateResult{CachedModTime: modTime}, nil
}

// openCover opens the cover params.CoverSource names, checked against
// params.CoverKey, with the extension that names its format and a func that
// releases it.
func openCover(params GenerateCoverParams) (io.ReadSeeker, string, func(), error) {
	switch {
	case params.CoverSource == "embedded":
		return openEmbeddedCover(params)
	case strings.HasPrefix(params.CoverSource, "folder:"):
		name := strings.TrimPrefix(params.CoverSource, "folder:")
		if name == "" || strings.ContainsAny(name, `/\`) {
			return nil, "", nil, ErrNoCover
		}
		return openFolderCover(params, path.Join(path.Dir(params.RelPath), name))
	}
	return nil, "", nil, ErrNoCover
}

// openEmbeddedCover reads the picture embedded in the track. It is at most
// audiotagutil.MaxTagBytes, a bound the tag reader holds it to, so it is
// held whole.
func openEmbeddedCover(params GenerateCoverParams) (io.ReadSeeker, string, func(), error) {
	info, err := params.FS.Stat(params.Ctx, params.RelPath)
	if errors.Is(err, vfs.ErrNotFound) {
		return nil, "", nil, ErrNoCover
	}
	if err != nil {
		return nil, "", nil, err
	}
	f, err := params.FS.Open(params.Ctx, params.RelPath)
	if err != nil {
		return nil, "", nil, fmt.Errorf("open %s: %w", params.RelPath, err)
	}
	defer f.Close()
	picture, err := audiotagutil.ReadPicture(audiotagutil.ReadPictureParams{File: f, Size: info.Size})
	if errors.Is(err, audiotagutil.ErrNoPicture) {
		return nil, "", nil, ErrNoCover
	}
	if err != nil {
		return nil, "", nil, fmt.Errorf("%w: %w", ErrUnsupportedSource, err)
	}
	sum := sha256.Sum256(picture.Data)
	if hex.EncodeToString(sum[:]) != params.CoverKey {
		return nil, "", nil, ErrNoCover
	}
	ext := ".jpg"
	if picture.MIMEType == "image/png" {
		ext = ".png"
	}
	return bytes.NewReader(picture.Data), ext, func() {}, nil
}

// openFolderCover opens the folder image at coverPath, hashes it as it
// streams by, and rewinds it for decoding. One larger than
// audiotagutil.MaxTagBytes was passed over by the scan, so it is no cover.
func openFolderCover(params GenerateCoverParams, coverPath string) (io.ReadSeeker, string, func(), error) {
	f, err := params.FS.Open(params.Ctx, coverPath)
	if errors.Is(err, vfs.ErrNotFound) {
		return nil, "", nil, ErrNoCover
	}
	if err != nil {
		return nil, "", nil, fmt.Errorf("open %s: %w", coverPath, err)
	}
	h := sha256.New()
	n, err := io.Copy(h, io.LimitReader(f, audiotagutil.MaxTagBytes+1))
	if err == nil {
		_, err = f.Seek(0, io.SeekStart)
	}
	if err != nil {
		f.Close()
		return nil, "", nil, fmt.Errorf("read %s: %w", coverPath, err)
	}
	if n > audiotagutil.MaxTagBytes || hex.EncodeToString(h.Sum(nil)) != params.CoverKey {
		f.Close()
		return nil, "", nil, ErrNoCover
	}
	return f, strings.ToLower(path.Ext(coverPath)), func() { f.Close() }, nil
}

// coverCacheKey is the cache entry of a cover at a size: the picture's hash,
// not any one track's path.
func coverCacheKey(coverKey string, size Size) string {
	h := sha256.Sum256([]byte(fmt.Sprintf("%s:cover:%s:s%s", cacheVersion, coverKey, size)))
	return fmt.Sprintf("%x", h)
}

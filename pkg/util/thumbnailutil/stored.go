package thumbnailutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"image"
	"io"
	"os"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// FromStore serves a size tier resized from the thumbnail the client uploaded
// for the file. The tier is cached the same way a generated one is, under the
// same key, and counts as stale once either the file or its stored thumbnail
// is newer than it. Decoding a 400px JPEG is cheap, so this does not wait on
// the IO semaphore generation does.
func FromStore(params FromStoreParams) (FromStoreResult, error) {
	stored, err := derivativeutil.Lookup(derivativeutil.LookupParams{
		SourcePath:    params.SourcePath,
		Kind:          derivativeutil.KindThumbnail,
		SourceModTime: params.SourceModTime,
	})
	if err != nil || !stored.Found {
		return FromStoreResult{}, err
	}

	newest := params.SourceModTime
	if stored.ModTime.After(newest) {
		newest = stored.ModTime
	}
	prepared, err := Prepare(PrepareParams{
		Queries:    params.Queries,
		Serial:     params.Serial,
		RelPath:    params.RelPath,
		FilePath:   params.FilePath,
		Size:       params.Size,
		SrcModTime: newest,
	})
	if err != nil {
		return FromStoreResult{}, err
	}
	if prepared.Hit {
		return FromStoreResult{Found: true, CachedPath: prepared.CachedPath, CachedModTime: prepared.CachedModTime}, nil
	}

	thumb, err := decodeStored(stored.Path, prepared.Width, prepared.Height)
	if err != nil {
		return FromStoreResult{}, err
	}
	// Hashed before rotation, like a generated thumbnail, and again whenever
	// the tier is rebuilt, so the hash follows a moved file to its new path.
	if !params.IsVideo {
		if err := upsertDHash(params.Queries, params.Serial, params.RelPath, thumb); err != nil {
			return FromStoreResult{}, err
		}
	}
	if prepared.RotationQuarters != 0 {
		thumb = photoutil.ApplyRotation(thumb, prepared.RotationQuarters)
	}
	modTime, err := writeCache(prepared.CachedPath, thumb, false)
	if err != nil {
		return FromStoreResult{}, err
	}
	return FromStoreResult{Found: true, CachedPath: prepared.CachedPath, CachedModTime: modTime}, nil
}

// StoreDerivative validates and stores a derivative a client rendered for a
// file. A photo's thumbnail is hashed for near-duplicate detection on the way
// in, so a photo the device cannot decode still takes part.
func StoreDerivative(params StoreDerivativeParams) (StoreDerivativeResult, error) {
	stored, err := derivativeutil.Store(derivativeutil.StoreParams{
		SourcePath: params.SourcePath,
		Kind:       params.Kind,
		Reader:     params.Reader,
	})
	if err != nil {
		return StoreDerivativeResult{}, err
	}
	if params.Kind == derivativeutil.KindThumbnail && !params.IsVideo {
		width, height := Dimensions(SizeLg)
		thumb, err := decodeStored(stored.Path, width, height)
		if err != nil {
			return StoreDerivativeResult{}, err
		}
		if err := upsertDHash(params.Queries, params.Serial, params.RelPath, thumb); err != nil {
			return StoreDerivativeResult{}, err
		}
	}
	return StoreDerivativeResult{Path: stored.Path}, nil
}

// StoreDerivatives attaches the derivatives in a multipart body to a file the
// caller may write, and announces the change so backup sync copies them and
// open clients reload the thumbnail. Each part is stored as it arrives; a bad
// part stops the upload with the ones before it kept.
func StoreDerivatives(params StoreDerivativesParams) (StoreDerivativesResult, error) {
	fileType := storageutil.DetermineFileTypeFromPath(params.RelPath)
	if fileType != storageutil.FileTypeImage && fileType != storageutil.FileTypeVideo {
		return StoreDerivativesResult{}, ErrNotMedia
	}
	resolved, err := params.Storage.ResolvePath(storageutil.ResolvePathParams{RelPath: params.RelPath, Serial: params.Serial})
	if err != nil {
		return StoreDerivativesResult{}, fmt.Errorf("%w: %w", ErrSourceNotFound, err)
	}
	if info, err := os.Stat(resolved.FullPath); err != nil || info.IsDir() {
		return StoreDerivativesResult{}, ErrSourceNotFound
	}

	var result StoreDerivativesResult
	for {
		part, err := params.Reader.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return result, fmt.Errorf("%w: %w", derivativeutil.ErrInvalid, err)
		}
		kind, ok := derivativeutil.ParseKind(part.FormName())
		if !ok {
			part.Close()
			continue
		}
		_, err = StoreDerivative(StoreDerivativeParams{
			Queries:    params.Queries,
			Serial:     params.Serial,
			RelPath:    params.RelPath,
			SourcePath: resolved.FullPath,
			Kind:       kind,
			Reader:     part,
			IsVideo:    fileType == storageutil.FileTypeVideo,
		})
		part.Close()
		if err != nil {
			return result, err
		}
		result.Stored = append(result.Stored, kind)
	}
	if len(result.Stored) == 0 {
		return result, ErrNoDerivatives
	}
	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind:         eventbus.EventDerivativesChanged,
			Path:         params.RelPath,
			DeviceSerial: params.Serial,
		})
	}
	return result, nil
}

// decodeStored decodes a stored thumbnail and crops it to a size tier.
func decodeStored(path string, width, height uint) (image.Image, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open stored thumbnail: %w", err)
	}
	defer f.Close()
	result, err := photoutil.GenerateThumbnailFromReader(f, ".jpg", width, height)
	if err != nil {
		return nil, fmt.Errorf("resize stored thumbnail: %w", err)
	}
	return result.Thumbnail, nil
}

// upsertDHash records the perceptual hash near-duplicate detection compares.
func upsertDHash(queries *db.Queries, serial, relPath string, img image.Image) error {
	if err := queries.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
		DeviceSerial: serial,
		RelPath:      relPath,
		Dhash:        sql.NullString{String: photoutil.DHashHex(img), Valid: true},
	}); err != nil {
		return fmt.Errorf("store perceptual hash: %w", err)
	}
	return nil
}

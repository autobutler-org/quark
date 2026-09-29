package photoutil

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"image"
	"io"
	"log"
	"math"
	"os"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// StorePhotoHashesParams names a photo and the hashes duplicate detection
// compares it by.
type StorePhotoHashesParams struct {
	Ctx     context.Context
	Queries *db.Queries
	// Serial and RelPath name the photo, spelled any way a request spells it.
	Serial  string
	RelPath string
	// DHash is the perceptual hash, from [GenerateThumbnailResult.DHash] or
	// [DHashFile]. Empty stores none.
	DHash string
	// Source is the photo file. It is rewound and streamed to the end for the
	// SHA-256. Nil stores no content hash.
	Source io.ReadSeeker
}

// StorePhotoHashesResult reports what was stored.
type StorePhotoHashesResult struct {
	// ContentHash is the hex SHA-256 of Source, empty without one.
	ContentHash string
}

// StorePhotoHashes records a photo's perceptual and content hashes, replacing
// any earlier ones. It is the one writer of photo_hashes: the thumbnail paths
// and [BackfillHashes] all come through here, so the row is keyed the way
// [ListDuplicates], its existence check, and the access checks spell the path.
// A trashed photo is never listed as a duplicate, so it is not stored.
func StorePhotoHashes(params StorePhotoHashesParams) (StorePhotoHashesResult, error) {
	relPath := accessutil.Canonical(params.RelPath)
	if storageutil.IsTrashPath(relPath) {
		return StorePhotoHashesResult{}, nil
	}
	content := ""
	if params.Source != nil {
		if _, err := params.Source.Seek(0, io.SeekStart); err != nil {
			return StorePhotoHashesResult{}, fmt.Errorf("rewind photo: %w", err)
		}
		h := sha256.New()
		if _, err := io.Copy(h, params.Source); err != nil {
			return StorePhotoHashesResult{}, fmt.Errorf("hash photo: %w", err)
		}
		content = hex.EncodeToString(h.Sum(nil))
	}
	if err := params.Queries.UpsertPhotoHash(params.Ctx, db.UpsertPhotoHashParams{
		DeviceSerial: params.Serial,
		RelPath:      relPath,
		Dhash:        sql.NullString{String: params.DHash, Valid: params.DHash != ""},
		ContentHash:  sql.NullString{String: content, Valid: content != ""},
	}); err != nil {
		return StorePhotoHashesResult{}, fmt.Errorf("store photo hashes: %w", err)
	}
	return StorePhotoHashesResult{ContentHash: content}, nil
}

// DHashFile decodes an image file, RAW included, turns it upright, and returns
// its perceptual hash: the same value [GenerateThumbnail] reports for it.
func DHashFile(filePath string) (string, error) {
	var img image.Image
	var err error
	if IsRawFile(filePath) {
		img, err = RawToJPEG(filePath)
	} else {
		img, _, err = decodeImageFile(filePath)
	}
	if err != nil {
		return "", err
	}
	return DHashHex(img), nil
}

// BackfillHashesParams points the backfill at the photo library.
type BackfillHashesParams struct {
	Ctx     context.Context
	Queries *db.Queries
	// FS and Storage enumerate the library the way [ListPhotos] does. Storage
	// also resolves each photo to the file that is read.
	FS      vfs.VFS
	Storage *storageutil.StorageService
	// IOSemaphore, when set, is held while each photo is read. Photos are
	// read one at a time, so the pass takes at most one slot from requests.
	IOSemaphore *iosemutil.Semaphore
}

// BackfillHashesResult counts what the backfill did.
type BackfillHashesResult struct {
	// Scanned is the photos in the library.
	Scanned int
	// Hashed is the photos that had no complete row and now have one.
	Hashed int
	// Failed is the photos that could not be read or stored.
	Failed int
}

// BackfillHashes hashes every library photo that has no photo_hashes row, or
// a row missing its dHash or content hash, and leaves every complete row
// alone. Photos only used to be hashed when their thumbnail was generated,
// and never by content, so a library whose thumbnails were already cached had
// nothing for [ListDuplicates] to group (#1666). It is idempotent: once
// everything is hashed a run costs one library listing and one query.
//
// A photo that cannot be decoded keeps the dHash it already had, which a
// client may have sent with its thumbnail, and gains a content hash.
// ponytail: a photo no decoder here can read has no dHash, so it is read
// again on every run; record the failure if a library of those shows up.
func BackfillHashes(params BackfillHashesParams) (BackfillHashesResult, error) {
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		return BackfillHashesResult{}, err
	}
	library, err := ListPhotos(ListPhotosParams{
		Ctx: params.Ctx, FS: params.FS, Storage: params.Storage,
		Access: system.Access, Limit: math.MaxInt,
	})
	if err != nil {
		return BackfillHashesResult{}, fmt.Errorf("list photos: %w", err)
	}
	// Every row that has a dHash; a row with no dHash is missing one anyway.
	rows, err := params.Queries.ListNearDuplicates(params.Ctx)
	if err != nil {
		return BackfillHashesResult{}, fmt.Errorf("list photo hashes: %w", err)
	}
	complete := map[DuplicatePhoto]bool{}
	knownDHash := map[DuplicatePhoto]string{}
	for _, row := range rows {
		key := DuplicatePhoto{DeviceSerial: row.DeviceSerial, RelPath: row.RelPath}
		complete[key] = row.ContentHash.Valid
		knownDHash[key] = row.Dhash.String
	}

	result := BackfillHashesResult{Scanned: len(library.Photos)}
	for _, photo := range library.Photos {
		key := DuplicatePhoto{DeviceSerial: photo.Serial, RelPath: accessutil.Canonical(photo.RelPath)}
		if complete[key] || storageutil.IsTrashPath(key.RelPath) {
			continue
		}
		if err := params.Ctx.Err(); err != nil {
			return result, err
		}
		if err := backfillPhoto(params, key, knownDHash[key]); err != nil {
			log.Printf("[photo-hashes] %q (serial=%q): %v", key.RelPath, key.DeviceSerial, err)
			result.Failed++
			continue
		}
		result.Hashed++
	}
	return result, nil
}

// backfillPhoto hashes one photo under the IO semaphore, keeping dhash when
// the file will not decode.
func backfillPhoto(params BackfillHashesParams, photo DuplicatePhoto, dhash string) error {
	if sem := params.IOSemaphore; sem != nil {
		// Wait as long as it takes: requests come first.
		for !sem.AcquireDefault(params.Ctx) {
			if err := params.Ctx.Err(); err != nil {
				return err
			}
		}
		defer sem.Release()
	}
	resolved, err := params.Storage.ResolvePath(storageutil.ResolvePathParams{
		RelPath: photo.RelPath, Serial: photo.DeviceSerial,
	})
	if err != nil {
		return err
	}
	f, err := os.Open(resolved.FullPath)
	if err != nil {
		return err
	}
	defer f.Close()
	if decoded, err := DHashFile(resolved.FullPath); err == nil {
		dhash = decoded
	}
	_, err = StorePhotoHashes(StorePhotoHashesParams{
		Ctx: params.Ctx, Queries: params.Queries,
		Serial: photo.DeviceSerial, RelPath: photo.RelPath,
		DHash: dhash, Source: f,
	})
	return err
}

// decodeImageFile decodes an image file and turns it upright by its EXIF
// orientation.
func decodeImageFile(filePath string) (image.Image, string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, "", fmt.Errorf("error opening image file %s: %w", filePath, err)
	}
	defer file.Close()

	img, format, err := image.Decode(file)
	if err != nil {
		return nil, "", fmt.Errorf("error decoding image file %s: %w", filePath, err)
	}
	return orientDecodedImage(img, file, ImageFormatFromPath(filePath)), format, nil
}

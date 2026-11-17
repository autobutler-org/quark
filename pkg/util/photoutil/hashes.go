package photoutil

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"image"
	"io"
	"os"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// StorePhotoHashesParams names a photo and the hashes duplicate detection
// compares it by.
type StorePhotoHashesParams struct {
	Ctx     context.Context
	Queries db.Querier
	// Serial and RelPath name the photo, spelled any way a request spells it.
	Serial  string
	RelPath string
	// DHash is the perceptual hash, from [GenerateThumbnailResult.DHash] or
	// [DHashFile]. Empty stores none.
	DHash string
	// Source is the photo file. It is rewound and streamed to the end for the
	// SHA-256, and its EXIF read for the capture date. Nil stores no content
	// hash and keeps whatever capture date was stored before.
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
//
// The photo's capture date rides along (#2592): the thumbnail paths already
// hold the file open, so a new photo is dated the first time it renders.
func StorePhotoHashes(params StorePhotoHashesParams) (StorePhotoHashesResult, error) {
	relPath := accessutil.Canonical(params.RelPath)
	if storageutil.IsTrashPath(relPath) {
		return StorePhotoHashesResult{}, nil
	}
	content := ""
	var facts exifFacts
	if params.Source != nil {
		var err error
		if facts, err = readExifFacts(params.Source, relPath); err != nil {
			return StorePhotoHashesResult{}, err
		}
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
		TakenAt:      facts.takenAt,
		Latitude:     facts.latitude,
		Longitude:    facts.longitude,
		TakenChecked: params.Source != nil,
	}); err != nil {
		return StorePhotoHashesResult{}, fmt.Errorf("store photo hashes: %w", err)
	}
	return StorePhotoHashesResult{ContentHash: content}, nil
}

// readExifFacts reads a photo's EXIF capture date and GPS position from
// source, spelled as relPath for its format. A photo with no date or no
// position, or EXIF that will not decode, has none: it sorts by its other
// date, stays off the map, and is not read again. Only a failure to rewind
// the file is an error.
func readExifFacts(source io.ReadSeeker, relPath string) (exifFacts, error) {
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return exifFacts{}, fmt.Errorf("rewind photo: %w", err)
	}
	exif, err := DecodeExif(source, ImageFormatFromPath(relPath))
	if err != nil || exif == nil {
		return exifFacts{}, nil
	}
	var facts exifFacts
	if exif.DateTaken != nil {
		facts.takenAt = sql.NullTime{Time: *exif.DateTaken, Valid: true}
	}
	if lat, lon, ok := ValidPosition(exif); ok {
		facts.latitude = sql.NullFloat64{Float64: lat, Valid: true}
		facts.longitude = sql.NullFloat64{Float64: lon, Valid: true}
	}
	return facts, nil
}

// DHashFile decodes an image file, RAW included, turns it upright, and returns
// its perceptual hash: the same value [GenerateThumbnail] reports for it.
func DHashFile(filePath string) (string, error) {
	var img image.Image
	orientation := 1
	var err error
	if IsRawFile(filePath) {
		img, err = RawToJPEG(filePath)
	} else {
		img, orientation, _, err = decodeImageFile(filePath)
	}
	if err != nil {
		return "", err
	}
	return uprightDHash(img, orientation), nil
}

// DHashSource returns the perceptual hash of relPath on fsys, the same value
// [GenerateThumbnail] reports for it. An image is decoded from source, which
// is relPath already open; a camera RAW goes to its converter by host path,
// the one thing the converter can take.
func DHashSource(ctx context.Context, fsys vfs.VFS, relPath string, source io.ReadSeeker) (string, error) {
	if IsRawFile(relPath) {
		hostPath, err := HostPath(ctx, fsys, relPath)
		if err != nil {
			return "", err
		}
		return DHashFile(hostPath)
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return "", fmt.Errorf("rewind photo: %w", err)
	}
	img, _, err := DecodeImage(source)
	if err != nil {
		return "", err
	}
	return uprightDHash(img, sourceOrientation(source, ImageFormatFromPath(relPath))), nil
}

// decodeImageFile decodes an image file and reads the EXIF orientation that
// turns it upright. The pixels are left as stored: turning a full-size image
// is left to whoever needs it, which thumbnails do after shrinking it.
func decodeImageFile(filePath string) (image.Image, int, string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, 0, "", fmt.Errorf("error opening image file %s: %w", filePath, err)
	}
	defer file.Close()

	img, format, err := DecodeImage(file)
	if err != nil {
		return nil, 0, "", fmt.Errorf("error decoding image file %s: %w", filePath, err)
	}
	return img, sourceOrientation(file, ImageFormatFromPath(filePath)), format, nil
}

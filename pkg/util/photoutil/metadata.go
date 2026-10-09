package photoutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"path"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ErrInvalidRelPath reports a relative path that escapes the files directory it
// is resolved against. Callers map it to a 400.
var ErrInvalidRelPath = errors.New("invalid relPath")

// ExifSummary holds the EXIF fields exposed for a photo, formatted for display.
// All fields are pointers so that absent values are omitted from the JSON
// output.
type ExifSummary struct {
	DateTaken    *string  `json:"dateTaken,omitempty"`
	Make         *string  `json:"make,omitempty"`
	Model        *string  `json:"model,omitempty"`
	Lens         *string  `json:"lens,omitempty"`
	Aperture     *float64 `json:"aperture,omitempty"`
	ShutterSpeed *string  `json:"shutterSpeed,omitempty"`
	ISO          *int     `json:"iso,omitempty"`
	FocalLength  *float64 `json:"focalLength,omitempty"`
	Latitude     *float64 `json:"latitude,omitempty"`
	Longitude    *float64 `json:"longitude,omitempty"`
}

// AlbumRef is a minimal album reference for embedding in photo metadata.
type AlbumRef struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

// MetadataParams identifies the photo to describe and how to reach it.
type MetadataParams struct {
	// Ctx bounds the VFS and database calls.
	Ctx context.Context
	// Queries reads rotation, favorite, and album membership.
	Queries *db.Queries
	// UserID is the account whose favorite and albums are reported.
	UserID int64
	// Registry holds one namespace per device; the photo is read through
	// Serial's.
	Registry vfs.Registry
	// Serial is the device serial the file belongs to, empty for local files.
	Serial string
	// RelPath is the photo's path relative to its files directory.
	RelPath string
}

// MetadataResult is the full description of a single photo.
type MetadataResult struct {
	FileSize           int64
	MTime              int64
	Width              int
	Height             int
	RotationQuarters   int64
	IsFavorite         bool
	Exif               *ExifSummary
	Albums             []AlbumRef
	LivePhotoVideoPath string
	// SoftErrors are lookups that failed without failing the request — the
	// fields they cover come back zero-valued. Callers log them.
	SoftErrors []error
}

// Metadata gathers everything the photo detail view needs: file stat, EXIF,
// the server-side rotation, the account's favorite state and albums, and the
// Live Photo video companion.
//
// A missing file comes back as [storageutil.ErrPathNotFound] and a relPath that
// escapes its files directory as [ErrInvalidRelPath], so callers can map both to
// the right status code.
func Metadata(params MetadataParams) (MetadataResult, error) {
	fsys, err := DeviceFS(params.Registry, params.Serial)
	if err != nil {
		return MetadataResult{}, fmt.Errorf("%w: %s", storageutil.ErrPathNotFound, params.RelPath)
	}
	stat, err := statPhoto(params, fsys)
	if err != nil {
		return MetadataResult{}, err
	}

	var rotationQuarters int64
	if rq, rotErr := params.Queries.GetPhotoRotation(
		params.Ctx,
		db.GetPhotoRotationParams{DeviceSerial: params.Serial, RelPath: params.RelPath},
	); rotErr == nil {
		rotationQuarters = rq
	} else if !errors.Is(rotErr, sql.ErrNoRows) {
		return MetadataResult{}, fmt.Errorf("get photo rotation: %w", rotErr)
	}

	var softErrors []error

	isFavorite, favErr := params.Queries.IsFavorite(
		params.Ctx,
		db.IsFavoriteParams{UserID: params.UserID, DeviceSerial: params.Serial, RelPath: params.RelPath},
	)
	if favErr != nil && !errors.Is(favErr, sql.ErrNoRows) {
		softErrors = append(softErrors, fmt.Errorf("check favorite for %q: %w", params.RelPath, favErr))
	}

	albums, albumsErr := params.Queries.ListAlbumsContainingPhoto(
		params.Ctx,
		db.ListAlbumsContainingPhotoParams{
			UserID:       params.UserID,
			DeviceSerial: params.Serial,
			RelPath:      params.RelPath,
		},
	)
	if albumsErr != nil {
		softErrors = append(softErrors, fmt.Errorf(
			"list albums containing photo %q for device %q: %w", params.RelPath, params.Serial, albumsErr,
		))
		albums = nil
	}
	albumRefs := make([]AlbumRef, 0, len(albums))
	for _, a := range albums {
		albumRefs = append(albumRefs, AlbumRef{ID: a.ID, Name: a.Name})
	}

	liveVideoPath := FindLivePhotoVideo(params.Ctx, fsys, params.RelPath)

	return MetadataResult{
		FileSize:           stat.size,
		MTime:              stat.mtime,
		Width:              stat.width,
		Height:             stat.height,
		RotationQuarters:   rotationQuarters,
		IsFavorite:         isFavorite,
		Exif:               stat.exif,
		Albums:             albumRefs,
		LivePhotoVideoPath: liveVideoPath,
		SoftErrors:         softErrors,
	}, nil
}

// SaveRotationParams is the viewer rotation to persist for one photo.
type SaveRotationParams struct {
	// Ctx bounds the database write.
	Ctx context.Context
	// Queries writes the rotation record.
	Queries *db.Queries
	// Serial is the device serial the file belongs to, empty for local files.
	Serial string
	// RelPath is the photo's path relative to its files directory.
	RelPath string
	// RotationQuarters is the rotation in 90° clockwise steps. Values outside
	// 0–3 are normalized; a normalized 0 removes the record.
	RotationQuarters int64
}

// SaveRotation persists the viewer rotation for a photo. No rotation is stored
// as no record, so the table only ever holds photos the user actually turned.
func SaveRotation(params SaveRotationParams) error {
	quarters := ((params.RotationQuarters % 4) + 4) % 4
	if quarters == 0 {
		// No rotation — remove the record to keep the table clean.
		return params.Queries.DeletePhotoRotation(params.Ctx, db.DeletePhotoRotationParams{
			DeviceSerial: params.Serial,
			RelPath:      params.RelPath,
		})
	}
	return params.Queries.UpsertPhotoRotation(params.Ctx, db.UpsertPhotoRotationParams{
		DeviceSerial:     params.Serial,
		RelPath:          params.RelPath,
		RotationQuarters: quarters,
	})
}

// photoStat is the part of the metadata that comes from the file itself.
type photoStat struct {
	size   int64
	mtime  int64
	width  int
	height int
	exif   *ExifSummary
}

// statPhoto stats the photo on fsys and decodes its EXIF. EXIF is best
// effort: a file that does not decode still reports its size and modification
// time.
func statPhoto(params MetadataParams, fsys vfs.VFS) (photoStat, error) {
	if accessutil.Canonical(params.RelPath) == "" {
		return photoStat{}, ErrInvalidRelPath
	}
	fi, err := fsys.Stat(params.Ctx, params.RelPath)
	switch {
	case errors.Is(err, vfs.ErrNotFound):
		return photoStat{}, fmt.Errorf("%w: %s", storageutil.ErrPathNotFound, params.RelPath)
	case errors.Is(err, vfs.ErrPermissionDenied):
		// A path that climbs out of the namespace.
		return photoStat{}, ErrInvalidRelPath
	case err != nil:
		return photoStat{}, err
	}
	stat := photoStat{size: fi.Size, mtime: fi.ModTime.Unix()}

	imgFormat := ImageFormatFromPath(params.RelPath)
	if imgFormat == 0 {
		return stat, nil
	}
	f, err := fsys.Open(params.Ctx, params.RelPath)
	if err != nil {
		return stat, nil
	}
	defer f.Close()
	if data, exifErr := DecodeExif(f, imgFormat); exifErr == nil && data != nil {
		stat.exif = SummarizeExif(data)
		stat.width = data.Width
		stat.height = data.Height
	}
	return stat, nil
}

// FindLivePhotoVideo finds the companion .mov (or .mp4) of an image on fsys,
// which marks an iPhone Live Photo, with one single-level listing of the
// image's folder. It returns the video's path, in relPath's folder, or "" if
// there is none.
//
// The sibling is found by listing the folder rather than by stat-ing
// candidate spellings. A stat loop reports the spelling it guessed, not the
// one stored: on a case-insensitive filesystem (macOS, Windows) stat of
// "photo.MOV" succeeds for a file actually named "photo.mov", so the client
// was handed a path that does not exist as spelled — and would 404 against a
// case-sensitive filesystem holding the same library.
func FindLivePhotoVideo(ctx context.Context, fsys vfs.VFS, relPath string) string {
	if !canHaveLiveVideo(relPath) {
		return ""
	}
	dir := path.Dir(accessutil.Canonical(relPath))
	if dir == "." {
		dir = ""
	}
	entries, err := fsys.List(ctx, dir, nil)
	if err != nil {
		return ""
	}
	name := liveVideoName(entries, path.Base(relPath))
	if name == "" {
		return ""
	}
	// Keep relPath's directory and swap in the real filename, so the
	// returned path is spelled exactly as it is stored.
	if d := path.Dir(relPath); d != "." && d != "/" {
		return path.Join(d, name)
	}
	return name
}

// canHaveLiveVideo reports whether an image is a kind an iPhone pairs with a
// Live Photo video: HEIC or JPEG.
func canHaveLiveVideo(name string) bool {
	switch strings.ToLower(path.Ext(name)) {
	case ".heic", ".heif", ".jpg", ".jpeg":
		return true
	}
	return false
}

// liveVideoName picks, from a folder's entries, the video sharing imageName's
// stem, ignoring case. A .mov comes before a .mp4: a Live Photo's companion
// is a .mov, and preferring it keeps the pick stable for a folder holding
// both. Within an extension the first name in byte order wins, whatever
// order the listing came in.
func liveVideoName(entries []vfs.FileInfo, imageName string) string {
	stem := strings.TrimSuffix(imageName, path.Ext(imageName))
	for _, want := range []string{".mov", ".mp4"} {
		pick := ""
		for _, e := range entries {
			ext := path.Ext(e.Name)
			if e.IsDir || !strings.EqualFold(ext, want) || !strings.EqualFold(strings.TrimSuffix(e.Name, ext), stem) {
				continue
			}
			if pick == "" || e.Name < pick {
				pick = e.Name
			}
		}
		if pick != "" {
			return pick
		}
	}
	return ""
}

// SummarizeExif formats decoded EXIF for display, rounding the numeric fields
// and rendering the shutter speed as a fraction. It returns nil when the photo
// carried none of the fields.
func SummarizeExif(data *ExifData) *ExifSummary {
	e := &ExifSummary{}
	empty := true

	if data.DateTaken != nil {
		s := data.DateTaken.Format(time.RFC3339)
		e.DateTaken = &s
		empty = false
	}
	if data.Make != "" {
		e.Make = &data.Make
		empty = false
	}
	if data.Model != "" {
		e.Model = &data.Model
		empty = false
	}
	if data.LensModel != "" {
		e.Lens = &data.LensModel
		empty = false
	}
	if data.Aperture != 0 {
		v := RoundTo(data.Aperture, 2)
		e.Aperture = &v
		empty = false
	}
	if data.ShutterSpeed[1] != 0 {
		n, d := data.ShutterSpeed[0], data.ShutterSpeed[1]
		var s string
		if n == 0 {
			s = "0"
		} else if d%n == 0 {
			s = fmt.Sprintf("1/%d", d/n)
		} else {
			s = fmt.Sprintf("%d/%d", n, d)
		}
		e.ShutterSpeed = &s
		empty = false
	}
	if data.ISO != 0 {
		e.ISO = &data.ISO
		empty = false
	}
	if data.FocalLength != 0 {
		v := RoundTo(data.FocalLength, 2)
		e.FocalLength = &v
		empty = false
	}
	if data.HasGPS {
		lat := RoundTo(data.Latitude, 6)
		lon := RoundTo(data.Longitude, 6)
		e.Latitude = &lat
		e.Longitude = &lon
		empty = false
	}

	if empty {
		return nil
	}
	return e
}

// RoundTo rounds v to the given number of decimal places.
func RoundTo(v float64, decimals int) float64 {
	factor := math.Pow(10, float64(decimals))
	return math.Round(v*factor) / factor
}

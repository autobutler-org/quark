// Package thumbnailutil generates and caches image and video thumbnails on
// disk. It owns everything between "which file, which size" and "here are the
// cached bytes": the size tiers, the cache key and directory, thumbnail
// rendering (including the ffmpeg frame grab for video), and the perceptual
// hash that photo deduplication reads back out of the database.
//
// A thumbnail a client rendered and uploaded (#2379) is kept in the same
// cache and comes first: the size tiers are resized from it, and generating
// from the file is the fallback. A file the device cannot decode itself
// (H.264/HEVC video, HEIC) is answered with [NeedsClientRender] so a client
// can render one and upload it.
//
// HTTP concerns — ETag negotiation, status codes, the IO semaphore — stay with
// the caller; [ETagFromModTime] and [ContentTypeForExt] are here only because
// they are derived from the cache entry the service produced.
package thumbnailutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// Size represents the supported thumbnail size tiers.
type Size string

const (
	SizeSm Size = "sm" // 96×96  – grid icons / file browser
	SizeMd Size = "md" // 240×240 – card previews
	SizeLg Size = "lg" // 400×400 – detail view (legacy default)
)

// ErrFFmpegUnavailable reports a video thumbnail request on a host without
// ffmpeg. Callers map it to 404, the same as a missing file.
var ErrFFmpegUnavailable = errors.New("video thumbnails require ffmpeg (not installed)")

// ErrInvalidThumbnail reports an uploaded thumbnail that is not a JPEG, is
// larger than [MaxClientThumbnailBytes], or is bigger on a side than a
// thumbnail needs to be.
var ErrInvalidThumbnail = errors.New("invalid thumbnail")

// ErrNotMedia reports a thumbnail sent for a file that is neither a photo nor
// a video.
var ErrNotMedia = errors.New("only photos and videos have thumbnails")

// ErrNoThumbnail reports a thumbnail upload with no "thumbnail" part in it.
var ErrNoThumbnail = errors.New(`send the thumbnail as a "thumbnail" part`)

// ErrSourceNotFound reports a thumbnail sent for a file that is not there.
var ErrSourceNotFound = errors.New("file not found")

// MaxClientThumbnailBytes is the largest thumbnail a client may upload. One
// with a 400px long edge is a few tens of KB.
const MaxClientThumbnailBytes int64 = 2 << 20

// ErrUnsupportedSource reports a source the thumbnail pipeline cannot decode —
// an unknown format, a truncated file. Callers with a second source to try
// (the VFS path falling back to the storage service) use it to fall through.
var ErrUnsupportedSource = errors.New("unsupported thumbnail source")

// MaxBufferedSourceBytes caps a source that cannot seek, such as an archive
// entry. Decoding reads EXIF back out of the stream, so [GenerateFromReader]
// holds such a source in memory whole.
// ponytail: a larger entry gets no thumbnail; spool it to a temp file if big
// scans inside archives need one.
const MaxBufferedSourceBytes int64 = 64 << 20

// PrepareParams describes a thumbnail request far enough to locate its cache
// entry: which file, at which size, and how stale the entry may be.
type PrepareParams struct {
	// Queries reads the user's server-side rotation for the photo.
	Queries *db.Queries
	// Serial is the device serial the file belongs to, empty for local files.
	Serial string
	// RelPath is the path used for database lookups (no leading slash).
	RelPath string
	// FilePath is the raw request path, used for the cache key.
	FilePath string
	// Size is the requested size tier.
	Size Size
	// SrcModTime is the source file's modification time; a cache entry older
	// than it is stale.
	SrcModTime time.Time
}

// PrepareResult is everything needed to either serve the cache entry or
// regenerate it.
type PrepareResult struct {
	CachedPath       string
	CachedModTime    time.Time
	Hit              bool
	RotationQuarters int64
	Width            uint
	Height           uint
}

// GenerateParams renders a thumbnail from a file on disk. Video sources get a
// representative frame extracted with ffmpeg first.
type GenerateParams struct {
	// Ctx bounds the ffmpeg probe and frame extraction.
	Ctx context.Context
	// Queries stores the perceptual hash.
	Queries *db.Queries
	// Serial and RelPath identify the photo the perceptual hash belongs to.
	Serial  string
	RelPath string
	// SourcePath is the file to render.
	SourcePath string
	// Ext is the lowercase source extension, which picks the cache encoding.
	Ext string
	// IsVideo selects the ffmpeg frame grab.
	IsVideo bool
	// Width and Height are the target dimensions.
	Width  uint
	Height uint
	// RotationQuarters applies the user's server-side rotation.
	RotationQuarters int64
	// CachedPath is where the encoded thumbnail is committed.
	CachedPath string
}

// GenerateFromReaderParams renders a thumbnail from an already-open stream —
// the VFS path, which has no OS path to hand to an external tool. Video and
// RAW sources are not supported here.
type GenerateFromReaderParams struct {
	// Reader streams the source image.
	Reader io.Reader
	// Ext is the lowercase source extension, used for format detection.
	Ext string
	// Width and Height are the target dimensions.
	Width  uint
	Height uint
	// RotationQuarters applies the user's server-side rotation.
	RotationQuarters int64
	// CachedPath is where the encoded thumbnail is committed.
	CachedPath string
}

// GenerateResult reports the committed cache entry.
type GenerateResult struct {
	CachedModTime time.Time
}

// StoreClientThumbnailParams is a thumbnail a client rendered for a file: a
// JPEG, long edge 400, rotation applied.
type StoreClientThumbnailParams struct {
	// Queries stores the perceptual hash of a photo's thumbnail. Nil skips it.
	Queries *db.Queries
	// Serial and RelPath name the file, as a request spells them.
	Serial  string
	RelPath string
	// Reader is the JPEG, read to EOF or one byte past the size limit.
	Reader io.Reader
	// IsVideo skips the perceptual hash, which only photos are compared by.
	IsVideo bool
}

// StoreClientThumbnailResult reports the stored thumbnail.
type StoreClientThumbnailResult struct {
	CachedPath string
}

// FromClientThumbnailParams asks for a size tier of a file, resized from the
// thumbnail a client uploaded for it.
type FromClientThumbnailParams struct {
	// Queries reads the user's rotation for the photo.
	Queries *db.Queries
	// Serial and RelPath identify the file.
	Serial  string
	RelPath string
	// FilePath is the raw request path, used for the tier's cache key.
	FilePath string
	// SourceModTime is the file's modification time. A thumbnail older than
	// the file is stale and ignored.
	SourceModTime time.Time
	Size          Size
}

// FromClientThumbnailResult is the tier to serve. Found is false when the
// file has no fresh client thumbnail.
type FromClientThumbnailResult struct {
	Found         bool
	CachedPath    string
	CachedModTime time.Time
}

// StoreClientThumbnailsParams attaches the "thumbnail" part of a multipart
// body to an existing file. Other parts are skipped.
type StoreClientThumbnailsParams struct {
	Queries *db.Queries
	Storage *storageutil.StorageService
	// Serial and RelPath name the file, as the request did.
	Serial  string
	RelPath string
	Reader  *multipart.Reader
}

// StoreClientThumbnailsResult reports the stored thumbnail.
type StoreClientThumbnailsResult struct{}

// ParseSize parses the ?size= query parameter, defaulting to lg.
func ParseSize(raw string) Size {
	switch Size(raw) {
	case SizeSm:
		return SizeSm
	case SizeMd:
		return SizeMd
	default:
		return SizeLg
	}
}

// Dimensions returns the pixel dimensions for a given size tier.
func Dimensions(size Size) (width, height uint) {
	switch size {
	case SizeSm:
		return 96, 96
	case SizeMd:
		return 240, 240
	default: // SizeLg and any unknown value
		return 400, 400
	}
}

// ETagFromModTime returns a quoted ETag string derived from a file's
// modification time.
func ETagFromModTime(t time.Time) string {
	return fmt.Sprintf(`"%x"`, t.UnixNano())
}

// ContentTypeForExt returns the MIME type for a thumbnail based on its source
// file extension.
func ContentTypeForExt(ext string) string {
	switch ext {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	default:
		return "image/jpeg"
	}
}

// cspell:words thumbversionutil

// Package thumbversionutil decides when a thumbnail or profile picture may be
// cached as immutable (#4217). A client puts the picture's version in the
// URL's v parameter, built from data it already holds: a photo's mtime and
// saved rotation, a profile picture's avatarUpdatedAt. When v names the
// version the Quark would serve now, the URL can never show anything else, so
// the response is cacheable for a year without revalidation. A missing or
// stale v keeps the revalidate-every-time behavior older clients rely on.
package thumbversionutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// Immutable is the Cache-Control for a URL whose v matches the current
// version. private keeps a shared cache from ever storing a user's picture.
const Immutable = "private, max-age=31536000, immutable"

// Revalidate is the Cache-Control for every other request: the client may
// store the response but must revalidate it by ETag before each use.
const Revalidate = "no-cache"

// Version is a photo or video thumbnail's version as clients write it in v:
// the source file's mtime in Unix seconds and its saved rotation in quarter
// turns, as in "1700000000.1". The photo listing carries both.
func Version(srcModTime time.Time, rotationQuarters int64) string {
	return fmt.Sprintf("%d.%d", srcModTime.Unix(), rotationQuarters)
}

// AvatarVersion is a profile picture's version as clients write it in v: its
// avatarUpdatedAt, the stored file's mtime in Unix milliseconds.
func AvatarVersion(updatedAt time.Time) string {
	return strconv.FormatInt(updatedAt.UnixMilli(), 10)
}

// CacheControl is the Cache-Control for a response to a request whose v was
// requested, when the picture's version is now current. An empty current
// means the response has no version a client could name.
func CacheControl(requested, current string) string {
	if requested != "" && requested == current {
		return Immutable
	}
	return Revalidate
}

// Rotation reads the saved rotation of the photo at params.RelPath on the
// device params.Serial, in quarter turns; a photo never rotated is 0.
func Rotation(params RotationParams) (RotationResult, error) {
	quarters, err := params.Queries.GetPhotoRotation(params.Ctx, db.GetPhotoRotationParams{
		DeviceSerial: params.Serial,
		RelPath:      params.RelPath,
	})
	if errors.Is(err, sql.ErrNoRows) {
		return RotationResult{}, nil
	}
	if err != nil {
		return RotationResult{}, fmt.Errorf("get photo rotation: %w", err)
	}
	return RotationResult{Quarters: quarters}, nil
}

// RotationParams names the photo [Rotation] reads.
type RotationParams struct {
	Ctx     context.Context
	Queries db.Querier
	Serial  string
	RelPath string
}

// RotationResult is the photo's saved rotation.
type RotationResult struct {
	// Quarters is the clockwise rotation in quarter turns, 0 to 3.
	Quarters int64
}

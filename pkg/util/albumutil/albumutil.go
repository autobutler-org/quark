// Package albumutil holds the photo album writes that carry naming rules: an
// album name cannot contain '/', and it is unique among its siblings ignoring
// case. Root albums are siblings of each other, and of the system Favorites
// album. Albums belong to one account (#1912): the siblings are that account's
// own, and another account's album reads as missing.
//
// The database enforces uniqueness with idx_photo_albums_sibling_name, so a
// concurrent request that slips past any check still fails here as
// ErrNameConflict. HTTP concerns stay with the caller, which maps the sentinel
// errors below (and sql.ErrNoRows for a missing album) onto status codes.
package albumutil

import (
	"context"
	"database/sql"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// Sentinel errors the caller maps onto a status code. Their text is the copy a
// client shows, so it must not be rewrapped in a way that changes it.
var (
	// ErrNameConflict reports that the album's parent already holds an album
	// with the same name ignoring case.
	ErrNameConflict = errors.New("an album with that name already exists here")
	// ErrNameHasSlash reports a name containing '/', the album path separator.
	ErrNameHasSlash = errors.New("album names cannot contain /")
)

// CreateAlbumParams creates a user album.
type CreateAlbumParams struct {
	Queries *db.Queries
	// UserID owns the album.
	UserID int64
	Name   string
	// ParentID is invalid for a root album.
	ParentID sql.NullInt64
}

// CreateAlbumResult carries the created album.
type CreateAlbumResult struct {
	Album db.PhotoAlbum
}

// RenameAlbumParams renames an existing album in place.
type RenameAlbumParams struct {
	Queries *db.Queries
	// UserID owns the album. Another account's album is missing.
	UserID int64
	ID     int64
	Name   string
}

// RenameAlbumResult carries the renamed album.
type RenameAlbumResult struct {
	Album db.PhotoAlbum
}

// MoveAlbumParams moves an existing album under a new parent.
type MoveAlbumParams struct {
	Queries *db.Queries
	// UserID owns the album. Another account's album is missing.
	UserID int64
	ID     int64
	// ParentID is invalid to move the album to the root.
	ParentID sql.NullInt64
}

// MoveAlbumResult carries the moved album.
type MoveAlbumResult struct {
	Album db.PhotoAlbum
}

// CountItemsParams counts the items of one album that a caller can see.
type CountItemsParams struct {
	Queries *db.Queries
	// Access leaves out the items the caller cannot read (#1904).
	Access  accessutil.Access
	AlbumID int64
}

// CountItemsResult carries the count.
type CountItemsResult struct {
	Count int64
}

// CountItems counts an album's items the caller can read, so an album they can
// see does not reveal how many photos it holds that they cannot. An admin's
// count is one COUNT query, as before.
func CountItems(ctx context.Context, params CountItemsParams) (CountItemsResult, error) {
	if params.Access.Principal().IsAdmin {
		count, err := params.Queries.CountAlbumItems(ctx, params.AlbumID)
		return CountItemsResult{Count: count}, err
	}
	items, err := params.Queries.ListAlbumItems(ctx, params.AlbumID)
	if err != nil {
		return CountItemsResult{}, err
	}
	var count int64
	for _, item := range items {
		if params.Access.Check(item.DeviceSerial, item.RelPath, accessutil.Read).Readable {
			count++
		}
	}
	return CountItemsResult{Count: count}, nil
}

// CreateAlbum creates an album, refusing a name with '/' or one a sibling
// already holds.
func CreateAlbum(ctx context.Context, params CreateAlbumParams) (CreateAlbumResult, error) {
	if err := checkName(params.Name, params.ParentID); err != nil {
		return CreateAlbumResult{}, err
	}
	album, err := params.Queries.CreateAlbum(ctx, db.CreateAlbumParams{
		Name:     params.Name,
		ParentID: params.ParentID,
		UserID:   params.UserID,
	})
	if err != nil {
		return CreateAlbumResult{}, nameConflictOr(err)
	}
	return CreateAlbumResult{Album: album}, nil
}

// RenameAlbum renames an album, refusing a name with '/' or one a sibling
// already holds. Changing only the case of the album's own name is allowed.
// A missing album, or another account's, returns an error wrapping
// sql.ErrNoRows.
func RenameAlbum(ctx context.Context, params RenameAlbumParams) (RenameAlbumResult, error) {
	if err := checkSlash(params.Name); err != nil {
		return RenameAlbumResult{}, err
	}
	current, err := params.Queries.GetAlbum(ctx, db.GetAlbumParams{ID: params.ID, UserID: params.UserID})
	if err != nil {
		return RenameAlbumResult{}, err
	}
	if err := checkName(params.Name, current.ParentID); err != nil {
		return RenameAlbumResult{}, err
	}
	album, err := params.Queries.RenameAlbum(ctx, db.RenameAlbumParams{
		Name:   params.Name,
		ID:     params.ID,
		UserID: params.UserID,
	})
	if err != nil {
		return RenameAlbumResult{}, nameConflictOr(err)
	}
	return RenameAlbumResult{Album: album}, nil
}

// MoveAlbum moves an album, refusing a parent that already holds an album with
// its name. A missing album, or another account's, returns an error wrapping
// sql.ErrNoRows.
func MoveAlbum(ctx context.Context, params MoveAlbumParams) (MoveAlbumResult, error) {
	current, err := params.Queries.GetAlbum(ctx, db.GetAlbumParams{ID: params.ID, UserID: params.UserID})
	if err != nil {
		return MoveAlbumResult{}, err
	}
	if err := checkName(current.Name, params.ParentID); err != nil {
		return MoveAlbumResult{}, err
	}
	album, err := params.Queries.MoveAlbum(ctx, db.MoveAlbumParams{
		ParentID: params.ParentID,
		ID:       params.ID,
		UserID:   params.UserID,
	})
	if err != nil {
		return MoveAlbumResult{}, nameConflictOr(err)
	}
	return MoveAlbumResult{Album: album}, nil
}

// Package albumutil holds the photo album writes that carry naming rules: an
// album name cannot contain '/', and it is unique among its siblings ignoring
// case. Root albums are siblings of each other, and of the system Favorites
// album.
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
	Name    string
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
	ID      int64
	Name    string
}

// RenameAlbumResult carries the renamed album.
type RenameAlbumResult struct {
	Album db.PhotoAlbum
}

// MoveAlbumParams moves an existing album under a new parent.
type MoveAlbumParams struct {
	Queries *db.Queries
	ID      int64
	// ParentID is invalid to move the album to the root.
	ParentID sql.NullInt64
}

// MoveAlbumResult carries the moved album.
type MoveAlbumResult struct {
	Album db.PhotoAlbum
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
	})
	if err != nil {
		return CreateAlbumResult{}, nameConflictOr(err)
	}
	return CreateAlbumResult{Album: album}, nil
}

// RenameAlbum renames an album, refusing a name with '/' or one a sibling
// already holds. Changing only the case of the album's own name is allowed.
// A missing album returns an error wrapping sql.ErrNoRows.
func RenameAlbum(ctx context.Context, params RenameAlbumParams) (RenameAlbumResult, error) {
	if err := checkSlash(params.Name); err != nil {
		return RenameAlbumResult{}, err
	}
	current, err := params.Queries.GetAlbum(ctx, params.ID)
	if err != nil {
		return RenameAlbumResult{}, err
	}
	if err := checkName(params.Name, current.ParentID); err != nil {
		return RenameAlbumResult{}, err
	}
	album, err := params.Queries.RenameAlbum(ctx, db.RenameAlbumParams{
		Name: params.Name,
		ID:   params.ID,
	})
	if err != nil {
		return RenameAlbumResult{}, nameConflictOr(err)
	}
	return RenameAlbumResult{Album: album}, nil
}

// MoveAlbum moves an album, refusing a parent that already holds an album with
// its name. A missing album returns an error wrapping sql.ErrNoRows.
func MoveAlbum(ctx context.Context, params MoveAlbumParams) (MoveAlbumResult, error) {
	current, err := params.Queries.GetAlbum(ctx, params.ID)
	if err != nil {
		return MoveAlbumResult{}, err
	}
	if err := checkName(current.Name, params.ParentID); err != nil {
		return MoveAlbumResult{}, err
	}
	album, err := params.Queries.MoveAlbum(ctx, db.MoveAlbumParams{
		ParentID: params.ParentID,
		ID:       params.ID,
	})
	if err != nil {
		return MoveAlbumResult{}, nameConflictOr(err)
	}
	return MoveAlbumResult{Album: album}, nil
}

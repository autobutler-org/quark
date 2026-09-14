package v0_albums

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// albumWriteError maps an albumutil create, rename or move error onto its
// status: 400 for a '/' in the name, 409 for a sibling holding the name, 404
// for a missing album, and 500 for anything else.
func albumWriteError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, albumutil.ErrNameHasSlash):
		return serverutil.BadRequest(err)
	case errors.Is(err, albumutil.ErrNameConflict):
		return serverutil.Conflict(err)
	case errors.Is(err, sql.ErrNoRows):
		return serverutil.NotFound(err)
	default:
		return serverutil.InternalServerError(err)
	}
}

// toAlbumJSON converts an album row plus its item count for a response.
func toAlbumJSON(album db.PhotoAlbum, itemCount int64) AlbumJSON {
	var parentID *int64
	if album.ParentID.Valid {
		parentID = &album.ParentID.Int64
	}
	return AlbumJSON{
		ID:        album.ID,
		Name:      album.Name,
		ParentID:  parentID,
		SmartType: sqlutil.NullStringPtr(album.SmartType),
		CreatedAt: sqlutil.FormatTime(album.CreatedAt),
		UpdatedAt: sqlutil.FormatTime(album.UpdatedAt),
		ItemCount: itemCount,
	}
}

// errSystemAlbum is why a system album (Favorites) refuses a user edit. Its
// contents follow photo_favorites, which only favoritesutil writes.
var errSystemAlbum = errors.New("system albums cannot be changed")

// forbidSystemAlbum answers 403 for a system album and nil for a user one.
func forbidSystemAlbum(album db.PhotoAlbum) *serverutil.Response {
	if !album.SmartType.Valid {
		return nil
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(errSystemAlbum)
}

// rejectSystemAlbum loads the album and applies forbidSystemAlbum. A missing
// album passes, so each handler keeps the not-found answer it already gave.
func rejectSystemAlbum(ctx context.Context, q *db.Queries, id int64) *serverutil.Response {
	album, err := q.GetAlbum(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return forbidSystemAlbum(album)
}

// buildTree converts a flat album list into a nested tree.
// Uses a child-index map to avoid value-copy aliasing issues when building
// multi-level hierarchies.
func buildTree(albums []AlbumJSON) []AlbumJSON {
	// Map album ID → its children IDs.
	childIDs := make(map[int64][]int64, len(albums))
	byID := make(map[int64]AlbumJSON, len(albums))
	for _, a := range albums {
		byID[a.ID] = a
	}
	for _, a := range albums {
		if a.ParentID != nil {
			childIDs[*a.ParentID] = append(childIDs[*a.ParentID], a.ID)
		}
	}

	// build recursively populates Children before returning a copy.
	var build func(id int64) AlbumJSON
	build = func(id int64) AlbumJSON {
		a := byID[id]
		for _, cid := range childIDs[id] {
			a.Children = append(a.Children, build(cid))
		}
		return a
	}

	roots := []AlbumJSON{}
	for _, a := range albums {
		if a.ParentID == nil {
			roots = append(roots, build(a.ID))
		}
	}
	return roots
}

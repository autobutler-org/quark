package favoritesutil

import (
	"context"
	"database/sql"
	"errors"
	"log"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// FavoritesAlbumName is the name CreateFavoritesAlbum gives the system album,
// at the root. Album names are unique among siblings ignoring case, so no user
// album at the root may take it.
const FavoritesAlbumName = "Favorites"

// ErrFavoritesNameTaken reports that a user album at the root holds the
// Favorites name, so the system album cannot be created. The 008 migration and
// albumutil both refuse that state; seeing this error means something wrote
// photo_albums around them.
var ErrFavoritesNameTaken = errors.New("a user album named Favorites blocks the system Favorites album")

// EnsureFavoritesAlbum returns the account's system Favorites album, creating
// it if it doesn't exist. Every account has its own. Safe to call concurrently
// — if two goroutines race to create the album, the loser re-fetches the
// winner's row.
func EnsureFavoritesAlbum(ctx context.Context, q *db.Queries, userID int64) (db.PhotoAlbum, error) {
	album, err := q.GetFavoritesAlbum(ctx, userID)
	if err == nil {
		return album, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return db.PhotoAlbum{}, err
	}
	// Attempt to create — handle the race where another request creates it
	// concurrently and hits the unique constraint on smart_type.
	album, err = q.CreateFavoritesAlbum(ctx, userID)
	if err == nil {
		return album, nil
	}
	if !sqlutil.IsUniqueConstraintErr(err) {
		return db.PhotoAlbum{}, err
	}
	// Either another request won the race, or a user album at the root holds
	// the name (the sibling-name index). Only the first leaves a row to fetch.
	album, err = q.GetFavoritesAlbum(ctx, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return db.PhotoAlbum{}, ErrFavoritesNameTaken
	}
	return album, err
}

// ToggleFavorite adds or removes a photo from the account's favorites and syncs
// its Favorites smart album. Returns true if the photo is now favorited.
func ToggleFavorite(ctx context.Context, q *db.Queries, userID int64, deviceSerial, relPath string) (bool, error) {
	isFav, err := q.IsFavorite(ctx, db.IsFavoriteParams{
		UserID:       userID,
		DeviceSerial: deviceSerial,
		RelPath:      relPath,
	})
	if err != nil {
		return false, err
	}

	if isFav {
		if err := q.RemoveFavorite(ctx, db.RemoveFavoriteParams{
			UserID:       userID,
			DeviceSerial: deviceSerial,
			RelPath:      relPath,
		}); err != nil {
			return false, err
		}
		// Best-effort: remove from the Favorites smart album. A failure here
		// leaves a stale album row but does not affect the authoritative
		// photo_favorites table, so we log and continue rather than rolling back.
		album, err := EnsureFavoritesAlbum(ctx, q, userID)
		if err == nil {
			if removeErr := q.RemovePhotoFromAlbum(ctx, db.RemovePhotoFromAlbumParams{
				AlbumID:      album.ID,
				DeviceSerial: deviceSerial,
				RelPath:      relPath,
			}); removeErr != nil && !errors.Is(removeErr, sql.ErrNoRows) {
				log.Printf("[favorites] best-effort album remove failed for %q: %v", relPath, removeErr)
			}
		}
		return false, nil
	}

	if err := q.AddFavorite(ctx, db.AddFavoriteParams{
		UserID:       userID,
		DeviceSerial: deviceSerial,
		RelPath:      relPath,
	}); err != nil {
		return false, err
	}
	// Best-effort: add to the Favorites smart album. A duplicate-key error
	// means it's already there (idempotent); any other failure is logged but
	// does not fail the toggle since photo_favorites is the source of truth.
	album, err := EnsureFavoritesAlbum(ctx, q, userID)
	if err == nil {
		if _, addErr := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{
			AlbumID:      album.ID,
			DeviceSerial: deviceSerial,
			RelPath:      relPath,
		}); addErr != nil && !sqlutil.IsUniqueConstraintErr(addErr) {
			log.Printf("[favorites] best-effort album add failed for %q: %v", relPath, addErr)
		}
	}
	return true, nil
}

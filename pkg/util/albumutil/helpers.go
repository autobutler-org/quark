package albumutil

import (
	"database/sql"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// checkSlash refuses a name containing the album path separator.
func checkSlash(name string) error {
	if strings.Contains(name, "/") {
		return ErrNameHasSlash
	}
	return nil
}

// checkName applies checkSlash, then reserves the Favorites name at the root.
// Once the system album exists the unique index already refuses the name; this
// covers the window before EnsureFavoritesAlbum has run, when a user album
// taking the name would make that insert fail.
func checkName(name string, parentID sql.NullInt64) error {
	if err := checkSlash(name); err != nil {
		return err
	}
	if !parentID.Valid && strings.EqualFold(name, favoritesutil.FavoritesAlbumName) {
		return ErrNameConflict
	}
	return nil
}

// nameConflictOr turns a unique-constraint failure into ErrNameConflict. The
// only unique index a user album can hit is idx_photo_albums_sibling_name.
func nameConflictOr(err error) error {
	if sqlutil.IsUniqueConstraintErr(err) {
		return ErrNameConflict
	}
	return err
}

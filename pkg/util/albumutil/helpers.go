package albumutil

import (
	"database/sql"
	"path"
	"sort"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
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

// sortItems orders items by sortBy and order in place, defaulting to the
// added_at DESC order ListAlbumItems already returns for a zero-value or
// unrecognized sortBy/order (#2509).
func sortItems(items []db.PhotoAlbumItem, sortBy, order string) {
	ascending := order == photoutil.OrderAsc
	if sortBy == photoutil.SortName {
		sort.Slice(items, func(i, j int) bool {
			ni := strings.ToLower(path.Base(items[i].RelPath))
			nj := strings.ToLower(path.Base(items[j].RelPath))
			if ascending {
				return ni < nj
			}
			return ni > nj
		})
		return
	}
	if ascending {
		sort.SliceStable(items, func(i, j int) bool {
			return items[i].AddedAt.Before(items[j].AddedAt)
		})
	}
}

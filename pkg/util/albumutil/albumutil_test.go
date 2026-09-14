package albumutil_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
)

func under(id int64) sql.NullInt64 { return sql.NullInt64{Int64: id, Valid: true} }

func create(t *testing.T, q *db.Queries, name string, parent sql.NullInt64) db.PhotoAlbum {
	t.Helper()
	result, err := albumutil.CreateAlbum(context.Background(), albumutil.CreateAlbumParams{
		Queries: q, Name: name, ParentID: parent,
	})
	if err != nil {
		t.Fatalf("CreateAlbum(%q): %v", name, err)
	}
	return result.Album
}

func TestCreateAlbum(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	trips := create(t, q, "Trips", sql.NullInt64{})
	create(t, q, "Japan", under(trips.ID))

	tests := []struct {
		name   string
		album  string
		parent sql.NullInt64
		want   error
	}{
		{"root case-only clash", "TRIPS", sql.NullInt64{}, albumutil.ErrNameConflict},
		{"nested clash", "japan", under(trips.ID), albumutil.ErrNameConflict},
		{"slash", "a/b", sql.NullInt64{}, albumutil.ErrNameHasSlash},
		{"reserved Favorites at root", "favorites", sql.NullInt64{}, albumutil.ErrNameConflict},
		{"same name under another parent", "Japan", sql.NullInt64{}, nil},
		{"Favorites nested", "Favorites", under(trips.ID), nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{
				Queries: q, Name: tt.album, ParentID: tt.parent,
			})
			if !errors.Is(err, tt.want) {
				t.Fatalf("CreateAlbum(%q) error = %v, want %v", tt.album, err, tt.want)
			}
		})
	}
}

func TestCreateAlbum_ClashWithSystemFavorites(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	if _, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q); err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	_, err := albumutil.CreateAlbum(context.Background(), albumutil.CreateAlbumParams{Queries: q, Name: "FAVORITES"})
	if !errors.Is(err, albumutil.ErrNameConflict) {
		t.Fatalf("error = %v, want ErrNameConflict", err)
	}
}

func TestRenameAlbum(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	trips := create(t, q, "Trips", sql.NullInt64{})
	create(t, q, "Beach", sql.NullInt64{})
	japan := create(t, q, "Japan", under(trips.ID))
	create(t, q, "Kyoto", under(trips.ID))

	tests := []struct {
		name  string
		id    int64
		album string
		want  error
	}{
		{"root case-only clash", trips.ID, "beach", albumutil.ErrNameConflict},
		{"nested clash", japan.ID, "KYOTO", albumutil.ErrNameConflict},
		{"slash", trips.ID, "a/b", albumutil.ErrNameHasSlash},
		{"reserved Favorites at root", trips.ID, "Favorites", albumutil.ErrNameConflict},
		{"missing album", 9999, "Nowhere", sql.ErrNoRows},
		{"own name in another case", trips.ID, "TRIPS", nil},
		{"Favorites nested", japan.ID, "Favorites", nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := albumutil.RenameAlbum(ctx, albumutil.RenameAlbumParams{Queries: q, ID: tt.id, Name: tt.album})
			if !errors.Is(err, tt.want) {
				t.Fatalf("RenameAlbum(%d, %q) error = %v, want %v", tt.id, tt.album, err, tt.want)
			}
		})
	}
}

func TestMoveAlbum(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	trips := create(t, q, "Trips", sql.NullInt64{})
	create(t, q, "Japan", under(trips.ID))
	rootJapan := create(t, q, "JAPAN", sql.NullInt64{})
	nestedTrips := create(t, q, "trips", under(rootJapan.ID))
	nestedFavorites := create(t, q, "Favorites", under(trips.ID))
	loose := create(t, q, "Loose", under(trips.ID))

	tests := []struct {
		name   string
		id     int64
		parent sql.NullInt64
		want   error
	}{
		{"into a parent with a clashing name", rootJapan.ID, under(trips.ID), albumutil.ErrNameConflict},
		{"to root with a clashing name", nestedTrips.ID, sql.NullInt64{}, albumutil.ErrNameConflict},
		{"Favorites to root", nestedFavorites.ID, sql.NullInt64{}, albumutil.ErrNameConflict},
		{"missing album", 9999, sql.NullInt64{}, sql.ErrNoRows},
		{"no clash", loose.ID, sql.NullInt64{}, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := albumutil.MoveAlbum(ctx, albumutil.MoveAlbumParams{Queries: q, ID: tt.id, ParentID: tt.parent})
			if !errors.Is(err, tt.want) {
				t.Fatalf("MoveAlbum(%d) error = %v, want %v", tt.id, err, tt.want)
			}
		})
	}
}

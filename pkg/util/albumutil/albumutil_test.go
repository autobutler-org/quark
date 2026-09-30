package albumutil_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

// fullAccess is an admin's access, which filters nothing.
func fullAccess(t *testing.T) accessutil.Access {
	t.Helper()
	loaded, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access
}

func under(id int64) sql.NullInt64 { return sql.NullInt64{Int64: id, Valid: true} }

// newOwnedQueries returns queries over a fresh database and an account to own
// albums.
func newOwnedQueries(t *testing.T) (*db.Queries, int64) {
	t.Helper()
	q := dbtest.NewDB(t).Queries
	user, err := q.CreateUser(context.Background(), db.CreateUserParams{Username: "founder", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	return q, user.ID
}

func create(t *testing.T, q *db.Queries, owner int64, name string, parent sql.NullInt64) db.PhotoAlbum {
	t.Helper()
	result, err := albumutil.CreateAlbum(context.Background(), albumutil.CreateAlbumParams{
		Queries: q, UserID: owner, Name: name, ParentID: parent,
	})
	if err != nil {
		t.Fatalf("CreateAlbum(%q): %v", name, err)
	}
	return result.Album
}

func TestCreateAlbum(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	trips := create(t, q, owner, "Trips", sql.NullInt64{})
	create(t, q, owner, "Japan", under(trips.ID))

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
				Queries: q, UserID: owner, Name: tt.album, ParentID: tt.parent,
			})
			if !errors.Is(err, tt.want) {
				t.Fatalf("CreateAlbum(%q) error = %v, want %v", tt.album, err, tt.want)
			}
		})
	}
}

func TestCreateAlbum_ClashWithSystemFavorites(t *testing.T) {
	q, owner := newOwnedQueries(t)
	if _, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q, owner); err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	_, err := albumutil.CreateAlbum(context.Background(), albumutil.CreateAlbumParams{Queries: q, UserID: owner, Name: "FAVORITES"})
	if !errors.Is(err, albumutil.ErrNameConflict) {
		t.Fatalf("error = %v, want ErrNameConflict", err)
	}
}

func TestRenameAlbum(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	trips := create(t, q, owner, "Trips", sql.NullInt64{})
	create(t, q, owner, "Beach", sql.NullInt64{})
	japan := create(t, q, owner, "Japan", under(trips.ID))
	create(t, q, owner, "Kyoto", under(trips.ID))

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
			_, err := albumutil.RenameAlbum(ctx, albumutil.RenameAlbumParams{Queries: q, UserID: owner, ID: tt.id, Name: tt.album})
			if !errors.Is(err, tt.want) {
				t.Fatalf("RenameAlbum(%d, %q) error = %v, want %v", tt.id, tt.album, err, tt.want)
			}
		})
	}
}

func TestMoveAlbum(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	trips := create(t, q, owner, "Trips", sql.NullInt64{})
	create(t, q, owner, "Japan", under(trips.ID))
	rootJapan := create(t, q, owner, "JAPAN", sql.NullInt64{})
	nestedTrips := create(t, q, owner, "trips", under(rootJapan.ID))
	nestedFavorites := create(t, q, owner, "Favorites", under(trips.ID))
	loose := create(t, q, owner, "Loose", under(trips.ID))

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
			_, err := albumutil.MoveAlbum(ctx, albumutil.MoveAlbumParams{Queries: q, UserID: owner, ID: tt.id, ParentID: tt.parent})
			if !errors.Is(err, tt.want) {
				t.Fatalf("MoveAlbum(%d) error = %v, want %v", tt.id, err, tt.want)
			}
		})
	}
}

// TestListItems_SortByName checks the name sort against RelPath's base name,
// independent of insertion (added_at) order.
func TestListItems_SortByName(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	album := create(t, q, owner, "Trips", sql.NullInt64{})
	for _, name := range []string{"charlie.jpg", "alpha.jpg", "bravo.jpg"} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, DeviceSerial: "dev", RelPath: name}); err != nil {
			t.Fatalf("AddPhotoToAlbum(%q): %v", name, err)
		}
	}

	ascending, err := albumutil.ListItems(ctx, albumutil.ListItemsParams{
		Queries: q, Access: fullAccess(t), AlbumID: album.ID, Sort: photoutil.SortName, Order: photoutil.OrderAsc,
	})
	if err != nil {
		t.Fatalf("ListItems asc: %v", err)
	}
	wantAsc := []string{"alpha.jpg", "bravo.jpg", "charlie.jpg"}
	for i, want := range wantAsc {
		if ascending.Items[i].RelPath != want {
			t.Fatalf("ascending[%d] = %q, want %q", i, ascending.Items[i].RelPath, want)
		}
	}

	descending, err := albumutil.ListItems(ctx, albumutil.ListItemsParams{
		Queries: q, Access: fullAccess(t), AlbumID: album.ID, Sort: photoutil.SortName, Order: photoutil.OrderDesc,
	})
	if err != nil {
		t.Fatalf("ListItems desc: %v", err)
	}
	wantDesc := []string{"charlie.jpg", "bravo.jpg", "alpha.jpg"}
	for i, want := range wantDesc {
		if descending.Items[i].RelPath != want {
			t.Fatalf("descending[%d] = %q, want %q", i, descending.Items[i].RelPath, want)
		}
	}
}

// TestListItems_SortByTaken orders by the photo's capture date, standing in
// added_at for a photo with none, and reports the dates it used (#2592).
func TestListItems_SortByTaken(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	album := create(t, q, owner, "Trips", sql.NullInt64{})
	// Added in this order, so undated.jpg's added_at is now: the newest date.
	for _, name := range []string{"2023.jpg", "2019.jpg", "undated.jpg"} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, DeviceSerial: "dev", RelPath: name}); err != nil {
			t.Fatalf("AddPhotoToAlbum(%q): %v", name, err)
		}
	}
	dates := map[string]time.Time{
		"2019.jpg": time.Date(2019, 7, 4, 12, 0, 0, 0, time.UTC),
		"2023.jpg": time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC),
	}
	for name, taken := range dates {
		if err := q.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{
			DeviceSerial: "dev", RelPath: name, TakenAt: sql.NullTime{Time: taken, Valid: true}, TakenChecked: true,
		}); err != nil {
			t.Fatal(err)
		}
	}

	for _, tt := range []struct {
		order string
		want  []string
	}{
		{photoutil.OrderDesc, []string{"undated.jpg", "2023.jpg", "2019.jpg"}},
		{photoutil.OrderAsc, []string{"2019.jpg", "2023.jpg", "undated.jpg"}},
	} {
		result, err := albumutil.ListItems(ctx, albumutil.ListItemsParams{
			Queries: q, Access: fullAccess(t), AlbumID: album.ID, Sort: photoutil.SortTaken, Order: tt.order,
		})
		if err != nil {
			t.Fatalf("ListItems %s: %v", tt.order, err)
		}
		for i, want := range tt.want {
			if result.Items[i].RelPath != want {
				t.Fatalf("%s[%d] = %q, want %q", tt.order, i, result.Items[i].RelPath, want)
			}
		}
		for _, item := range result.Items {
			got, ok := result.TakenAt[item.ID]
			if want, dated := dates[item.RelPath]; ok != dated || !got.Equal(want) {
				t.Errorf("TakenAt[%s] = %v (present %v), want %v", item.RelPath, got, ok, want)
			}
		}
	}
}

// TestListItems_DefaultMatchesAddedAtDesc checks that an unspecified Sort and
// Order leaves the SQL query's own added_at DESC order untouched.
func TestListItems_DefaultMatchesAddedAtDesc(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	album := create(t, q, owner, "Trips", sql.NullInt64{})
	for _, name := range []string{"first.jpg", "second.jpg"} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, DeviceSerial: "dev", RelPath: name}); err != nil {
			t.Fatalf("AddPhotoToAlbum(%q): %v", name, err)
		}
	}

	direct, err := q.ListAlbumItems(ctx, album.ID)
	if err != nil {
		t.Fatalf("ListAlbumItems: %v", err)
	}
	result, err := albumutil.ListItems(ctx, albumutil.ListItemsParams{Queries: q, Access: fullAccess(t), AlbumID: album.ID})
	if err != nil {
		t.Fatalf("ListItems: %v", err)
	}
	if len(result.Items) != len(direct) {
		t.Fatalf("got %d items, want %d", len(result.Items), len(direct))
	}
	for i := range direct {
		if result.Items[i].RelPath != direct[i].RelPath {
			t.Fatalf("item %d = %q, want %q (default order should match ListAlbumItems)", i, result.Items[i].RelPath, direct[i].RelPath)
		}
	}
}

// TestAlbumsPerAccount checks two accounts each name their own root albums and
// cannot reach each other's albums by id (#1912).
func TestAlbumsPerAccount(t *testing.T) {
	q, owner := newOwnedQueries(t)
	ctx := context.Background()
	other, err := q.CreateUser(ctx, db.CreateUserParams{Username: "other", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	mine := create(t, q, owner, "Trips", sql.NullInt64{})
	create(t, q, other.ID, "trips", sql.NullInt64{})

	if _, err := albumutil.RenameAlbum(ctx, albumutil.RenameAlbumParams{Queries: q, UserID: other.ID, ID: mine.ID, Name: "Mine"}); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("renaming another account's album: error = %v, want sql.ErrNoRows", err)
	}
	if _, err := albumutil.MoveAlbum(ctx, albumutil.MoveAlbumParams{Queries: q, UserID: other.ID, ID: mine.ID}); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("moving another account's album: error = %v, want sql.ErrNoRows", err)
	}
}

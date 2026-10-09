package photoutil_test

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"

	_ "modernc.org/sqlite"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// --- ParsePagination ---

func TestParsePagination(t *testing.T) {
	cases := []struct {
		name             string
		offsetRaw        string
		limitRaw         string
		wantOff, wantLim int
	}{
		{"defaults", "", "", 0, 50},
		{"parsed", "10", "25", 10, 25},
		{"clamped to max", "0", "1000", 0, 200},
		{"negative offset ignored", "-5", "", 0, 50},
		{"zero limit ignored", "", "0", 0, 50},
		{"garbage ignored", "abc", "xyz", 0, 50},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			offset, limit := photoutil.ParsePagination(tc.offsetRaw, tc.limitRaw)
			if offset != tc.wantOff || limit != tc.wantLim {
				t.Errorf("ParsePagination(%q, %q) = (%d, %d), want (%d, %d)",
					tc.offsetRaw, tc.limitRaw, offset, limit, tc.wantOff, tc.wantLim)
			}
		})
	}
}

// --- ParseDuplicateThreshold ---

func TestParseDuplicateThreshold(t *testing.T) {
	cases := []struct {
		raw  string
		want int
	}{
		{"", 10},
		{"0", 0},
		{"5", 5},
		{"20", 20},
		{"21", 10},
		{"-1", 10},
		{"abc", 10},
	}
	for _, tc := range cases {
		if got := photoutil.ParseDuplicateThreshold(tc.raw); got != tc.want {
			t.Errorf("ParseDuplicateThreshold(%q) = %d, want %d", tc.raw, got, tc.want)
		}
	}
}

// --- ParseSort / ParseOrder ---

func TestParseSort(t *testing.T) {
	cases := []struct{ raw, want string }{
		{"", "added"},
		{"added", "added"},
		{"name", "name"},
		{"taken", "taken"},
		{"garbage", "added"},
	}
	for _, tc := range cases {
		if got := photoutil.ParseSort(tc.raw); got != tc.want {
			t.Errorf("ParseSort(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

func TestParseOrder(t *testing.T) {
	cases := []struct{ raw, want string }{
		{"", "desc"},
		{"desc", "desc"},
		{"asc", "asc"},
		{"garbage", "desc"},
	}
	for _, tc := range cases {
		if got := photoutil.ParseOrder(tc.raw); got != tc.want {
			t.Errorf("ParseOrder(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

// --- ListPhotos (VFS path) ---

// newPhotoRegistry is a registry whose internal "files" namespace is a MemVFS
// holding paths.
func newPhotoRegistry(t *testing.T, paths ...string) vfs.Registry {
	t.Helper()
	mem := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for _, p := range paths {
		if err := mem.Write(context.Background(), p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatalf("write %s: %v", p, err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, mem); err != nil {
		t.Fatal(err)
	}
	return registry
}

func TestListPhotos_VFS_ListsImagesOnly(t *testing.T) {
	registry := newPhotoRegistry(t, "a.jpg", "sub/b.png", "notes.txt")

	result, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx:      context.Background(),
		Registry: registry,
		Access:   systemAccess(t),
		Offset:   0,
		Limit:    50,
	})
	if err != nil {
		t.Fatalf("ListPhotos: %v", err)
	}
	if result.Total != 2 {
		t.Fatalf("Total = %d, want 2 (the two images)", result.Total)
	}
	for _, p := range result.Photos {
		if strings.HasSuffix(p.RelPath, ".txt") {
			t.Errorf("non-image %q in result", p.RelPath)
		}
	}
}

func TestListPhotos_VFS_Paginates(t *testing.T) {
	registry := newPhotoRegistry(t, "a.jpg", "b.jpg", "c.jpg")

	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t), Offset: 1, Limit: 1,
	})
	if err != nil {
		t.Fatalf("ListPhotos: %v", err)
	}
	if page.Total != 3 || len(page.Photos) != 1 || page.Offset != 1 || page.Limit != 1 {
		t.Errorf("got total=%d photos=%d offset=%d limit=%d, want 3/1/1/1",
			page.Total, len(page.Photos), page.Offset, page.Limit)
	}
}

func TestListPhotos_VFS_SortByNameAscending(t *testing.T) {
	registry := newPhotoRegistry(t, "charlie.jpg", "alpha.jpg", "bravo.jpg")

	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t),
		Sort: "name", Order: "asc", Offset: 0, Limit: 50,
	})
	if err != nil {
		t.Fatalf("ListPhotos: %v", err)
	}
	got := []string{page.Photos[0].FileName, page.Photos[1].FileName, page.Photos[2].FileName}
	want := []string{"alpha.jpg", "bravo.jpg", "charlie.jpg"}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("got order %v, want %v", got, want)
			break
		}
	}
}

func TestListPhotos_VFS_SortByNameDescending(t *testing.T) {
	registry := newPhotoRegistry(t, "alpha.jpg", "charlie.jpg", "bravo.jpg")

	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t),
		Sort: "name", Order: "desc", Offset: 0, Limit: 50,
	})
	if err != nil {
		t.Fatalf("ListPhotos: %v", err)
	}
	got := []string{page.Photos[0].FileName, page.Photos[1].FileName, page.Photos[2].FileName}
	want := []string{"charlie.jpg", "bravo.jpg", "alpha.jpg"}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("got order %v, want %v", got, want)
			break
		}
	}
}

func TestListPhotos_VFS_OffsetBeyondTotal(t *testing.T) {
	registry := newPhotoRegistry(t, "a.jpg")

	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t), Offset: 99, Limit: 50,
	})
	if err != nil {
		t.Fatalf("ListPhotos: %v", err)
	}
	if page.Photos == nil {
		t.Fatal("Photos = nil, want an empty slice so it serializes as []")
	}
	if len(page.Photos) != 0 || page.Total != 1 {
		t.Errorf("got %d photos, total %d, want 0 photos and total 1", len(page.Photos), page.Total)
	}
}

// --- SaveRotation ---

func newRotationDB(t *testing.T) *db.Queries {
	t.Helper()
	return dbtest.NewDB(t).Queries
}

func TestSaveRotation_NormalizesAndDeletes(t *testing.T) {
	ctx := context.Background()
	queries := newRotationDB(t)

	save := func(quarters int64) {
		t.Helper()
		if err := photoutil.SaveRotation(photoutil.SaveRotationParams{
			Ctx:              ctx,
			Queries:          queries,
			RelPath:          "a.jpg",
			RotationQuarters: quarters,
		}); err != nil {
			t.Fatalf("SaveRotation(%d): %v", quarters, err)
		}
	}
	read := func() (int64, error) {
		return queries.GetPhotoRotation(ctx, db.GetPhotoRotationParams{RelPath: "a.jpg"})
	}

	// Out-of-range values wrap into 0–3.
	save(5)
	if got, err := read(); err != nil || got != 1 {
		t.Fatalf("after save(5): rotation = %d, err = %v, want 1", got, err)
	}
	save(-1)
	if got, err := read(); err != nil || got != 3 {
		t.Fatalf("after save(-1): rotation = %d, err = %v, want 3", got, err)
	}

	// A normalized zero removes the record rather than storing it.
	save(4)
	if _, err := read(); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("after save(4): err = %v, want sql.ErrNoRows", err)
	}
}

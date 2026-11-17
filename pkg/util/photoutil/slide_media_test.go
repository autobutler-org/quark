package photoutil_test

import (
	"context"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func TestListPhotos_SkipsPicturesOfImportedPresentations(t *testing.T) {
	registry := newPhotoRegistry(t,
		"Talk.qslide",
		"Talk_media/image1.png",
		"Talk_media/image2.jpeg",
		"work/Pitch_(1).qslide",
		"work/Pitch_media/image1.png",
		"work/Deck_(2)_media/image1.png",
		"work/Deck_(2).qslide",
		"Trip_media/beach.jpg",
		"holiday.jpg",
	)

	result, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t),
		Sort: photoutil.SortName, Order: photoutil.OrderAsc, Limit: 50,
	})
	if err != nil {
		t.Fatal(err)
	}
	got := []string{}
	for _, p := range result.Photos {
		got = append(got, p.RelPath)
	}
	want := []string{"Trip_media/beach.jpg", "holiday.jpg"}
	slices.Sort(got)
	if !slices.Equal(got, want) || result.Total != len(want) {
		t.Fatalf("photos = %v (total %d), want %v: a presentation's pictures are not photos", got, result.Total, want)
	}
}

// TestListPhotos_AdoptsImportedPicturesByReference: the old name-based filter
// lost a presentation's pictures after the .qslide was renamed, moved or
// deleted. The references in the deck identify its legacy media directory;
// once adopted, that ownership survives the deck disappearing.
func TestListPhotos_AdoptsImportedPicturesByReference(t *testing.T) {
	registry := newPhotoRegistry(t,
		"Talk_media/image1.png",
		"Trip_media/beach.jpg",
	)
	fsys, _ := registry.Get(vfs.FilesNamespace(""))
	deck := `{"schemaVersion":1,"title":"Talk","slides":[{"id":"s","elements":[{"id":"i","type":"image","frame":{"x":0,"y":0,"width":1,"height":1},"source":"Talk_media/image1.png"}]}]}`
	if err := fsys.Write(context.Background(), "archive/Renamed Talk.qslide", strings.NewReader(deck), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}

	list := func() []string {
		t.Helper()
		result, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
			Ctx: context.Background(), Registry: registry, Access: systemAccess(t),
			Sort: photoutil.SortName, Order: photoutil.OrderAsc, Limit: 50,
		})
		if err != nil {
			t.Fatal(err)
		}
		got := make([]string, 0, len(result.Photos))
		for _, photo := range result.Photos {
			got = append(got, photo.RelPath)
		}
		return got
	}

	if got, want := list(), []string{"Trip_media/beach.jpg"}; !slices.Equal(got, want) {
		t.Fatalf("with renamed and moved deck: photos = %v, want %v", got, want)
	}
	if err := fsys.Move(context.Background(), "Talk_media", "presentation-assets"); err != nil {
		t.Fatal(err)
	}
	if err := fsys.Delete(context.Background(), "archive/Renamed Talk.qslide", vfs.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	if got, want := list(), []string{"Trip_media/beach.jpg"}; !slices.Equal(got, want) {
		t.Fatalf("after media move and deck deletion: photos = %v, want %v", got, want)
	}
}

// TestListDuplicates_SkipsDocumentMedia: rendering a thumbnail used to leave
// an imported picture in duplicate groups even though the grid hid it.
func TestListDuplicates_SkipsDocumentMedia(t *testing.T) {
	ctx := context.Background()
	registry := newPhotoRegistry(t, "Talk_media/a.png", "Talk_media/b.png")
	fsys, _ := registry.Get(vfs.FilesNamespace(""))
	deck := `{"schemaVersion":1,"title":"Talk","slides":[{"elements":[
		{"type":"image","source":"Talk_media/a.png"},
		{"type":"image","source":"Talk_media/b.png"}
	]}]}`
	if err := fsys.Write(ctx, "Renamed.qslide", strings.NewReader(deck), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	seedHashes(t, database.Queries, []hashRow{
		{"", "Talk_media/a.png", "0000000000000000", "same"},
		{"", "Talk_media/b.png", "0000000000000000", "same"},
	})

	got := listGroups(t, photoutil.ListDuplicatesParams{
		Ctx: ctx, Queries: database.Queries, Threshold: 4, Access: systemAccess(t),
		Exists: photoutil.ExistsIn(ctx, registry),
	})
	if len(got) != 0 {
		t.Fatalf("duplicate groups = %q, want none", got)
	}
}

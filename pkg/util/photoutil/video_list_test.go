package photoutil_test

import (
	"context"
	"os"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// videoFixture is a real three-second H.264 clip from videoutil's corpus, so the
// listing has a duration to read.
const videoFixture = "../videoutil/testdata/h264-gop12.mp4"

// videoLibrary is the internal drive holding a photo, a Live Photo and its
// companion video, a standalone clip that really parses, and one that does
// not.
func videoLibrary(t *testing.T) vfs.Registry {
	t.Helper()
	registry := twoDevices(t, map[string]string{
		"beach.jpg":    "x",
		"IMG_1.HEIC":   "x",
		"IMG_1.MOV":    "live companion",
		"broken.mp4":   "not a video",
		"cake/cut.png": "x",
	}, nil)
	clip, err := os.Open(videoFixture)
	if err != nil {
		t.Fatal(err)
	}
	defer clip.Close()
	fsys, ok := registry.Get(vfs.FilesNamespace(""))
	if !ok {
		t.Fatal("no internal drive")
	}
	if err := fsys.Write(context.Background(), "party/clip.mp4", clip, vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	return registry
}

// TestListPhotos_IncludesVideos: Photos listed images only, so a video
// uploaded to Quark never showed up there (#3428). A standalone video is
// listed as one, with its duration; a Live Photo's companion video stays
// folded into its photo.
func TestListPhotos_IncludesVideos(t *testing.T) {
	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: videoLibrary(t), Access: systemAccess(t),
		Sort: photoutil.SortName, Order: photoutil.OrderAsc, Limit: 50, IncludeVideos: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]photoutil.PhotoSummary{}
	for _, p := range page.Photos {
		got[p.RelPath] = p
	}
	want := map[string]bool{ // path -> is a video
		"beach.jpg": false, "IMG_1.HEIC": false, "cake/cut.png": false,
		"party/clip.mp4": true, "broken.mp4": true,
	}
	if len(got) != len(want) || page.Total != len(want) {
		t.Fatalf("listed %v (total %d), want %v", keys(got), page.Total, want)
	}
	for p, video := range want {
		if got[p].IsVideo != video {
			t.Errorf("%s: isVideo = %v, want %v", p, got[p].IsVideo, video)
		}
	}
	if !got["IMG_1.HEIC"].HasLiveVideo {
		t.Error("IMG_1.HEIC lost its Live Photo flag")
	}
	if d := got["party/clip.mp4"].DurationMs; d < 2500 || d > 3500 {
		t.Errorf("clip.mp4 durationMs = %d, want about 3000", d)
	}
	// A clip that does not parse is still the user's video, just without a
	// duration to show.
	if d := got["broken.mp4"].DurationMs; d != 0 {
		t.Errorf("broken.mp4 durationMs = %d, want 0", d)
	}
	for p, s := range got {
		if !want[p] && s.DurationMs != 0 {
			t.Errorf("%s: a photo has durationMs %d", p, s.DurationMs)
		}
	}
}

// TestListPhotos_VideosAreOptIn: without IncludeVideos the listing is the
// images it always was, for a client that can only open an image and for the
// hashing backfill, which has nothing to hash in a video.
func TestListPhotos_VideosAreOptIn(t *testing.T) {
	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: videoLibrary(t), Access: systemAccess(t),
		Limit: 50,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range page.Photos {
		if p.IsVideo {
			t.Errorf("listed the video %s without IncludeVideos", p.RelPath)
		}
	}
	if page.Total != 3 {
		t.Errorf("total = %d, want the 3 photos", page.Total)
	}
}

// TestListPhotos_TakenSortDatesVideosByDateAdded: a video has no EXIF, so the
// taken sort places it by its date added and never counts it as pending, which
// would keep a client polling forever.
func TestListPhotos_TakenSortDatesVideosByDateAdded(t *testing.T) {
	database := dbtest.NewDB(t)
	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: videoLibrary(t), Access: systemAccess(t),
		Sort: photoutil.SortTaken, Queries: database.Queries, Limit: 50, IncludeVideos: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if page.PendingDates != 0 {
		t.Errorf("pendingDates = %d, want 0", page.PendingDates)
	}
	rows, err := database.Queries.ListPhotoHashStates(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range rows {
		if row.RelPath == "party/clip.mp4" || row.RelPath == "broken.mp4" {
			t.Errorf("the taken sort stored a photo row for the video %s", row.RelPath)
		}
	}
}

func keys(m map[string]photoutil.PhotoSummary) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

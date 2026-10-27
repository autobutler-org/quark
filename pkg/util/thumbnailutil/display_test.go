package thumbnailutil

import (
	"bytes"
	"context"
	"image"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// photoLibrary writes a w × h JPEG named name into a fresh files namespace,
// with HOME, and so the thumbnail cache, isolated to the test.
func photoLibrary(t *testing.T, name string, w, h int) (vfs.VFS, time.Time) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	dir := t.TempDir()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, w, h)), nil); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), buf.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(dir, name))
	if err != nil {
		t.Fatal(err)
	}
	fsys, err := vfs.NewLocalVFS(dir, vfs.FilesNamespace(""))
	if err != nil {
		t.Fatal(err)
	}
	return fsys, info.ModTime()
}

// prepareAndGenerate runs a library thumbnail request the way the handler
// does and returns the prepared entry and the dimensions of what was cached.
func prepareAndGenerate(t *testing.T, fsys vfs.VFS, params PrepareParams) (PrepareResult, image.Point) {
	t.Helper()
	prepared, err := Prepare(params)
	if err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	if !prepared.Hit {
		if _, err := Generate(GenerateParams{
			Ctx: context.Background(), FS: fsys, RelPath: params.RelPath, Ext: ".jpg",
			Width: prepared.Width, Height: prepared.Height, Resize: prepared.Resize,
			RotationQuarters: prepared.RotationQuarters, CachedPath: prepared.CachedPath,
		}); err != nil {
			t.Fatalf("Generate: %v", err)
		}
	}
	f, err := os.Open(prepared.CachedPath)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cfg, err := jpeg.DecodeConfig(f)
	if err != nil {
		t.Fatalf("cache entry is not a JPEG: %v", err)
	}
	return prepared, image.Pt(cfg.Width, cfg.Height)
}

// The xl tier is the whole photo, long edge capped at 1280: a 2560x1600
// landscape comes out 1280x800, not a cropped square.
func TestXlIsUncroppedWithItsLongEdgeCapped(t *testing.T) {
	for _, tt := range []struct {
		name string
		w, h int
		want image.Point
	}{
		{"landscape.jpg", 2560, 1600, image.Pt(1280, 800)},
		{"portrait.jpg", 1500, 3000, image.Pt(640, 1280)},
	} {
		fsys, modTime := photoLibrary(t, tt.name, tt.w, tt.h)
		_, got := prepareAndGenerate(t, fsys, PrepareParams{
			Queries: dbtest.NewDB(t).Queries, RelPath: tt.name, FilePath: "/" + tt.name,
			Size: SizeXl, SrcModTime: modTime,
		})
		if got != tt.want {
			t.Errorf("%s: %dx%d at xl is %v, want %v", tt.name, tt.w, tt.h, got, tt.want)
		}
	}
}

// A photo smaller than the display box is served at its own size.
func TestXlNeverUpscalesASmallPhoto(t *testing.T) {
	fsys, modTime := photoLibrary(t, "small.jpg", 300, 200)
	_, got := prepareAndGenerate(t, fsys, PrepareParams{
		Queries: dbtest.NewDB(t).Queries, RelPath: "small.jpg", FilePath: "/small.jpg",
		Size: SizeXl, SrcModTime: modTime,
	})
	if got != image.Pt(300, 200) {
		t.Errorf("a 300x200 photo at xl is %v, want 300x200", got)
	}
}

// xl is cached like every tier: a second request is a hit on the same
// entry, separate from lg's, and a source rewritten after it, or a new
// rotation, misses.
func TestXlIsCachedAndInvalidatedLikeTheOtherTiers(t *testing.T) {
	fsys, modTime := photoLibrary(t, "photo.jpg", 2000, 1000)
	database := dbtest.NewDB(t)
	params := PrepareParams{
		Queries: database.Queries, RelPath: "photo.jpg", FilePath: "/photo.jpg",
		Size: SizeXl, SrcModTime: modTime,
	}
	first, _ := prepareAndGenerate(t, fsys, params)
	if first.Hit {
		t.Fatal("the first xl request found an entry already cached")
	}
	if first.Resize != photoutil.ResizeFit {
		t.Errorf("xl prepares Resize %v, want ResizeFit", first.Resize)
	}

	second, err := Prepare(params)
	if err != nil {
		t.Fatal(err)
	}
	if !second.Hit || second.CachedPath != first.CachedPath {
		t.Errorf("the second xl request is %+v, want a hit on %s", second, first.CachedPath)
	}

	lg, err := Prepare(PrepareParams{
		Queries: database.Queries, RelPath: "photo.jpg", FilePath: "/photo.jpg",
		Size: SizeLg, SrcModTime: modTime,
	})
	if err != nil {
		t.Fatal(err)
	}
	if lg.CachedPath == first.CachedPath || lg.Resize != photoutil.ResizeCrop {
		t.Errorf("lg shares xl's entry or mode: %+v", lg)
	}

	rewritten := params
	rewritten.SrcModTime = time.Now().Add(time.Hour)
	if stale, err := Prepare(rewritten); err != nil || stale.Hit {
		t.Errorf("a source newer than its xl entry is %+v, %v; want a miss", stale, err)
	}

	if err := database.Queries.UpsertPhotoRotation(context.Background(), db.UpsertPhotoRotationParams{
		RelPath: "photo.jpg", RotationQuarters: 1,
	}); err != nil {
		t.Fatalf("rotate photo: %v", err)
	}
	rotated, err := Prepare(params)
	if err != nil {
		t.Fatal(err)
	}
	if rotated.Hit || rotated.CachedPath == first.CachedPath {
		t.Errorf("a rotated photo's xl request is %+v, want a miss on a new entry", rotated)
	}
}

// A client thumbnail is a 400px square-ish JPEG; xl from it would be an
// upscale, so xl never comes from one.
func TestXlIsNeverServedFromAClientThumbnail(t *testing.T) {
	_, modTime := writeSource(t, "photo.heic")
	database := dbtest.NewDB(t)
	if err := store(t, StoreClientThumbnailParams{
		Queries: database.Queries, RelPath: "photo.heic",
		Reader: bytes.NewReader(clientJPEG(t, 300, 400)),
	}); err != nil {
		t.Fatal(err)
	}
	result, err := FromClientThumbnail(FromClientThumbnailParams{
		Queries: database.Queries, RelPath: "photo.heic", FilePath: "/photo.heic",
		SourceModTime: modTime, Size: SizeXl,
	})
	if err != nil || result.Found {
		t.Fatalf("xl from a client thumbnail is %+v, %v; want it not found", result, err)
	}
}

package thumbnailutil

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
)

// clientThumbnail is a 400x300 JPEG like the one a client uploads.
func clientThumbnail(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 400, 300))
	for x := 0; x < 200; x++ {
		for y := 0; y < 300; y++ {
			img.Pix[img.PixOffset(x, y)+0] = 255
			img.Pix[img.PixOffset(x, y)+3] = 255
		}
	}
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// writeVideo writes a file the device cannot decode, so any thumbnail it
// serves has to have come from the store.
func writeVideo(t *testing.T) (string, time.Time) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	source := filepath.Join(t.TempDir(), "clip.mov")
	if err := os.WriteFile(source, []byte("not really a video"), 0o600); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(source)
	if err != nil {
		t.Fatal(err)
	}
	return source, info.ModTime()
}

func TestFromStoreWithoutDerivativeIsNotFound(t *testing.T) {
	source, modTime := writeVideo(t)
	result, err := FromStore(FromStoreParams{
		Queries: dbtest.NewDB(t).Queries, RelPath: "clip.mov", FilePath: "/clip.mov",
		SourcePath: source, SourceModTime: modTime, Size: SizeSm, IsVideo: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Found {
		t.Fatal("no derivative was stored, so nothing should be found")
	}
}

func TestStoreDerivativesThenFromStoreServesResizedThumbnail(t *testing.T) {
	source, modTime := writeVideo(t)
	database := dbtest.NewDB(t)

	stored, err := StoreDerivative(StoreDerivativeParams{
		Queries: database.Queries, RelPath: "clip.mov", SourcePath: source,
		Kind: derivativeutil.KindThumbnail, Reader: bytes.NewReader(clientThumbnail(t)), IsVideo: true,
	})
	if err != nil {
		t.Fatalf("StoreDerivative: %v", err)
	}
	if stored.Path == "" {
		t.Fatal("StoreDerivative should report where it stored the thumbnail")
	}

	result, err := FromStore(FromStoreParams{
		Queries: database.Queries, RelPath: "clip.mov", FilePath: "/clip.mov",
		SourcePath: source, SourceModTime: modTime, Size: SizeSm, IsVideo: true,
	})
	if err != nil {
		t.Fatalf("FromStore: %v", err)
	}
	if !result.Found {
		t.Fatal("the stored thumbnail should be found")
	}
	f, err := os.Open(result.CachedPath)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cfg, format, err := image.DecodeConfig(f)
	if err != nil {
		t.Fatal(err)
	}
	if format != "jpeg" || cfg.Width != 96 || cfg.Height != 96 {
		t.Errorf("got a %dx%d %s, want a 96x96 jpeg", cfg.Width, cfg.Height, format)
	}
}

func TestStoreDerivativeRecordsDHashForPhotos(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	source := filepath.Join(t.TempDir(), "photo.heic")
	if err := os.WriteFile(source, []byte("heic"), 0o600); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)

	if _, err := StoreDerivative(StoreDerivativeParams{
		Queries: database.Queries, Serial: "", RelPath: "photo.heic", SourcePath: source,
		Kind: derivativeutil.KindThumbnail, Reader: bytes.NewReader(clientThumbnail(t)),
	}); err != nil {
		t.Fatalf("StoreDerivative: %v", err)
	}

	rows, err := database.Queries.ListNearDuplicates(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].RelPath != "photo.heic" || !rows[0].Dhash.Valid {
		t.Fatalf("want one dHash row for photo.heic, got %+v", rows)
	}
}

func TestStoreDerivativeRejectsInvalidBody(t *testing.T) {
	source, _ := writeVideo(t)
	_, err := StoreDerivative(StoreDerivativeParams{
		Queries: dbtest.NewDB(t).Queries, RelPath: "clip.mov", SourcePath: source,
		Kind: derivativeutil.KindThumbnail, Reader: bytes.NewReader([]byte("nope")), IsVideo: true,
	})
	if !errors.Is(err, derivativeutil.ErrInvalid) {
		t.Fatalf("want ErrInvalid, got %v", err)
	}
}

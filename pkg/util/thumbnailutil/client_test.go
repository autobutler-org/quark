package thumbnailutil

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// clientJPEG is a JPEG like the thumbnail a client uploads.
func clientJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, w, h)), nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// writeSource writes a file the device cannot decode, so any thumbnail served
// for it came from the client.
func writeSource(t *testing.T, name string) (string, time.Time) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	source := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(source, []byte("not decodable here"), 0o600); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(source)
	if err != nil {
		t.Fatal(err)
	}
	return source, info.ModTime()
}

func store(t *testing.T, params StoreClientThumbnailParams) error {
	t.Helper()
	_, err := StoreClientThumbnail(params)
	return err
}

func TestFromClientThumbnailWithoutOneIsNotFound(t *testing.T) {
	_, modTime := writeSource(t, "clip.mov")
	result, err := FromClientThumbnail(FromClientThumbnailParams{
		Queries: dbtest.NewDB(t).Queries, RelPath: "clip.mov", FilePath: "/clip.mov",
		SourceModTime: modTime, Size: SizeSm,
	})
	if err != nil || result.Found {
		t.Fatalf("want nothing found, got %+v, %v", result, err)
	}
}

func TestStoredClientThumbnailServesEveryTier(t *testing.T) {
	_, modTime := writeSource(t, "clip.mov")
	database := dbtest.NewDB(t)
	if err := store(t, StoreClientThumbnailParams{
		Queries: database.Queries, RelPath: "/clip.mov", IsVideo: true,
		Reader: bytes.NewReader(clientJPEG(t, 400, 225)),
	}); err != nil {
		t.Fatalf("StoreClientThumbnail: %v", err)
	}

	for size, edge := range map[Size]int{SizeSm: 96, SizeMd: 240, SizeLg: 400} {
		// The request path keeps its leading slash; the stored one was
		// written without caring which spelling it came in.
		result, err := FromClientThumbnail(FromClientThumbnailParams{
			Queries: database.Queries, RelPath: "clip.mov", FilePath: "/clip.mov",
			SourceModTime: modTime, Size: size,
		})
		if err != nil || !result.Found {
			t.Fatalf("%s: want the stored thumbnail, got %+v, %v", size, result, err)
		}
		f, err := os.Open(result.CachedPath)
		if err != nil {
			t.Fatal(err)
		}
		cfg, format, err := image.DecodeConfig(f)
		f.Close()
		if err != nil || format != "jpeg" || cfg.Width != edge || cfg.Height != edge {
			t.Errorf("%s: got %dx%d %s (%v), want %dx%d jpeg", size, cfg.Width, cfg.Height, format, err, edge, edge)
		}
	}
}

func TestClientThumbnailOlderThanItsFileIsStale(t *testing.T) {
	_, modTime := writeSource(t, "photo.heic")
	database := dbtest.NewDB(t)
	if err := store(t, StoreClientThumbnailParams{
		Queries: database.Queries, RelPath: "photo.heic",
		Reader: bytes.NewReader(clientJPEG(t, 300, 400)),
	}); err != nil {
		t.Fatal(err)
	}
	// The file was rewritten after the thumbnail was: it shows the old one.
	result, err := FromClientThumbnail(FromClientThumbnailParams{
		Queries: database.Queries, RelPath: "photo.heic", FilePath: "/photo.heic",
		SourceModTime: modTime.Add(time.Hour), Size: SizeSm,
	})
	if err != nil || result.Found {
		t.Fatalf("want a stale thumbnail ignored, got %+v, %v", result, err)
	}
}

func TestStoreClientThumbnailRecordsDHashForPhotos(t *testing.T) {
	writeSource(t, "photo.heic")
	database := dbtest.NewDB(t)
	if err := store(t, StoreClientThumbnailParams{
		Queries: database.Queries, RelPath: "photo.heic",
		Reader: bytes.NewReader(clientJPEG(t, 300, 400)),
	}); err != nil {
		t.Fatal(err)
	}
	rows, err := database.Queries.ListNearDuplicates(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].RelPath != "photo.heic" || !rows[0].Dhash.Valid {
		t.Fatalf("want one dHash row for photo.heic, got %+v", rows)
	}
}

func TestStoreClientThumbnailRejectsWhatIsNotAThumbnail(t *testing.T) {
	writeSource(t, "clip.mov")
	var pngBuf bytes.Buffer
	if err := png.Encode(&pngBuf, image.NewRGBA(image.Rect(0, 0, 4, 4))); err != nil {
		t.Fatal(err)
	}
	for name, body := range map[string][]byte{
		"png":        pngBuf.Bytes(),
		"garbage":    []byte("nope"),
		"too wide":   clientJPEG(t, 3000, 10),
		"too many B": append(clientJPEG(t, 10, 10), make([]byte, MaxClientThumbnailBytes)...),
	} {
		t.Run(name, func(t *testing.T) {
			err := store(t, StoreClientThumbnailParams{
				Queries: dbtest.NewDB(t).Queries, RelPath: "clip.mov", IsVideo: true,
				Reader: bytes.NewReader(body),
			})
			if !errors.Is(err, ErrInvalidThumbnail) {
				t.Fatalf("want ErrInvalidThumbnail, got %v", err)
			}
		})
	}
}

func TestNeedsClientRender(t *testing.T) {
	for name, want := range map[string]bool{
		"clip.mp4": true, "clip.MOV": true, "IMG.HEIC": true, "a.heif": true,
		"a.jpg": false, "a.png": false, "scan.dng": false, "notes.txt": false,
	} {
		if got := NeedsClientRender(name); got != want {
			t.Errorf("NeedsClientRender(%q) = %v, want %v", name, got, want)
		}
	}
}

package thumbnailutil

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

// sourceJPEG returns the bytes of a small solid-color JPEG to thumbnail.
func sourceJPEG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 64, 32))
	for y := 0; y < 32; y++ {
		for x := 0; x < 64; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 4), G: uint8(y * 8), B: 128, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatalf("encode source jpeg: %v", err)
	}
	return buf.Bytes()
}

func TestGenerateFromReaderWritesDecodableCacheEntry(t *testing.T) {
	cachedPath := filepath.Join(t.TempDir(), "entry")

	result, err := GenerateFromReader(GenerateFromReaderParams{
		Reader:     bytes.NewReader(sourceJPEG(t)),
		Ext:        ".jpg",
		Width:      16,
		Height:     16,
		CachedPath: cachedPath,
	})
	if err != nil {
		t.Fatalf("GenerateFromReader: %v", err)
	}
	if result.CachedModTime.IsZero() {
		t.Error("CachedModTime should be the committed entry's mod time, got zero")
	}

	f, err := os.Open(cachedPath)
	if err != nil {
		t.Fatalf("cache entry not committed: %v", err)
	}
	defer f.Close()
	cfg, format, err := image.DecodeConfig(f)
	if err != nil {
		t.Fatalf("cache entry is not a decodable image: %v", err)
	}
	if format != "jpeg" {
		t.Errorf("cache entry format = %q, want jpeg", format)
	}
	if cfg.Width != 16 || cfg.Height != 16 {
		t.Errorf("cache entry is %dx%d, want 16x16", cfg.Width, cfg.Height)
	}

	// The temporary file the entry was committed through must not survive.
	if leftovers, _ := filepath.Glob(cachedPath + ".*.tmp"); len(leftovers) != 0 {
		t.Errorf("temporary cache file was left behind: %v", leftovers)
	}
}

func TestGenerateFromReaderRejectsUndecodableSource(t *testing.T) {
	cachedPath := filepath.Join(t.TempDir(), "entry")

	_, err := GenerateFromReader(GenerateFromReaderParams{
		Reader:     bytes.NewReader([]byte("not an image")),
		Ext:        ".jpg",
		Width:      16,
		Height:     16,
		CachedPath: cachedPath,
	})
	if !errors.Is(err, ErrUnsupportedSource) {
		t.Fatalf("error = %v, want ErrUnsupportedSource so callers can fall through", err)
	}
	if _, statErr := os.Stat(cachedPath); !os.IsNotExist(statErr) {
		t.Errorf("a failed generation must not leave a cache entry behind: %v", statErr)
	}
}

// photoRow reads the one photo_hashes row a test expects.
func photoRow(t *testing.T, q *db.Queries) db.ListNearDuplicatesRow {
	t.Helper()
	rows, err := q.ListNearDuplicates(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("want one photo_hashes row, got %+v", rows)
	}
	return rows[0]
}

// TestGenerateFromReaderStoresPhotoHashes: the VFS path, which internal-drive
// photos take, used to store no hash at all, so duplicate detection found
// nothing (#1666).
func TestGenerateFromReaderStoresPhotoHashes(t *testing.T) {
	data := sourceJPEG(t)
	source := filepath.Join(t.TempDir(), "a.jpg")
	if err := os.WriteFile(source, data, 0o600); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(source)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	database := dbtest.NewDB(t)

	if _, err := GenerateFromReader(GenerateFromReaderParams{
		Queries: database.Queries, RelPath: "/trip/a.jpg", Reader: f, Ext: ".jpg",
		Width: 16, Height: 16, CachedPath: filepath.Join(t.TempDir(), "entry"),
	}); err != nil {
		t.Fatalf("GenerateFromReader: %v", err)
	}

	row := photoRow(t, database.Queries)
	sum := sha256.Sum256(data)
	if row.RelPath != "trip/a.jpg" || row.ContentHash.String != hex.EncodeToString(sum[:]) {
		t.Fatalf("row = %+v, want trip/a.jpg keyed with the file's SHA-256", row)
	}
	wantDHash, err := photoutil.DHashFile(source)
	if err != nil {
		t.Fatal(err)
	}
	if row.Dhash.String != wantDHash {
		t.Errorf("dhash = %q, want the whole-image hash %q", row.Dhash.String, wantDHash)
	}
}

// TestGenerateStoresTheSameHashesAtEveryTier: the dHash used to come from the
// cropped thumbnail of whichever tier rendered last.
func TestGenerateStoresTheSameHashesAtEveryTier(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	source := filepath.Join(t.TempDir(), "a.jpg")
	if err := os.WriteFile(source, sourceJPEG(t), 0o600); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	var first db.ListNearDuplicatesRow
	for i, size := range []Size{SizeSm, SizeMd, SizeLg} {
		w, h := Dimensions(size)
		if _, err := Generate(GenerateParams{
			Ctx: context.Background(), Queries: database.Queries, RelPath: "a.jpg",
			SourcePath: source, Ext: ".jpg", Width: w, Height: h,
			CachedPath: filepath.Join(t.TempDir(), string(size)),
		}); err != nil {
			t.Fatalf("Generate %s: %v", size, err)
		}
		row := photoRow(t, database.Queries)
		if !row.Dhash.Valid || !row.ContentHash.Valid {
			t.Fatalf("%s: want both hashes, got %+v", size, row)
		}
		if i == 0 {
			first = row
		} else if row.Dhash != first.Dhash || row.ContentHash != first.ContentHash {
			t.Errorf("%s: hashes %+v differ from the sm tier's %+v", size, row, first)
		}
	}
}

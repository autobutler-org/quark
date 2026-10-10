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
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// videoFixtures is the namespace of videoutil's tiny synthetic clips, 128x72.
func videoFixtures(t *testing.T) vfs.VFS {
	t.Helper()
	fsys, err := vfs.NewLocalVFS(filepath.Join("..", "videoutil", "testdata"), vfs.FilesNamespace(""))
	if err != nil {
		t.Fatal(err)
	}
	return fsys
}

// TestGenerateRendersAV1AndVP8Video: a video thumbnail used to need ffmpeg
// whatever the codec. These two the device decodes itself (#2865).
func TestGenerateRendersAV1AndVP8Video(t *testing.T) {
	// Nothing on PATH, so no external process can have rendered it.
	t.Setenv("PATH", t.TempDir())
	for _, name := range []string{"av1-opus.webm", "vp8-vorbis.webm"} {
		cachedPath := filepath.Join(t.TempDir(), "entry")
		if _, err := Generate(GenerateParams{
			Ctx: context.Background(), FS: videoFixtures(t), RelPath: name, Ext: ".webm", IsVideo: true,
			Width: 96, Height: 96, CachedPath: cachedPath,
		}); err != nil {
			t.Errorf("Generate %s: %v", name, err)
			continue
		}
		f, err := os.Open(cachedPath)
		if err != nil {
			t.Fatalf("%s: cache entry not committed: %v", name, err)
		}
		cfg, format, err := image.DecodeConfig(f)
		f.Close()
		if err != nil {
			t.Fatalf("%s: cache entry is not a decodable image: %v", name, err)
		}
		if format != "jpeg" || cfg.Width != 96 || cfg.Height != 96 {
			t.Errorf("%s: cache entry is a %dx%d %s, want a 96x96 jpeg", name, cfg.Width, cfg.Height, format)
		}
	}
}

// TestGenerateReportsAVideoCodecWithNoDecoder: H.264 and HEVC are a client's
// to render, so they fail with an error the caller can tell from a broken file.
func TestGenerateReportsAVideoCodecWithNoDecoder(t *testing.T) {
	for _, name := range []string{"h264-gop12.mp4", "hevc-aac-copy.mkv"} {
		cachedPath := filepath.Join(t.TempDir(), "entry")
		_, err := Generate(GenerateParams{
			Ctx: context.Background(), FS: videoFixtures(t), RelPath: name, Ext: filepath.Ext(name), IsVideo: true,
			Width: 96, Height: 96, CachedPath: cachedPath,
		})
		if !errors.Is(err, videoutil.ErrNoDecoder) {
			t.Errorf("Generate %s = %v, want videoutil.ErrNoDecoder", name, err)
		}
		if _, statErr := os.Stat(cachedPath); !os.IsNotExist(statErr) {
			t.Errorf("%s: a failed generation must not leave a cache entry behind: %v", name, statErr)
		}
	}
}

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
	fsys := memFS(t, map[string][]byte{"a.jpg": sourceJPEG(t)})
	database := dbtest.NewDB(t)
	var first db.ListNearDuplicatesRow
	for i, size := range []Size{SizeSm, SizeMd, SizeLg} {
		w, h := Dimensions(size)
		if _, err := Generate(GenerateParams{
			Ctx: context.Background(), Queries: database.Queries, FS: fsys, RelPath: "a.jpg",
			Ext: ".jpg", Width: w, Height: h,
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

// memFS is a MemVFS holding files.
func memFS(t *testing.T, files map[string][]byte) vfs.VFS {
	t.Helper()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for p, data := range files {
		if err := fsys.Write(context.Background(), p, bytes.NewReader(data), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	return fsys
}

// TestGenerateReadsThroughTheNamespace: Generate used to take a disk path, so
// only a file the caller had resolved to the host could get a thumbnail. An
// image now renders from any namespace, and a RAW or video with no host path
// behind it is not found rather than read off the internal drive.
func TestGenerateReadsThroughTheNamespace(t *testing.T) {
	fsys := memFS(t, map[string][]byte{"a.jpg": sourceJPEG(t), "b.cr2": []byte("raw"), "c.mp4": []byte("video")})
	database := dbtest.NewDB(t)
	cached := filepath.Join(t.TempDir(), "entry")
	if _, err := Generate(GenerateParams{
		Ctx: context.Background(), Queries: database.Queries, FS: fsys, Serial: "USB-1", RelPath: "a.jpg",
		Ext: ".jpg", Width: 16, Height: 16, CachedPath: cached,
	}); err != nil {
		t.Fatalf("Generate: %v", err)
	}
	if f, err := os.Open(cached); err != nil {
		t.Fatalf("no cache entry: %v", err)
	} else {
		f.Close()
	}
	if row := photoRow(t, database.Queries); row.DeviceSerial != "USB-1" || !row.Dhash.Valid || !row.ContentHash.Valid {
		t.Errorf("row = %+v, want both hashes on USB-1", row)
	}

	for _, tc := range []struct {
		relPath string
		isVideo bool
	}{{"b.cr2", false}, {"c.mp4", true}, {"gone.jpg", false}} {
		_, err := Generate(GenerateParams{
			Ctx: context.Background(), FS: fsys, RelPath: tc.relPath, IsVideo: tc.isVideo,
			Width: 16, Height: 16, CachedPath: filepath.Join(t.TempDir(), "entry"),
		})
		if !errors.Is(err, vfs.ErrNotFound) {
			t.Errorf("%s: err = %v, want vfs.ErrNotFound", tc.relPath, err)
		}
	}
}

// An archive entry cannot seek, so it is held in memory — but only up to the
// cap. A larger one is refused, not truncated into a half-decoded image.
func TestBufferSourceRefusesASourceOverTheCap(t *testing.T) {
	rs, err := BufferSource(bytes.NewReader(sourceJPEG(t)))
	if err != nil {
		t.Fatalf("BufferSource: %v", err)
	}
	if _, err := rs.Seek(0, 0); err != nil {
		t.Fatalf("buffered source must seek: %v", err)
	}

	over := io.LimitReader(zeroReader{}, MaxBufferedSourceBytes+1)
	if _, err := BufferSource(over); !errors.Is(err, ErrUnsupportedSource) {
		t.Fatalf("BufferSource over the cap: got %v, want ErrUnsupportedSource", err)
	}
}

// zeroReader is an endless source of zero bytes.
type zeroReader struct{}

func (zeroReader) Read(p []byte) (int, error) {
	clear(p)
	return len(p), nil
}

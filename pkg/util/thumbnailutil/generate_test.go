package thumbnailutil

import (
	"bytes"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"
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

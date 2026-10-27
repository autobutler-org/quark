package v0_thumbnails_test

import (
	"bytes"
	"image"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"
)

// GET ?size=xl answers with the whole photo fitted within 1280px, not a
// cropped square, and a repeat request is served from the cached entry.
func TestGetThumbnailXlIsTheUncroppedPhoto(t *testing.T) {
	engine, dir, _ := newThumbnailEngine(t, true)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 2000, 1000)), nil); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "wide.jpg"), buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}

	w := get(engine, "/api/v0/thumbnails/wide.jpg?size=xl")
	if w.Code != 200 {
		t.Fatalf("got %d: %s", w.Code, w.Body.String())
	}
	etag := w.Header().Get("ETag")
	cfg, err := jpeg.DecodeConfig(w.Body)
	if err != nil {
		t.Fatalf("body is not a JPEG: %v", err)
	}
	if cfg.Width != 1280 || cfg.Height != 640 {
		t.Errorf("xl of a 2000x1000 photo is %dx%d, want 1280x640", cfg.Width, cfg.Height)
	}

	again := get(engine, "/api/v0/thumbnails/wide.jpg?size=xl")
	if again.Header().Get("ETag") != etag {
		t.Errorf("a second xl request regenerated the entry: ETag %q, then %q", etag, again.Header().Get("ETag"))
	}
}

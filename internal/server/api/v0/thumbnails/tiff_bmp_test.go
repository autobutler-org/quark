package v0_thumbnails_test

import (
	"bytes"
	"image"
	"image/color"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/image/bmp"
	"golang.org/x/image/tiff"
)

// A TIFF and a BMP each get a thumbnail, now that Files asks for one (#4199).
func TestGetThumbnail_TIFFAndBMP(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 40, 30))
	src.Set(5, 5, color.RGBA{G: 255, A: 255})
	encoders := map[string]func(*bytes.Buffer) error{
		"scan.tif":  func(b *bytes.Buffer) error { return tiff.Encode(b, src, &tiff.Options{Compression: tiff.Deflate}) },
		"scan.tiff": func(b *bytes.Buffer) error { return tiff.Encode(b, src, nil) },
		"paint.bmp": func(b *bytes.Buffer) error { return bmp.Encode(b, src) },
	}
	for name, encode := range encoders {
		t.Run(name, func(t *testing.T) {
			engine, dir, _ := newThumbnailEngine(t, true)
			var buf bytes.Buffer
			if err := encode(&buf); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, name), buf.Bytes(), 0o644); err != nil {
				t.Fatal(err)
			}
			w := get(engine, "/api/v0/thumbnails/"+name+"?size=sm")
			if w.Code != 200 {
				t.Fatalf("got %d: %s", w.Code, w.Body.String())
			}
			if _, _, err := image.Decode(w.Body); err != nil {
				t.Errorf("body is not an image: %v", err)
			}
		})
	}
}

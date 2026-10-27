package photoutil

import (
	"bytes"
	"testing"
)

// A fitted rendition keeps the photo whole: its long edge lands on the box
// and its aspect ratio is the source's, never a center-cropped square.
func TestResizeFitKeepsAspectAndCapsLongEdge(t *testing.T) {
	for _, tt := range []struct {
		name         string
		srcW, srcH   int
		wantW, wantH int
	}{
		{"landscape", 4000, 3000, 1280, 960},
		{"portrait", 3000, 4000, 960, 1280},
		{"square", 2000, 2000, 1280, 1280},
		{"panorama", 6400, 800, 1280, 160},
	} {
		got, err := resizeTo(gradientImage(tt.srcW, tt.srcH), 1280, 1280, ResizeFit)
		if err != nil {
			t.Fatalf("%s: resizeTo: %v", tt.name, err)
		}
		if b := got.Bounds(); b.Dx() != tt.wantW || b.Dy() != tt.wantH {
			t.Errorf("%s: %dx%d fitted into 1280 is %dx%d, want %dx%d",
				tt.name, tt.srcW, tt.srcH, b.Dx(), b.Dy(), tt.wantW, tt.wantH)
		}
	}
}

// A photo already smaller than the box is served at its own size.
func TestResizeFitNeverUpscales(t *testing.T) {
	got, err := resizeTo(gradientImage(300, 200), 1280, 1280, ResizeFit)
	if err != nil {
		t.Fatalf("resizeTo: %v", err)
	}
	if b := got.Bounds(); b.Dx() != 300 || b.Dy() != 200 {
		t.Errorf("a 300x200 photo fitted into 1280 is %dx%d, want it untouched", b.Dx(), b.Dy())
	}
}

// The crop tiers are unchanged: an exact square whatever the source shape.
func TestResizeCropIsSquare(t *testing.T) {
	got, err := resizeTo(gradientImage(400, 100), 96, 96, ResizeCrop)
	if err != nil {
		t.Fatalf("resizeTo: %v", err)
	}
	if b := got.Bounds(); b.Dx() != 96 || b.Dy() != 96 {
		t.Errorf("cropped tier is %dx%d, want 96x96", b.Dx(), b.Dy())
	}
}

// A fitted rendition of an EXIF-rotated photo is upright: the 40x20 source
// tagged orientation 6 comes out 20x40, still uncropped and not upscaled.
func TestGenerateThumbnailFromReaderFitIsUpright(t *testing.T) {
	result, err := GenerateThumbnailFromReader(bytes.NewReader(exifOrientedJPEG(t, 6)), ".jpg", 1280, 1280, ResizeFit)
	if err != nil {
		t.Fatalf("GenerateThumbnailFromReader: %v", err)
	}
	if b := result.Thumbnail.Bounds(); b.Dx() != 20 || b.Dy() != 40 {
		t.Fatalf("fitted rendition is %dx%d, want 20x40", b.Dx(), b.Dy())
	}
	if !isRedder(t, result.Thumbnail, 10, 5) || isRedder(t, result.Thumbnail, 10, 35) {
		t.Error("fitted rendition should be the upright image, red on top")
	}
}

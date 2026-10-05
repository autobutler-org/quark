package photoutil

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"image/jpeg"
	"runtime"
	"testing"

	"github.com/bep/imagemeta"
)

// exifOrientedJPEG returns a 40x20 landscape JPEG — red left half, blue right
// half — carrying an EXIF orientation tag. The fixture is built here rather
// than committed because it is a few hundred bytes of header around a JPEG the
// stdlib can encode, and the tag is the only part that matters.
//
// Orientation 6 means "rotate 90° clockwise to display", so a correctly
// oriented decode is 20x40 portrait with the red half on top.
func exifOrientedJPEG(t *testing.T, orientation uint16) []byte {
	t.Helper()

	img := image.NewRGBA(image.Rect(0, 0, 40, 20))
	for y := range 20 {
		for x := range 40 {
			if x < 20 {
				img.Set(x, y, color.RGBA{R: 255, A: 255})
			} else {
				img.Set(x, y, color.RGBA{B: 255, A: 255})
			}
		}
	}
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, img, nil); err != nil {
		t.Fatalf("encode fixture: %v", err)
	}

	// A little-endian TIFF header with a single-entry IFD0 holding
	// Orientation (tag 0x0112, type SHORT).
	var tiff bytes.Buffer
	tiff.WriteString("II")
	_ = binary.Write(&tiff, binary.LittleEndian, uint16(42))
	_ = binary.Write(&tiff, binary.LittleEndian, uint32(8))
	_ = binary.Write(&tiff, binary.LittleEndian, uint16(1))
	_ = binary.Write(&tiff, binary.LittleEndian, uint16(0x0112))
	_ = binary.Write(&tiff, binary.LittleEndian, uint16(3))
	_ = binary.Write(&tiff, binary.LittleEndian, uint32(1))
	_ = binary.Write(&tiff, binary.LittleEndian, orientation)
	_ = binary.Write(&tiff, binary.LittleEndian, uint16(0))
	_ = binary.Write(&tiff, binary.LittleEndian, uint32(0))

	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	app1 := binary.BigEndian.AppendUint16([]byte{0xFF, 0xE1}, uint16(len(payload)+2))
	app1 = append(app1, payload...)

	// Splice the APP1 segment in right after the SOI marker.
	body := encoded.Bytes()
	out := append([]byte{}, body[:2]...)
	out = append(out, app1...)
	return append(out, body[2:]...)
}

// isRedder reports whether the pixel at (x, y) reads red rather than blue.
// JPEG is lossy at this size, so the test compares channels instead of
// matching an exact color.
func isRedder(t *testing.T, img image.Image, x, y int) bool {
	t.Helper()
	r, _, b, _ := img.At(x, y).RGBA()
	return r > b
}

// The half of #1798 that must keep working: a JPEG decoder ignores the
// orientation tag, so the thumbnail pipeline has to apply it.
func TestOrientDecodedImageAppliesExifOrientation(t *testing.T) {
	data := exifOrientedJPEG(t, 6)
	rs := bytes.NewReader(data)
	decoded, err := jpeg.Decode(rs)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	got := applyExifOrientation(decoded, sourceOrientation(rs, imagemeta.JPEG))

	bounds := got.Bounds()
	if bounds.Dx() != 20 || bounds.Dy() != 40 {
		t.Fatalf("orientation 6 should turn 40x20 into 20x40, got %dx%d", bounds.Dx(), bounds.Dy())
	}
	if !isRedder(t, got, bounds.Min.X+10, bounds.Min.Y+5) {
		t.Error("top of the upright image should be the red half")
	}
	if isRedder(t, got, bounds.Min.X+10, bounds.Min.Y+35) {
		t.Error("bottom of the upright image should be the blue half")
	}
}

// seekCounter reports whether sourceOrientation went looking for an
// orientation tag at all.
type seekCounter struct {
	*bytes.Reader
	seeks int
}

func (s *seekCounter) Seek(offset int64, whence int) (int64, error) {
	s.seeks++
	return s.Reader.Seek(offset, whence)
}

// The half that regressed in #1798: libheif already applies the container's
// rotation during decode, so applying the EXIF tag again turns an upright
// iPhone portrait photo sideways. A HEIF source must read as upright, and
// the tag must not even be read — an assertion a fabricated JPEG fixture can
// carry, where comparing pixels could not.
func TestOrientDecodedImageSkipsFormatsTheDecoderAlreadyOriented(t *testing.T) {
	data := exifOrientedJPEG(t, 6)
	src := &seekCounter{Reader: bytes.NewReader(data)}
	if _, err := jpeg.Decode(src); err != nil {
		t.Fatalf("decode: %v", err)
	}
	src.seeks = 0

	if got := sourceOrientation(src, imagemeta.HEIF); got != 1 {
		t.Errorf("a HEIF source is already upright, so its orientation is 1, got %d", got)
	}
	if src.seeks != 0 {
		t.Errorf("a HEIF source's orientation tag must not be consulted, saw %d seeks", src.seeks)
	}
}

// The whole VFS thumbnail path, end to end: a portrait source has to come out
// of the pipeline portrait.
func TestGenerateThumbnailFromReaderRespectsExifOrientation(t *testing.T) {
	data := exifOrientedJPEG(t, 6)

	result, err := GenerateThumbnailFromReader(bytes.NewReader(data), ".jpg", 10, 20)
	if err != nil {
		t.Fatalf("GenerateThumbnailFromReader: %v", err)
	}

	bounds := result.Thumbnail.Bounds()
	if !isRedder(t, result.Thumbnail, bounds.Min.X+5, bounds.Min.Y+2) {
		t.Error("thumbnail top should be the red half of the upright image")
	}
	if isRedder(t, result.Thumbnail, bounds.Min.X+5, bounds.Max.Y-3) {
		t.Error("thumbnail bottom should be the blue half of the upright image")
	}
}

// gradientImage is a w × h RGBA whose every pixel differs from its
// neighbors, so a transform that lands one pixel in the wrong place shows.
func gradientImage(w, h int) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			img.Set(x, y, color.RGBA{R: uint8(x * 255 / w), G: uint8(y * 255 / h), B: uint8((x*7 + y*13) % 256), A: 255})
		}
	}
	return img
}

// atOrigin copies img onto an image whose bounds start at (0, 0).
func atOrigin(img image.Image) *image.RGBA {
	b := img.Bounds()
	out := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	for y := range b.Dy() {
		for x := range b.Dx() {
			out.Set(x, y, img.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return out
}

// maxChannelDiff is the largest 8-bit channel difference between two
// same-sized images, compared from their own origins.
func maxChannelDiff(t *testing.T, a, b image.Image) int {
	t.Helper()
	ab, bb := a.Bounds(), b.Bounds()
	if ab.Dx() != bb.Dx() || ab.Dy() != bb.Dy() {
		t.Fatalf("sizes differ: %dx%d vs %dx%d", ab.Dx(), ab.Dy(), bb.Dx(), bb.Dy())
	}
	worst := 0
	for y := range ab.Dy() {
		for x := range ab.Dx() {
			r1, g1, b1, a1 := a.At(ab.Min.X+x, ab.Min.Y+y).RGBA()
			r2, g2, b2, a2 := b.At(bb.Min.X+x, bb.Min.Y+y).RGBA()
			for _, d := range []int{int(r1>>8) - int(r2>>8), int(g1>>8) - int(g2>>8), int(b1>>8) - int(b2>>8), int(a1>>8) - int(a2>>8)} {
				worst = max(worst, d, -d)
			}
		}
	}
	return worst
}

// cropToFit hands back a SubImage whose bounds do not start at the origin.
// Rotating one used to write past the new image's bounds and leave a
// transparent band, which is what rotating after the crop would hit on
// every thumbnail.
func TestOrientationTransformsHandleSubImages(t *testing.T) {
	sub := gradientImage(40, 20).SubImage(image.Rect(10, 3, 30, 17))
	for orientation := 1; orientation <= 8; orientation++ {
		got := applyExifOrientation(sub, orientation)
		want := applyExifOrientation(atOrigin(sub), orientation)
		if d := maxChannelDiff(t, got, want); d != 0 {
			t.Errorf("orientation %d: a sub-image differs from the same pixels at the origin by %d", orientation, d)
		}
	}
	for quarters := int64(0); quarters < 4; quarters++ {
		if d := maxChannelDiff(t, ApplyRotation(sub, quarters), ApplyRotation(atOrigin(sub), quarters)); d != 0 {
			t.Errorf("rotation %d: a sub-image differs from the same pixels at the origin by %d", quarters, d)
		}
	}
}

// Rotating the thumbnail instead of the source must give the thumbnail the
// old order did. The sizes keep both crops' margins even, so neither order
// rounds its center differently.
func TestUprightThumbnailMatchesRotatingFirst(t *testing.T) {
	src := gradientImage(256, 128)
	for orientation := 1; orientation <= 8; orientation++ {
		for _, size := range [][2]uint{{32, 32}, {32, 16}, {16, 32}} {
			got, err := uprightThumbnail(src, orientation, size[0], size[1])
			if err != nil {
				t.Fatalf("orientation %d %v: %v", orientation, size, err)
			}
			want, _, err := cropToFit(applyExifOrientation(src, orientation), size[0], size[1])
			if err != nil {
				t.Fatal(err)
			}
			if b := got.Bounds(); b.Dx() != int(size[0]) || b.Dy() != int(size[1]) {
				t.Fatalf("orientation %d: thumbnail is %dx%d, want %dx%d", orientation, b.Dx(), b.Dy(), size[0], size[1])
			}
			// Lanczos run over the rows first rounds a little differently
			// from Lanczos run over the columns first.
			if d := maxChannelDiff(t, got, want); d > 3 {
				t.Errorf("orientation %d %v: differs from rotate-then-resize by %d", orientation, size, d)
			}
		}
	}
}

// The point of the order (#2762): the full-size source is never rotated, so
// the thumbnail costs about what one of an upright photo does rather than a second
// full-size RGBA.
func TestUprightThumbnailDoesNotCopyTheSource(t *testing.T) {
	src := gradientImage(2000, 1000)
	fullCopy := uint64(len(src.Pix))

	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	if _, err := uprightThumbnail(src, 6, 64, 64); err != nil {
		t.Fatal(err)
	}
	runtime.ReadMemStats(&after)

	if allocated := after.TotalAlloc - before.TotalAlloc; allocated >= fullCopy/2 {
		t.Errorf("a thumbnail of a 6-oriented source allocated %d bytes; a full-size copy is %d", allocated, fullCopy)
	}
}

// The hash is of the upright image, and every stored hash was taken that way,
// so hashing the source in place must give exactly the same bits.
func TestUprightDHashMatchesRotatedImage(t *testing.T) {
	for _, size := range [][2]int{{97, 61}, {61, 97}, {5, 3}, {9, 40}} {
		src := gradientImage(size[0], size[1])
		for orientation := 1; orientation <= 8; orientation++ {
			got := uprightDHash(src, orientation)
			want := DHashHex(applyExifOrientation(src, orientation))
			if got != want {
				t.Errorf("%v orientation %d: dHash %s, want %s", size, orientation, got, want)
			}
		}
	}
}

package photoutil

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"image/jpeg"
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

	got := orientDecodedImage(decoded, rs, imagemeta.JPEG)

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

// seekCounter reports whether orientDecodedImage went looking for an
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
// iPhone portrait photo sideways. A HEIF source must come back untouched, and
// the tag must not even be read — an assertion a fabricated JPEG fixture can
// carry, where comparing pixels could not.
func TestOrientDecodedImageSkipsFormatsTheDecoderAlreadyOriented(t *testing.T) {
	data := exifOrientedJPEG(t, 6)
	src := &seekCounter{Reader: bytes.NewReader(data)}
	decoded, err := jpeg.Decode(src)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	src.seeks = 0

	got := orientDecodedImage(decoded, src, imagemeta.HEIF)

	if got != decoded {
		t.Errorf("a HEIF source is already upright and must be returned untouched, got %v", got.Bounds())
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

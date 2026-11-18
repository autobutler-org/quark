// cspell:words thumbversionutil

package v0_thumbnails_test

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/thumbversionutil"
)

// orientedJPEG is a w x h JPEG, red on its left half and blue on its right,
// tagged with EXIF orientation 6: displayed upright it is h x w, red on top.
func orientedJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			c := color.RGBA{B: 255, A: 255}
			if x < w/2 {
				c = color.RGBA{R: 255, A: 255}
			}
			img.Set(x, y, c)
		}
	}
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, img, nil); err != nil {
		t.Fatal(err)
	}
	// A little-endian TIFF header whose one IFD0 entry is Orientation = 6.
	var tiff bytes.Buffer
	tiff.WriteString("II")
	for _, v := range []any{uint16(42), uint32(8), uint16(1), uint16(0x0112), uint16(3), uint32(1), uint16(6), uint16(0), uint32(0)} {
		_ = binary.Write(&tiff, binary.LittleEndian, v)
	}
	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	app1 := binary.BigEndian.AppendUint16([]byte{0xFF, 0xE1}, uint16(len(payload)+2))
	body := encoded.Bytes()
	out := append([]byte{}, body[:2]...)
	out = append(out, append(app1, payload...)...)
	return append(out, body[2:]...)
}

// TestGetThumbnail_Preview: size=preview is the whole photo, uncropped and
// upright, its long edge scaled down to 2048, served as a JPEG; a photo
// already smaller is not scaled up, and a PNG's preview is a JPEG too. The
// user's rotation is left to the viewer, as it is for the original, and a
// versioned preview URL is immutable like the grid tiers (#4220).
func TestGetThumbnail_Preview(t *testing.T) {
	engine, dir, database := newThumbnailEngine(t, true)
	if err := database.Queries.UpsertPhotoRotation(context.Background(), db.UpsertPhotoRotationParams{
		RelPath: "big.jpg", RotationQuarters: 1,
	}); err != nil {
		t.Fatal(err)
	}
	big := filepath.Join(dir, "big.jpg")
	if err := os.WriteFile(big, orientedJPEG(t, 3000, 1000), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "red.png"), pngBytes(t), 0o644); err != nil {
		t.Fatal(err)
	}

	decode := func(path string) image.Image {
		t.Helper()
		w := get(engine, path)
		if w.Code != http.StatusOK {
			t.Fatalf("GET %s: got %d: %s", path, w.Code, w.Body.String())
		}
		if ct := w.Header().Get("Content-Type"); ct != "image/jpeg" {
			t.Errorf("GET %s: Content-Type = %q, want image/jpeg", path, ct)
		}
		img, err := jpeg.Decode(w.Body)
		if err != nil {
			t.Fatalf("GET %s: body is not a JPEG: %v", path, err)
		}
		return img
	}

	preview := decode("/api/v0/thumbnails/big.jpg?size=preview")
	b := preview.Bounds()
	if b.Dy() != 2048 || b.Dx() < 682 || b.Dx() > 683 {
		t.Fatalf("preview of an EXIF-rotated 3000x1000 photo the user turned a quarter is %dx%d, want about 683x2048: EXIF applied, the user's rotation not", b.Dx(), b.Dy())
	}
	red := func(x, y int) bool { r, _, bl, _ := preview.At(x, y).RGBA(); return r > bl }
	if !red(b.Dx()/2, b.Dy()/8) || red(b.Dx()/2, b.Dy()*7/8) {
		t.Error("preview is not upright: want red on top and blue below")
	}

	if small := decode("/api/v0/thumbnails/red.png?size=preview").Bounds(); small.Dx() != 32 || small.Dy() != 32 {
		t.Errorf("preview of a 32x32 PNG is %dx%d, want it left at 32x32", small.Dx(), small.Dy())
	}

	// The grid tier of the same photo is still its cropped square.
	if sq := decode("/api/v0/thumbnails/big.jpg?size=lg").Bounds(); sq.Dx() != 400 || sq.Dy() != 400 {
		t.Errorf("lg tier is %dx%d, want 400x400", sq.Dx(), sq.Dy())
	}

	info, err := os.Stat(big)
	if err != nil {
		t.Fatal(err)
	}
	w := get(engine, fmt.Sprintf("/api/v0/thumbnails/big.jpg?size=preview&v=%d.1", info.ModTime().Unix()))
	if got := w.Header().Get("Cache-Control"); got != thumbversionutil.Immutable {
		t.Errorf("versioned preview: Cache-Control = %q, want %q", got, thumbversionutil.Immutable)
	}
}

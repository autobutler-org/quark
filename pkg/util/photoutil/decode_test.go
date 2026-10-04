package photoutil

// cspell:ignore IDAT IEND

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"testing"
)

// oversizePNG is a few hundred bytes that claim to be a width × height 8-bit
// grayscale PNG: a valid IHDR, then one row of image data. That is all a
// decompression bomb needs — the decoder sizes its pixel buffer from the
// header before it reads a byte of data.
func oversizePNG(t *testing.T, width, height uint32) []byte {
	t.Helper()
	var out bytes.Buffer
	out.WriteString("\x89PNG\r\n\x1a\n")
	chunk := func(kind string, data []byte) {
		_ = binary.Write(&out, binary.BigEndian, uint32(len(data)))
		body := append([]byte(kind), data...)
		out.Write(body)
		_ = binary.Write(&out, binary.BigEndian, crc32.ChecksumIEEE(body))
	}
	ihdr := binary.BigEndian.AppendUint32(nil, width)
	ihdr = binary.BigEndian.AppendUint32(ihdr, height)
	ihdr = append(ihdr, 8, 0, 0, 0, 0) // 8-bit, grayscale, deflate, no filter, no interlace
	chunk("IHDR", ihdr)

	var pixelData bytes.Buffer
	zw := zlib.NewWriter(&pixelData)
	_, _ = zw.Write(make([]byte, 1+width)) // one filter byte and one row
	_ = zw.Close()
	chunk("IDAT", pixelData.Bytes())
	chunk("IEND", nil)
	return out.Bytes()
}

// 9000 × 9000 is 81 MP, over the cap, and only 81 MiB if the cap fails to
// stop it — enough to tell, not enough to hurt the test run.
const bombSide = 9000

func TestDecodeImage_RefusesPixelsOverTheCap(t *testing.T) {
	if bombSide*bombSide <= MaxDecodePixels {
		t.Fatalf("fixture %d px must exceed MaxDecodePixels %d", bombSide*bombSide, MaxDecodePixels)
	}
	data := oversizePNG(t, bombSide, bombSide)

	for name, r := range map[string]io.Reader{
		"seekable": bytes.NewReader(data),
		"stream":   io.MultiReader(bytes.NewReader(data)),
	} {
		t.Run(name, func(t *testing.T) {
			_, _, err := DecodeImage(r)
			if !errors.Is(err, ErrImageTooLarge) {
				t.Fatalf("DecodeImage = %v, want ErrImageTooLarge", err)
			}
		})
	}
}

func TestDecodeImage_DecodesUnderTheCap(t *testing.T) {
	src := image.NewGray(image.Rect(0, 0, 30, 20))
	src.SetGray(3, 4, color.Gray{Y: 200})
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, src); err != nil {
		t.Fatal(err)
	}

	for name, r := range map[string]io.Reader{
		"seekable": bytes.NewReader(encoded.Bytes()),
		"stream":   io.MultiReader(bytes.NewReader(encoded.Bytes())),
	} {
		t.Run(name, func(t *testing.T) {
			img, format, err := DecodeImage(r)
			if err != nil {
				t.Fatalf("DecodeImage: %v", err)
			}
			if format != "png" || img.Bounds().Dx() != 30 || img.Bounds().Dy() != 20 {
				t.Fatalf("got %s %v, want png 30x20", format, img.Bounds())
			}
			if g := color.GrayModel.Convert(img.At(3, 4)).(color.Gray).Y; g != 200 {
				t.Errorf("pixel (3,4) = %d, want 200: the header bytes must be replayed into the decode", g)
			}
		})
	}
}

// Every way into the thumbnail pipeline checks the cap before it decodes.
func TestThumbnailPaths_RefusePixelsOverTheCap(t *testing.T) {
	data := oversizePNG(t, bombSide, bombSide)
	path := filepath.Join(t.TempDir(), "bomb.png")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := GenerateThumbnailFromReader(bytes.NewReader(data), ".png", 64, 64); !errors.Is(err, ErrImageTooLarge) {
		t.Errorf("GenerateThumbnailFromReader = %v, want ErrImageTooLarge", err)
	}
	if _, err := GenerateThumbnail(GenerateThumbnailParams{FilePath: path, Width: 64, Height: 64}); !errors.Is(err, ErrImageTooLarge) {
		t.Errorf("GenerateThumbnail = %v, want ErrImageTooLarge", err)
	}
	if _, _, err := ImageToThumbnail(path, 64, 64); !errors.Is(err, ErrImageTooLarge) {
		t.Errorf("ImageToThumbnail = %v, want ErrImageTooLarge", err)
	}
	if _, err := DHashFile(path); !errors.Is(err, ErrImageTooLarge) {
		t.Errorf("DHashFile = %v, want ErrImageTooLarge", err)
	}
}

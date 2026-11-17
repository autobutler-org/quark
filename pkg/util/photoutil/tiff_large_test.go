package photoutil

// cspell:ignore IFDs PackBits dbit MPTIFF subifd thumbnailing CMYK

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"
	"testing"

	"golang.org/x/image/tiff"
)

// streamTestTIFF writes s, reads its layout, and streams IFD0 at no more
// than longSide.
func streamTestTIFF(t *testing.T, s testTIFF, longSide int64) image.Image {
	t.Helper()
	data := writeTestTIFF(t, s)
	r := bytes.NewReader(data)
	layout, err := readTIFFLayout(r, int64(len(data)))
	if err != nil {
		t.Fatalf("readTIFFLayout: %v", err)
	}
	img, err := decodeTIFFStreamed(r, layout.order, layout.dirs[0], longSide)
	if err != nil {
		t.Fatalf("decodeTIFFStreamed: %v", err)
	}
	return img
}

// pixelRGBA reads (x, y) of a streamed image as 8-bit samples, gray as one.
func pixelSamples(img image.Image, x, y int) []uint8 {
	switch img := img.(type) {
	case *image.Gray:
		return []uint8{img.GrayAt(x, y).Y}
	case *image.RGBA:
		i := img.PixOffset(x, y)
		return img.Pix[i : i+4]
	case *image.NRGBA:
		i := img.PixOffset(x, y)
		return img.Pix[i : i+4]
	}
	return nil
}

// wantSamples is what the streaming decoder should produce for (x, y) of s
// at full size: 8-bit samples, gray and gray+alpha widened to RGBA.
func wantSamples(s *testTIFF, x, y int) []uint8 {
	v := make([]uint8, s.samples)
	for c := range s.samples {
		v[c] = uint8(s.sample(x, y, c) >> (s.bits - 8))
		if c == 0 && s.photometric == tiffPhotometricWhiteIsZero {
			v[c] = 255 - v[c]
		}
	}
	switch s.samples {
	case 2:
		return []uint8{v[0], v[0], v[0], v[1]}
	case 3:
		return []uint8{v[0], v[1], v[2], 255}
	}
	return v
}

// Every encoding the streaming decoder supports reads back exactly at full
// size: strips and tiles, each compression, predictor 2, 8 and 16 bits,
// both byte orders, and gray, gray+alpha, RGB and RGBA.
func TestDecodeTIFFStreamed_Encodings(t *testing.T) {
	compressions := map[string]int{
		"none": tiffCompressionNone, "lzw": tiffCompressionLZW, "deflate": tiffCompressionDeflate,
		"deflate-old": tiffCompressionDeflateOld, "packbits": tiffCompressionPackBits,
	}
	orders := map[string]testByteOrder{"le": binary.LittleEndian, "be": binary.BigEndian}
	for cname, compression := range compressions {
		for oname, order := range orders {
			for _, bits := range []int{8, 16} {
				for _, predictor := range []int{1, 2} {
					for _, samples := range []int{1, 2, 3, 4} {
						for _, tiled := range []bool{false, true} {
							s := testTIFF{
								order: order, width: 37, height: 23, samples: samples, bits: bits,
								compression: compression, predictor: predictor, rowsPerStrip: 5,
							}
							if tiled {
								s.tileWidth, s.tileLength = 16, 16
							}
							if samples == 2 || samples == 4 {
								s.extraSample = 2
							}
							name := fmt.Sprintf("%s/%s/%dbit/pred%d/%dch/tiled=%v", cname, oname, bits, predictor, samples, tiled)
							t.Run(name, func(t *testing.T) {
								img := streamTestTIFF(t, s, 1000)
								if got := img.Bounds(); got != image.Rect(0, 0, 37, 23) {
									t.Fatalf("bounds %v", got)
								}
								s.defaults()
								for y := range 23 {
									for x := range 37 {
										if got, want := pixelSamples(img, x, y), wantSamples(&s, x, y); !bytes.Equal(got, want) {
											t.Fatalf("(%d, %d): got %v, want %v", x, y, got, want)
										}
									}
								}
							})
						}
					}
				}
			}
		}
	}
}

// The test encoder's LZW is the one TIFF readers expect: x/image's decoder
// reads it back, so the streamed results above are not one encoder agreeing
// with itself.
func TestTestLZWIsReadableByXImage(t *testing.T) {
	s := testTIFF{width: 300, height: 200, samples: 3, compression: tiffCompressionLZW, rowsPerStrip: 64}
	img, err := tiff.Decode(bytes.NewReader(writeTestTIFF(t, s)))
	if err != nil {
		t.Fatalf("x/image tiff.Decode: %v", err)
	}
	s.defaults()
	r, g, b, _ := img.At(299, 199).RGBA()
	if want := wantSamples(&s, 299, 199); uint8(r>>8) != want[0] || uint8(g>>8) != want[1] || uint8(b>>8) != want[2] {
		t.Errorf("x/image read (%d, %d, %d), want %v", r>>8, g>>8, b>>8, want)
	}
}

func TestDecodeTIFFStreamed_WhiteIsZeroAndAssociatedAlpha(t *testing.T) {
	gray := testTIFF{width: 9, height: 4, photometric: tiffPhotometricWhiteIsZero}
	img := streamTestTIFF(t, gray, 100)
	gray.defaults()
	if got, want := pixelSamples(img, 8, 3), wantSamples(&gray, 8, 3); !bytes.Equal(got, want) {
		t.Errorf("WhiteIsZero: got %v, want %v", got, want)
	}

	if _, ok := streamTestTIFF(t, testTIFF{width: 9, height: 4, samples: 4, extraSample: 1}, 100).(*image.RGBA); !ok {
		t.Error("associated alpha should decode to premultiplied RGBA")
	}
	if _, ok := streamTestTIFF(t, testTIFF{width: 9, height: 4, samples: 4, extraSample: 2}, 100).(*image.NRGBA); !ok {
		t.Error("unassociated alpha should decode to NRGBA")
	}
}

// Shrinking averages every source pixel into the one output pixel it maps
// to, for strips and for tiles, including at a ratio that does not divide.
func TestDecodeTIFFStreamed_BoxFilter(t *testing.T) {
	for _, tiled := range []bool{false, true} {
		s := testTIFF{width: 101, height: 47, samples: 3, bits: 16, compression: tiffCompressionDeflate, rowsPerStrip: 3}
		if tiled {
			s.tileWidth, s.tileLength = 16, 32
		}
		t.Run(fmt.Sprintf("tiled=%v", tiled), func(t *testing.T) {
			img := streamTestTIFF(t, s, 20)
			s.defaults()
			const outW, outH = 20, 9 // 47 × 20 / 101
			if got := img.Bounds(); got != image.Rect(0, 0, outW, outH) {
				t.Fatalf("bounds %v, want %d × %d", got, outW, outH)
			}
			for oy := range outH {
				for ox := range outW {
					var sum [3]uint64
					var n uint64
					for y := range s.height {
						for x := range s.width {
							if x*outW/s.width == ox && y*outH/s.height == oy {
								for c := range 3 {
									sum[c] += uint64(s.sample(x, y, c))
								}
								n++
							}
						}
					}
					got := pixelSamples(img, ox, oy)
					for c := range 3 {
						if want := uint8(sum[c] / n >> 8); got[c] != want {
							t.Fatalf("(%d, %d) channel %d: got %d, want %d", ox, oy, c, got[c], want)
						}
					}
				}
			}
		})
	}
}

// hugeTIFF claims to be 20000 × 20000 8-bit RGB: 1.6 GB decoded, far over
// MaxDecodeBytes. Its own strips point past the end of the file, so any
// attempt to read IFD0's pixels fails.
func hugeTIFF() testTIFF {
	return testTIFF{width: 20000, height: 20000, samples: 3, rowsPerStrip: 20000, skipData: true, bogusData: true}
}

// An oversized TIFF with a reduced-resolution SubIFD decodes from it, and the
// full-size image is never read. Too-small and unflagged directories are not
// taken.
func TestDecodeImage_OversizedTIFFUsesReducedSubIFD(t *testing.T) {
	reduced := testTIFF{width: 4100, height: 6, samples: 3, compression: tiffCompressionLZW, newSubfileType: 1}
	tooSmall := testTIFF{width: 100, height: 1, samples: 3, newSubfileType: 1}
	unflagged := testTIFF{width: 5000, height: 7, samples: 3}
	for name, s := range map[string]testTIFF{
		"subifd": func() testTIFF { h := hugeTIFF(); h.subIFDs = []testTIFF{tooSmall, reduced, unflagged}; return h }(),
		"chain":  func() testTIFF { h := hugeTIFF(); h.next = &reduced; return h }(),
	} {
		t.Run(name, func(t *testing.T) {
			img, format, err := DecodeImage(bytes.NewReader(writeTestTIFF(t, s)))
			if err != nil {
				t.Fatalf("DecodeImage: %v", err)
			}
			if format != "tiff" {
				t.Errorf("format %q, want tiff", format)
			}
			if got := img.Bounds(); got != image.Rect(0, 0, 4096, 5) {
				t.Errorf("bounds %v, want the reduced directory at 4096 × 5", got)
			}
		})
	}
}

// Without a usable reduced directory, the full-size image is the source:
// the bogus strips fail the decode, which shows they were the ones read.
func TestDecodeImage_OversizedTIFFWithoutReducedReadsFullImage(t *testing.T) {
	_, _, err := DecodeImage(bytes.NewReader(writeTestTIFF(t, hugeTIFF())))
	if err == nil || errors.Is(err, ErrImageTooLarge) {
		t.Fatalf("DecodeImage = %v, want a read error from the full image's strips", err)
	}
}

// An oversized TIFF the streaming decoder cannot read is refused as today,
// saying why.
func TestDecodeImage_OversizedTIFFUnsupported(t *testing.T) {
	for want, mutate := range map[string]func(*testTIFF){
		"JPEG":           func(s *testTIFF) { s.compression = 7 },
		"planar":         func(s *testTIFF) { s.planarConfig = 2 },
		"CMYK":           func(s *testTIFF) { s.samples, s.photometric = 4, 5 },
		"floating-point": func(s *testTIFF) { s.bits, s.sampleFormat = 16, 3 },
		"palette":        func(s *testTIFF) { s.samples, s.photometric = 1, 3 },
	} {
		t.Run(want, func(t *testing.T) {
			s := hugeTIFF()
			mutate(&s)
			_, _, err := DecodeImage(bytes.NewReader(writeTestTIFF(t, s)))
			if !errors.Is(err, ErrImageTooLarge) {
				t.Fatalf("DecodeImage = %v, want ErrImageTooLarge", err)
			}
			if !strings.Contains(err.Error(), want) {
				t.Errorf("error %q does not say %q", err, want)
			}
		})
	}
}

// A TIFF within the budget is still x/image's full decode, at full size.
func TestDecodeImage_TIFFWithinBudgetIsFullSize(t *testing.T) {
	data := writeTestTIFF(t, testTIFF{width: 50, height: 30, samples: 3, compression: tiffCompressionLZW})
	img, format, err := DecodeImage(bytes.NewReader(data))
	if err != nil || format != "tiff" {
		t.Fatalf("DecodeImage = %v, %q", err, format)
	}
	if got := img.Bounds(); got != image.Rect(0, 0, 50, 30) {
		t.Errorf("bounds %v", got)
	}
}

// A 16-bit image under the pixel cap but over the byte budget is refused
// before it is decoded, when it is not a TIFF read in place.
func TestDecodeImage_SixteenBitStreamOverByteBudget(t *testing.T) {
	data := writeTestTIFF(t, testTIFF{width: 6000, height: 6000, samples: 3, bits: 16, skipData: true})
	if 6000*6000 > MaxDecodePixels {
		t.Fatal("fixture must be under the pixel cap")
	}
	_, _, err := DecodeImage(bytes.NewBuffer(data))
	if !errors.Is(err, ErrImageTooLarge) {
		t.Fatalf("DecodeImage = %v, want ErrImageTooLarge", err)
	}
}

// EXIF orientation is applied to an oversized TIFF's rendering as to any
// other photo's.
func TestDecodeImageUpright_OversizedTIFFOrientation(t *testing.T) {
	h := hugeTIFF()
	h.orientation = 6
	h.subIFDs = []testTIFF{{width: 4100, height: 6, samples: 3, newSubfileType: 1}}
	img, err := DecodeImageUpright(bytes.NewReader(writeTestTIFF(t, h)))
	if err != nil {
		t.Fatalf("DecodeImageUpright: %v", err)
	}
	if got := img.Bounds(); got.Dx() != 5 || got.Dy() != 4096 {
		t.Errorf("bounds %v, want the 4096 × 5 rendering turned to 5 × 4096", got)
	}
}

// thumbnailUnderMemoryLimit writes s to a temp file and thumbnails it under
// a memory limit far below a full decode, failing if the thumbnail
// allocated more than budget in total.
func thumbnailUnderMemoryLimit(t *testing.T, s testTIFF, budget uint64) {
	t.Helper()
	s.repeatFirstChunk = true
	path := filepath.Join(t.TempDir(), "scan.tif")
	if err := os.WriteFile(path, writeTestTIFF(t, s), 0o600); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	defer debug.SetMemoryLimit(debug.SetMemoryLimit(int64(budget)))
	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	result, err := GenerateThumbnailFromReader(f, ".tif", 256, 256)
	runtime.ReadMemStats(&after)
	if err != nil {
		t.Fatalf("GenerateThumbnailFromReader: %v", err)
	}
	if got := result.Thumbnail.Bounds(); got.Dx() != 256 || got.Dy() != 256 {
		t.Errorf("thumbnail %v, want 256 × 256", got)
	}
	if result.DHash == "" {
		t.Error("no dHash")
	}
	full := uint64(s.width*s.height) * 4
	if s.bits == 16 {
		full *= 2
	}
	if allocated := after.TotalAlloc - before.TotalAlloc; allocated > budget {
		t.Errorf("thumbnailing allocated %d MiB; budget %d MiB, a full decode %d MiB", allocated>>20, budget>>20, full>>20)
	}
}

// The #1705-style guard: a 200 MP 8-bit LZW scan thumbnails in a fraction
// of the 800 MB a full decode asks for.
func TestGenerateThumbnail_200MPTIFFBoundedMemory(t *testing.T) {
	if testing.Short() {
		t.Skip("streams 200 MP")
	}
	thumbnailUnderMemoryLimit(t, testTIFF{
		width: 20000, height: 10000, samples: 3, compression: tiffCompressionLZW, rowsPerStrip: 16,
		pixel: func(x, _, c int) uint16 { return uint16((x + c*80) % 256 * 257) },
	}, 128<<20)
}

// A 60 MP 16-bit TIFF is under the pixel cap but 480 MB decoded; it streams
// too.
func TestGenerateThumbnail_16Bit60MPTIFFBoundedMemory(t *testing.T) {
	if testing.Short() {
		t.Skip("streams 60 MP")
	}
	thumbnailUnderMemoryLimit(t, testTIFF{
		width: 10000, height: 6000, samples: 3, bits: 16, compression: tiffCompressionDeflate, predictor: 2,
		tileWidth: 256, tileLength: 256,
		pixel: func(x, y, c int) uint16 { return uint16(x*5 + y*3 + c*1000) },
	}, 128<<20)
}

package photoutil

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/color"
	"io"

	"github.com/bep/imagemeta"
	"golang.org/x/image/tiff"
)

// MaxDecodePixels is the most pixels any image other than a TIFF is decoded
// at. A decoder sizes its pixel buffer from the header alone, so a few
// hundred bytes of PNG claiming 16k × 16k ask for a gigabyte (#2762). 64 MP
// admits a 48 MP phone photo with room to spare and costs at most 256 MiB of
// 8-bit RGBA.
const MaxDecodePixels = 64_000_000

// MaxDecodeBytes is the most memory a full decode may ask for, counted from
// the header: four bytes a pixel, eight when samples are 16-bit. It is what
// [MaxDecodePixels] of 8-bit RGBA costs, and it also stops a 16-bit image
// under the pixel cap from taking twice that (#4199).
const MaxDecodeBytes = 256 << 20

// LargeImageLongSide is the long side, in pixels, an oversized TIFF is
// rendered at. It is the TIFF's thumbnail source, its hash source, and its
// full view.
const LargeImageLongSide = 4096

// MaxStreamedPixels bounds the TIFF an oversized decode will stream through:
// a few kilobytes of compressed TIFF can claim a terapixel, and streaming
// costs CPU in proportion to the pixels even when memory stays flat.
const MaxStreamedPixels = 4_000_000_000

// ErrImageTooLarge reports an image whose header claims more than
// [MaxDecodePixels] pixels or [MaxDecodeBytes] of decoded pixels, and that
// cannot be rendered smaller instead. It is refused before any pixel is
// decoded.
var ErrImageTooLarge = errors.New("image is too large to decode")

// DecodeImage decodes an image after checking from its header alone that it
// fits [MaxDecodePixels] and [MaxDecodeBytes]. Every full decode of a user's
// image goes through here.
//
// A TIFF from a source that reads at an offset (a vfs.File, an os.File, a
// bytes.Reader) is read in place, never buffered. One over the byte budget
// is not refused: it decodes from a reduced-resolution directory the file
// already has, or else streams row by row or tile by tile into an image of
// at most [LargeImageLongSide] on its long side. Only a TIFF the streaming
// decoder cannot read (JPEG compression, separate planes, CMYK, floating
// point, …) is [ErrImageTooLarge].
//
// A seekable r is rewound after the header is read. A stream is replayed from
// the bytes the header read consumed, which for JPEG, PNG, GIF, WebP and BMP
// is the header; the TIFF decoder reads a stream whole either way.
func DecodeImage(r io.Reader) (image.Image, string, error) {
	var head bytes.Buffer
	rs, seekable := r.(io.ReadSeeker)
	var start int64
	var configSource io.Reader
	if seekable {
		var err error
		if start, err = rs.Seek(0, io.SeekCurrent); err != nil {
			return nil, "", fmt.Errorf("decode image: %w", err)
		}
		if ra, ok := r.(io.ReaderAt); ok {
			if img, handled, err := decodeTIFFAt(ra, rs, start); handled {
				return img, "tiff", err
			}
		}
		configSource = rs
	} else {
		configSource = io.TeeReader(r, &head)
	}

	cfg, _, err := image.DecodeConfig(configSource)
	if err != nil {
		return nil, "", fmt.Errorf("decode image header: %w", err)
	}
	if int64(cfg.Width)*int64(cfg.Height) > MaxDecodePixels {
		return nil, "", fmt.Errorf("%w: %d × %d is over %d pixels", ErrImageTooLarge, cfg.Width, cfg.Height, MaxDecodePixels)
	}
	if n := decodedBytes(cfg); n > MaxDecodeBytes {
		return nil, "", fmt.Errorf("%w: %d × %d decodes to %d bytes, over %d", ErrImageTooLarge, cfg.Width, cfg.Height, n, MaxDecodeBytes)
	}

	source := io.MultiReader(&head, r)
	if seekable {
		if _, err := rs.Seek(start, io.SeekStart); err != nil {
			return nil, "", fmt.Errorf("decode image: %w", err)
		}
		source = rs
	}
	img, format, err := image.Decode(source)
	if err != nil {
		return nil, "", fmt.Errorf("decode image: %w", err)
	}
	return img, format, nil
}

// DecodeImageUpright decodes r as [DecodeImage] does and, when r seeks,
// turns the result upright by the EXIF orientation of its format. It is for
// an image re-encoded for a client, which carries no EXIF to turn it by.
func DecodeImageUpright(r io.Reader) (image.Image, error) {
	img, format, err := DecodeImage(r)
	if err != nil {
		return nil, err
	}
	rs, ok := r.(io.ReadSeeker)
	if !ok {
		return img, nil
	}
	formats := map[string]imagemeta.ImageFormat{
		"jpeg": imagemeta.JPEG,
		"png":  imagemeta.PNG,
		"webp": imagemeta.WebP,
		"tiff": imagemeta.TIFF,
	}
	if orientation := sourceOrientation(rs, formats[format]); orientation > 1 {
		return applyExifOrientation(img, orientation), nil
	}
	return img, nil
}

// decodedBytes is what decoding an image of cfg costs: eight bytes a pixel
// for a 16-bit color model, four otherwise.
func decodedBytes(cfg image.Config) int64 {
	perPixel := int64(4)
	switch cfg.ColorModel {
	case color.RGBA64Model, color.NRGBA64Model:
		perPixel = 8
	}
	return int64(cfg.Width) * int64(cfg.Height) * perPixel
}

// decodeTIFFAt decodes a TIFF held at ra from start, reporting handled false
// when the source is not a TIFF. Within [MaxDecodeBytes] it is x/image's
// decoder, reading in place; over it, the large-image path.
func decodeTIFFAt(ra io.ReaderAt, rs io.Seeker, start int64) (image.Image, bool, error) {
	end, err := rs.Seek(0, io.SeekEnd)
	if err == nil {
		_, err = rs.Seek(start, io.SeekStart)
	}
	if err != nil {
		return nil, true, fmt.Errorf("decode image: %w", err)
	}
	section := io.NewSectionReader(ra, start, end-start)
	head := make([]byte, 4)
	if _, err := section.ReadAt(head, 0); err != nil || !isTIFFHeader(head) {
		return nil, false, nil
	}
	layout, err := readTIFFLayout(section, section.Size())
	if err != nil {
		return nil, true, fmt.Errorf("decode image header: %w", err)
	}
	if layout.dirs[0].decodedBytes() <= MaxDecodeBytes {
		img, err := tiff.Decode(section)
		if err != nil {
			return nil, true, fmt.Errorf("decode image: %w", err)
		}
		return img, true, nil
	}
	ifd, err := layout.largeTIFFSource(MaxDecodeBytes, LargeImageLongSide)
	if err != nil {
		return nil, true, err
	}
	img, err := decodeTIFFStreamed(section, layout.order, ifd, LargeImageLongSide)
	if err != nil {
		return nil, true, fmt.Errorf("decode image: %w", err)
	}
	return img, true, nil
}

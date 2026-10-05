package photoutil

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"io"
)

// MaxDecodePixels is the most pixels any image is decoded at. A decoder
// sizes its pixel buffer from the header alone, so a few hundred bytes of PNG
// claiming 16k × 16k ask for a gigabyte (#2762). 64 MP admits a 48 MP phone
// photo with room to spare and costs at most 256 MiB of 8-bit RGBA.
const MaxDecodePixels = 64_000_000

// ErrImageTooLarge reports an image whose header claims more than
// [MaxDecodePixels] pixels. It is refused before any pixel is decoded.
var ErrImageTooLarge = errors.New("image is too large to decode")

// DecodeImage decodes an image after checking from its header alone that it
// is within [MaxDecodePixels]. Every full decode of a user's image goes
// through here.
//
// A seekable r is rewound after the header is read. A stream is replayed from
// the bytes the header read consumed, which for JPEG, PNG, GIF, WebP and BMP
// is the header; TIFF and HEIC decoders read a stream whole either way.
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

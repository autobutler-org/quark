package photoutil

import (
	"image"
	"io"

	"github.com/bep/imagemeta"
)

// sourceOrientation is the EXIF orientation to apply to an image decoded from
// r, read from the start of r, because the decode has already consumed it.
//
// It is the one place that decision is made, because whether orientation
// *should* be applied depends on the decoder: libheif — behind image.Decode
// for HEIC/HEIF — applies the container's rotate and mirror transforms itself
// and hands back pixels that are already upright, leaving the EXIF tag
// informational (gen2brain/heic says so on DecodeExif). Applying the tag on top
// of that rotates the image a second time, which is why iPhone portrait photos
// came back sideways (#1798). Every other decoder registered here — Go's JPEG,
// PNG and GIF, x/image's BMP, TIFF and WebP — ignores orientation, so those
// still need it applied.
func sourceOrientation(r io.ReadSeeker, format imagemeta.ImageFormat) int {
	if format == 0 || format == imagemeta.HEIF {
		return 1
	}
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return 1
	}
	return GetOrientation(r, format)
}

// uprightThumbnail scales and center-crops a decoded source to width × height
// as it will look once its EXIF orientation is applied, and applies the
// orientation to the thumbnail rather than to the source (#2762). Rotating
// the source first cost a second full-size RGBA and most of the CPU of a
// portrait thumbnail.
func uprightThumbnail(img image.Image, orientation int, width, height uint) (image.Image, error) {
	if swapsAxes(orientation) {
		width, height = height, width
	}
	thumb, _, err := cropToFit(img, width, height)
	if err != nil {
		return nil, err
	}
	return applyExifOrientation(thumb, orientation), nil
}

// swapsAxes reports whether an EXIF orientation turns the image a quarter,
// so that its upright width is the source's height.
func swapsAxes(orientation int) bool {
	return orientation >= 5 && orientation <= 8
}

// uprightCoord maps the pixel at (x, y) of a w × h source, counted from its
// origin, to where an EXIF orientation puts it in the upright image.
// http://sylvana.net/jpegcrop/exif_orientation.html
func uprightCoord(orientation, w, h, x, y int) (int, int) {
	switch orientation {
	case 2:
		return w - 1 - x, y
	case 3:
		return w - 1 - x, h - 1 - y
	case 4:
		return x, h - 1 - y
	case 5:
		return y, x
	case 6:
		return h - 1 - y, x
	case 7:
		return h - 1 - y, w - 1 - x
	case 8:
		return y, w - 1 - x
	}
	return x, y
}

// applyExifOrientation transforms an image by an EXIF orientation value. The
// result starts at the origin whatever img's bounds are, because cropToFit
// hands back a SubImage that does not.
func applyExifOrientation(img image.Image, orientation int) image.Image {
	if orientation < 2 || orientation > 8 {
		return img
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	out := image.NewRGBA(image.Rect(0, 0, w, h))
	if swapsAxes(orientation) {
		out = image.NewRGBA(image.Rect(0, 0, h, w))
	}
	for y := range h {
		for x := range w {
			ux, uy := uprightCoord(orientation, w, h, x, y)
			out.Set(ux, uy, img.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return out
}

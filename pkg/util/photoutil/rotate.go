package photoutil

import (
	"image"
	"io"

	"github.com/bep/imagemeta"
)

// orientDecodedImage turns a freshly decoded image upright using the EXIF
// orientation of the source stream it was decoded from. r is rewound to
// the start, because the decode has already consumed it.
//
// It is the one place orientation is applied, because whether it *should* be
// applied depends on the decoder: libheif — behind image.Decode for HEIC/HEIF —
// applies the container's rotate and mirror transforms itself and hands back
// pixels that are already upright, leaving the EXIF tag informational
// (gen2brain/heic says so on DecodeExif). Applying the tag on top of that
// rotates the image a second time, which is why iPhone portrait photos came
// back sideways (#1798). Every other decoder registered here — Go's JPEG, PNG
// and GIF, x/image's BMP, TIFF and WebP — ignores orientation, so those still
// need it applied.
func orientDecodedImage(img image.Image, r io.ReadSeeker, format imagemeta.ImageFormat) image.Image {
	if format == 0 || format == imagemeta.HEIF {
		return img
	}
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return img
	}
	return applyExifOrientation(img, GetOrientation(r, format))
}

// applyExifOrientation transforms an image based on the EXIF orientation value.
// http://sylvana.net/jpegcrop/exif_orientation.html
func applyExifOrientation(img image.Image, orientation int) image.Image {
	switch orientation {
	case 2:
		return flipHorizontal(img)
	case 3:
		return rotate180(img)
	case 4:
		return flipVertical(img)
	case 5:
		return rotate270(flipHorizontal(img))
	case 6:
		return rotate90(img)
	case 7:
		return rotate90(flipHorizontal(img))
	case 8:
		return rotate270(img)
	default:
		return img
	}
}

func rotate90(img image.Image) image.Image {
	bounds := img.Bounds()
	newImg := image.NewRGBA(image.Rect(0, 0, bounds.Dy(), bounds.Dx()))
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			newImg.Set(bounds.Max.Y-y-1, x, img.At(x, y))
		}
	}
	return newImg
}

func rotate180(img image.Image) image.Image {
	bounds := img.Bounds()
	newImg := image.NewRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			newImg.Set(bounds.Max.X-x-1, bounds.Max.Y-y-1, img.At(x, y))
		}
	}
	return newImg
}

func rotate270(img image.Image) image.Image {
	bounds := img.Bounds()
	newImg := image.NewRGBA(image.Rect(0, 0, bounds.Dy(), bounds.Dx()))
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			newImg.Set(y, bounds.Max.X-x-1, img.At(x, y))
		}
	}
	return newImg
}

func flipHorizontal(img image.Image) image.Image {
	bounds := img.Bounds()
	newImg := image.NewRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			newImg.Set(bounds.Max.X-x-1, y, img.At(x, y))
		}
	}
	return newImg
}

func flipVertical(img image.Image) image.Image {
	bounds := img.Bounds()
	newImg := image.NewRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			newImg.Set(x, bounds.Max.Y-y-1, img.At(x, y))
		}
	}
	return newImg
}

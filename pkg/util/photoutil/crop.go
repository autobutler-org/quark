package photoutil

import (
	"fmt"
	"image"

	"github.com/KononK/resize"
)

// cropToFit scales and center-crops an image to the target dimensions.
func cropToFit(img image.Image, width, height uint) (image.Image, string, error) {
	bounds := img.Bounds()
	srcW := uint(bounds.Dx())
	srcH := uint(bounds.Dy())

	if srcW == 0 || srcH == 0 {
		return nil, "", fmt.Errorf("source image has zero dimensions")
	}

	var scaledW, scaledH uint
	if srcW*height > srcH*width {
		scaledH = height
		scaledW = srcW * height / srcH
	} else {
		scaledW = width
		scaledH = srcH * width / srcW
	}

	scaled := resize.Resize(scaledW, scaledH, img, resize.Lanczos3)

	scaledBounds := scaled.Bounds()
	x0 := (scaledBounds.Dx() - int(width)) / 2
	y0 := (scaledBounds.Dy() - int(height)) / 2

	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	if si, ok := scaled.(subImager); ok {
		return si.SubImage(image.Rect(x0, y0, x0+int(width), y0+int(height))), "jpeg", nil
	}

	cropped := image.NewRGBA(image.Rect(0, 0, int(width), int(height)))
	for y := 0; y < int(height); y++ {
		for x := 0; x < int(width); x++ {
			cropped.Set(x, y, scaled.At(x0+x, y0+y))
		}
	}
	return cropped, "jpeg", nil
}

// resizeTo brings an image to a thumbnail tier's box the way mode says.
func resizeTo(img image.Image, width, height uint, mode Resize) (image.Image, error) {
	if mode == ResizeFit {
		return scaleWithin(img, width, height)
	}
	thumb, _, err := cropToFit(img, width, height)
	return thumb, err
}

// scaleWithin scales an image down to fit within width × height, keeping its
// aspect ratio. An image already inside the box is returned as it is: a
// display rendition is never upscaled.
func scaleWithin(img image.Image, width, height uint) (image.Image, error) {
	bounds := img.Bounds()
	srcW := uint(bounds.Dx())
	srcH := uint(bounds.Dy())

	if srcW == 0 || srcH == 0 {
		return nil, fmt.Errorf("source image has zero dimensions")
	}
	if srcW <= width && srcH <= height {
		return img, nil
	}
	if srcW*height > srcH*width {
		return resize.Resize(width, max(1, srcH*width/srcW), img, resize.Lanczos3), nil
	}
	return resize.Resize(max(1, srcW*height/srcH), height, img, resize.Lanczos3), nil
}

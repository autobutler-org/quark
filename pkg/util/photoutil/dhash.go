package photoutil

import (
	"encoding/binary"
	"encoding/hex"
	"image"
	"math/bits"
)

const (
	// dHashWidth is the number of columns in the dHash grid.
	// Each row produces (dHashWidth-1) bits of horizontal difference, so a
	// 9×8 grid yields 8×8 = 64 bits total.
	dHashWidth  = 9
	dHashHeight = 8
)

// DHash computes the difference hash (dHash) of img as a 64-bit integer.
//
// Algorithm:
//  1. Average the luma of img over a dHashWidth × dHashHeight (9 × 8) grid of
//     cells. Every source pixel counts once, so the result depends on the
//     picture rather than which pixels a sparse sample landed on: that is
//     what lets a full-resolution decode and a 400px client thumbnail of the
//     same photo land within a few bits.
//  2. For each row, compare adjacent cells left-to-right: set bit = 1 when
//     the left cell is brighter than the right one.
//
// It reads each pixel once and allocates nothing, so hashing a
// full-resolution decode costs its pixels in time, not memory.
//
// The result is an 8-byte (64-bit) value. Two images with a Hamming distance
// <= 10 are considered near-duplicates in practice.
func DHash(img image.Image) uint64 {
	return dHashGrid(lumaGrid(img, 1))
}

// uprightDHash is the hex dHash of img as it looks once an EXIF orientation is
// applied, bit for bit, without building the upright image: the grid cells
// are laid over the upright picture and each source pixel is added to the
// cell it lands in.
func uprightDHash(img image.Image, orientation int) string {
	return hashHex(dHashGrid(lumaGrid(img, orientation)))
}

// dHashGrid sets one bit per pair of horizontally adjacent grid cells.
func dHashGrid(grid [dHashHeight][dHashWidth]float64) uint64 {
	// Compute horizontal differences row by row.
	var hash uint64
	var bit uint64 = 1
	for y := 0; y < dHashHeight; y++ {
		for x := 0; x < dHashWidth-1; x++ {
			if grid[y][x] > grid[y][x+1] {
				hash |= bit
			}
			bit <<= 1
		}
	}
	return hash
}

// DHashHex returns the hex-encoded 16-character string representation of the
// dHash for img (suitable for storage in SQLite and indexed string comparison).
func DHashHex(img image.Image) string {
	return hashHex(DHash(img))
}

// hashHex is the 16-character hex spelling of a dHash.
func hashHex(h uint64) string {
	var buf [8]byte
	binary.BigEndian.PutUint64(buf[:], h)
	return hex.EncodeToString(buf[:])
}

// HammingDistance returns the number of differing bits between two dHash
// values. Values <= 10 indicate near-duplicate images.
func HammingDistance(a, b uint64) int {
	return bits.OnesCount64(a ^ b)
}

// HammingDistanceHex parses two 16-char hex dHash strings and returns their
// Hamming distance. Returns -1 if either string is malformed.
func HammingDistanceHex(a, b string) int {
	da, err := hexToUint64(a)
	if err != nil {
		return -1
	}
	db, err := hexToUint64(b)
	if err != nil {
		return -1
	}
	return HammingDistance(da, db)
}

func hexToUint64(s string) (uint64, error) {
	raw, err := hex.DecodeString(s)
	if err != nil || len(raw) != 8 {
		return 0, err
	}
	return binary.BigEndian.Uint64(raw), nil
}

// lumaGrid is the mean luma over each cell of a 9 × 8 grid laid on img as an
// EXIF orientation turns it upright. A cell with no pixels, in an image
// narrower or shorter than the grid, takes the pixel it falls on.
func lumaGrid(img image.Image, orientation int) [dHashHeight][dHashWidth]float64 {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	var grid [dHashHeight][dHashWidth]float64
	if w == 0 || h == 0 {
		return grid
	}
	uw, uh := w, h
	if swapsAxes(orientation) {
		uw, uh = h, w
	}
	if orientation != 1 && (uw < dHashWidth || uh < dHashHeight) {
		// Some cell has no pixel and takes one by its upright position;
		// an image this thin is cheap to turn upright instead.
		return lumaGrid(applyExifOrientation(img, orientation), 1)
	}
	at := pixelLuma(img)
	var sum, count [dHashHeight][dHashWidth]uint64
	for y := range h {
		for x := range w {
			ux, uy := uprightCoord(orientation, w, h, x, y)
			gx, gy := ux*dHashWidth/uw, uy*dHashHeight/uh
			sum[gy][gx] += uint64(at(b.Min.X+x, b.Min.Y+y))
			count[gy][gx]++
		}
	}
	for gy := range dHashHeight {
		for gx := range dHashWidth {
			if count[gy][gx] == 0 {
				grid[gy][gx] = float64(at(b.Min.X+gx*w/dHashWidth, b.Min.Y+gy*h/dHashHeight))
				continue
			}
			grid[gy][gx] = float64(sum[gy][gx]) / float64(count[gy][gx])
		}
	}
	return grid
}

// pixelLuma returns a reader of the 8-bit luma at a pixel of img. The image
// types the decoders here produce read straight from their pixel buffers;
// anything else goes through At, which allocates.
func pixelLuma(img image.Image) func(x, y int) uint32 {
	switch m := img.(type) {
	case *image.YCbCr:
		// JPEG: the Y plane is the luma already.
		return func(x, y int) uint32 { return uint32(m.Y[m.YOffset(x, y)]) }
	case *image.Gray:
		return func(x, y int) uint32 { return uint32(m.Pix[m.PixOffset(x, y)]) }
	case *image.RGBA:
		return func(x, y int) uint32 { return rgbLuma(m.Pix[m.PixOffset(x, y):]) }
	case *image.NRGBA:
		return func(x, y int) uint32 { return rgbLuma(m.Pix[m.PixOffset(x, y):]) }
	}
	return func(x, y int) uint32 {
		r, g, b, _ := img.At(x, y).RGBA()
		return (19595*r + 38470*g + 7471*b + 1<<15) >> 24
	}
}

// rgbLuma is the luma of the 8-bit R, G, B at the start of p, weighted the
// way color.GrayModel weighs them.
func rgbLuma(p []uint8) uint32 {
	return (19595*uint32(p[0]) + 38470*uint32(p[1]) + 7471*uint32(p[2]) + 1<<15) >> 16
}

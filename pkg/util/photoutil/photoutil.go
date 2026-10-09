// Package photoutil reads, transforms, and thumbnails photo and video files:
// listing the photo library through each device's VFS namespace, extracting
// EXIF metadata, correcting orientation, converting camera RAW, generating
// thumbnails, and comparing images by perceptual hash.
package photoutil

import (
	"fmt"
	"image"
	// Registers the GIF decoder with image.Decode.
	_ "image/gif"
	"io"
	"io/fs"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"

	// Registers the HEIC decoder with image.Decode.
	_ "github.com/gen2brain/heic"
	// Registers the BMP decoder with image.Decode.
	_ "golang.org/x/image/bmp"
	// Registers the TIFF decoder with image.Decode.
	_ "golang.org/x/image/tiff"
	// Registers the WebP decoder with image.Decode.
	_ "golang.org/x/image/webp"
)

// ExifData holds extracted EXIF fields in a format-agnostic way.
// Works for JPEG, HEIC/HEIF, PNG, WebP, TIFF, and RAW formats.
type ExifData struct {
	Orientation  int
	DateTaken    *time.Time
	Make         string
	Model        string
	LensModel    string
	Aperture     float64
	ShutterSpeed [2]int64 // numerator, denominator
	ISO          int
	FocalLength  float64
	Latitude     float64
	Longitude    float64
	HasGPS       bool
	Width        int
	Height       int
}

// GenerateThumbnailParams contains parameters for generating a thumbnail
type GenerateThumbnailParams struct {
	FilePath string
	Width    uint
	Height   uint
}

// GenerateThumbnailResult contains the result of generating a thumbnail
type GenerateThumbnailResult struct {
	Thumbnail image.Image
	Format    string
	// DHash is the perceptual hash of the whole upright source image, taken
	// before the crop and before any user rotation, so every size tier and
	// every path to the same file agrees on it (#1666). Empty for video.
	DHash string
}

// FilterPhotoFiles filters a list of files to only include photo files
func FilterPhotoFiles(files []fs.FileInfo) []fs.FileInfo {
	photoFiles := make([]fs.FileInfo, 0)
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		fileType := storageutil.DetermineFileTypeFromPath(file.Name())
		if fileType == storageutil.FileTypeImage {
			photoFiles = append(photoFiles, file)
		}
	}
	return photoFiles
}

// ImageToThumbnail decodes an image file, turns it upright, and scales and
// center-crops it to width × height. It returns the decoded format too.
func ImageToThumbnail(filePath string, width, height uint) (image.Image, string, error) {
	img, orientation, format, err := decodeImageFile(filePath)
	if err != nil {
		return nil, "", err
	}
	cropped, err := uprightThumbnail(img, orientation, width, height)
	if err != nil {
		return nil, "", fmt.Errorf("error cropping image file %s: %w", filePath, err)
	}
	return cropped, format, nil
}

// ApplyRotation rotates img by quarters × 90° clockwise.
// Negative values are normalized: -1 → 3, -2 → 2, etc.
func ApplyRotation(img image.Image, quarters int64) image.Image {
	// The EXIF orientations that turn an image 0°, 90°, 180° and 270°
	// clockwise.
	return applyExifOrientation(img, [4]int{1, 6, 3, 8}[((quarters%4)+4)%4])
}

// GenerateThumbnailFromReader creates a thumbnail from a seekable source: EXIF
// is read back after the decode has consumed it. A vfs.File seeks, so a
// library photo is never buffered; holding the whole image to get a seek put
// a multi-hundred-megabyte TIFF on the heap per request (#1723).
// ext is the lowercase file extension (e.g. ".jpg") used for format detection.
// RAW and video files are not supported — callers must use GenerateThumbnail for those.
func GenerateThumbnailFromReader(rs io.ReadSeeker, ext string, width, height uint) (*GenerateThumbnailResult, error) {
	fileType := storageutil.DetermineFileTypeFromPath("file" + ext)
	if fileType != storageutil.FileTypeImage {
		return nil, fmt.Errorf("GenerateThumbnailFromReader: unsupported file type for extension %q", ext)
	}

	img, format, err := DecodeImage(rs)
	if err != nil {
		return nil, fmt.Errorf("GenerateThumbnailFromReader: %w", err)
	}
	orientation := sourceOrientation(rs, ImageFormatFromPath("file"+ext))

	cropped, err := uprightThumbnail(img, orientation, width, height)
	if err != nil {
		return nil, fmt.Errorf("GenerateThumbnailFromReader: crop: %w", err)
	}
	return &GenerateThumbnailResult{Thumbnail: cropped, Format: format, DHash: uprightDHash(img, orientation)}, nil
}

// GenerateThumbnail creates a thumbnail image from an image file. A video's
// frame is extracted by the caller first and passed in as an image.
func GenerateThumbnail(params GenerateThumbnailParams) (*GenerateThumbnailResult, error) {
	ext := strings.ToLower(filepath.Ext(params.FilePath))
	if storageutil.DetermineFileTypeFromPath("file"+ext) != storageutil.FileTypeImage {
		return nil, fmt.Errorf("unsupported file type for thumbnail: %s", ext)
	}

	// RAW camera files can't be decoded by Go's image package — convert
	// via an external tool first, then thumbnail the resulting JPEG.
	if IsRawFile(params.FilePath) {
		img, err := RawToJPEG(params.FilePath)
		if err != nil {
			return nil, fmt.Errorf("failed to convert RAW file: %w", err)
		}
		cropped, _, cropErr := cropToFit(img, params.Width, params.Height)
		if cropErr != nil {
			return nil, fmt.Errorf("crop RAW thumbnail: %w", cropErr)
		}
		return &GenerateThumbnailResult{Thumbnail: cropped, Format: "jpeg", DHash: DHashHex(img)}, nil
	}

	img, orientation, format, err := decodeImageFile(params.FilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to generate thumbnail: %w", err)
	}
	thumbnail, err := uprightThumbnail(img, orientation, params.Width, params.Height)
	if err != nil {
		return nil, fmt.Errorf("failed to generate thumbnail: %w", err)
	}

	return &GenerateThumbnailResult{
		Thumbnail: thumbnail,
		Format:    format,
		DHash:     uprightDHash(img, orientation),
	}, nil
}

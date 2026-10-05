// Package photoutil reads, transforms, and thumbnails photo and video files:
// discovering photos on disk, extracting EXIF metadata, correcting orientation,
// converting camera RAW, generating thumbnails, and comparing images by
// perceptual hash.
package photoutil

import (
	"bytes"
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

// PhotoInfo stores a photo with its relative path
type PhotoInfo struct {
	FileInfo     fs.FileInfo
	RelPath      string
	HasLiveVideo bool
}

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

// FindAllPhotosRecursively finds all photo files in a directory and its subdirectories.
// Also detects Live Photo companions (e.g. IMG_1234.HEIC + IMG_1234.MOV) by collecting
// video basenames during the same walk — no extra disk I/O.
func FindAllPhotosRecursively(rootDir string) ([]PhotoInfo, error) {
	var photos []PhotoInfo
	videoBasenames := make(map[string]bool)

	err := filepath.Walk(rootDir, func(path string, info fs.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if path != rootDir && storageutil.IsInternalName(info.Name()) {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if info.IsDir() {
			return nil
		}

		fileType := storageutil.DetermineFileTypeFromPath(info.Name())
		switch fileType {
		case storageutil.FileTypeImage:
			relPath, err := filepath.Rel(rootDir, path)
			if err != nil {
				return err // coverage: ignore - filepath.Rel only fails on cross-volume paths (different drives on Windows)
			}
			photos = append(photos, PhotoInfo{
				FileInfo: info,
				RelPath:  relPath,
			})
		case storageutil.FileTypeVideo:
			ext := filepath.Ext(path)
			videoBasenames[strings.TrimSuffix(path, ext)] = true
		}
		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("error walking directory %s: %w", rootDir, err)
	}

	for i := range photos {
		ext := filepath.Ext(photos[i].RelPath)
		lower := strings.ToLower(ext)
		if lower == ".heic" || lower == ".heif" || lower == ".jpg" || lower == ".jpeg" {
			fullBase := strings.TrimSuffix(filepath.Join(rootDir, photos[i].RelPath), ext)
			photos[i].HasLiveVideo = videoBasenames[fullBase]
		}
	}

	return photos, nil
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

// GenerateThumbnailFromReader creates a thumbnail from an io.Reader.
// ext is the lowercase file extension (e.g. ".jpg") used for format detection.
// RAW and video files are not supported — callers must use GenerateThumbnail for those.
func GenerateThumbnailFromReader(r io.Reader, ext string, width, height uint) (*GenerateThumbnailResult, error) {
	fileType := storageutil.DetermineFileTypeFromPath("file" + ext)
	if fileType != storageutil.FileTypeImage {
		return nil, fmt.Errorf("GenerateThumbnailFromReader: unsupported file type for extension %q", ext)
	}

	// EXIF is read after the decode has consumed the stream, so this needs to
	// seek back. It used to buffer the whole image to get that, which put a
	// multi-hundred-megabyte TIFF or RAW on the heap once per concurrent
	// request (#1723).
	rs, err := AsReadSeeker(r)
	if err != nil {
		return nil, fmt.Errorf("GenerateThumbnailFromReader: read: %w", err)
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

// AsReadSeeker returns r as an io.ReadSeeker for the decoders that have to
// re-read a stream (image decode, then EXIF off the same bytes).
//
// A source that already seeks is used in place — vfs.VFS.Open hands back an
// *os.File for both the local and storage-service namespaces, so in production
// this is the branch taken and nothing is buffered. Only a stream-only source
// falls back to holding the whole thing in memory, which is what every caller
// used to do unconditionally (#1723).
func AsReadSeeker(r io.Reader) (io.ReadSeeker, error) {
	if rs, ok := r.(io.ReadSeeker); ok {
		return rs, nil
	}
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	return bytes.NewReader(data), nil
}

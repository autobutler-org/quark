package photoutil

import (
	"image"
	"image/color"
	_ "image/jpeg" // Import JPEG decoder
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func createTestImage(t *testing.T, path string, width, height int) {
	t.Helper()

	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.Set(x, y, color.RGBA{uint8(x % 256), uint8(y % 256), 128, 255})
		}
	}

	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("Failed to create test image: %v", err)
	}
	defer f.Close()

	if err := png.Encode(f, img); err != nil {
		t.Fatalf("Failed to encode test image: %v", err)
	}
}

func TestFilterPhotoFiles(t *testing.T) {
	tmpDir := t.TempDir()

	photoPath := filepath.Join(tmpDir, "photo.jpg")
	createTestImage(t, photoPath, 100, 100)

	txtPath := filepath.Join(tmpDir, "readme.txt")
	os.WriteFile(txtPath, []byte("text"), 0644)

	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		t.Fatalf("Failed to read test directory: %v", err)
	}

	var fileInfos []os.FileInfo
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil {
			continue
		}
		fileInfos = append(fileInfos, info)
	}

	photos := FilterPhotoFiles(fileInfos)

	if len(photos) != 1 {
		t.Errorf("Expected 1 photo, got %d", len(photos))
	}
}

func TestFindAllPhotosRecursively(t *testing.T) {
	tmpDir := t.TempDir()

	createTestImage(t, filepath.Join(tmpDir, "photo1.png"), 50, 50)
	createTestImage(t, filepath.Join(tmpDir, "photo2.jpg"), 50, 50)

	subDir := filepath.Join(tmpDir, "subdir")
	os.Mkdir(subDir, 0755)
	createTestImage(t, filepath.Join(subDir, "photo3.png"), 50, 50)

	os.WriteFile(filepath.Join(tmpDir, "readme.txt"), []byte("text"), 0644)

	// Trashed photos are not part of the library.
	trashDir := filepath.Join(tmpDir, storageutil.TrashDir)
	os.Mkdir(trashDir, 0755)
	createTestImage(t, filepath.Join(trashDir, "20240101T000000Z_abcd_gone.png"), 50, 50)

	photos, err := FindAllPhotosRecursively(tmpDir)
	if err != nil {
		t.Fatalf("FindAllPhotosRecursively failed: %v", err)
	}

	if len(photos) != 3 {
		t.Errorf("Expected 3 photos, got %d", len(photos))
	}
}

func TestImageToThumbnail(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "test.png")
	createTestImage(t, imagePath, 200, 200)

	thumbnail, format, err := ImageToThumbnail(imagePath, 50, 50)
	if err != nil {
		t.Fatalf("ImageToThumbnail failed: %v", err)
	}

	if thumbnail == nil {
		t.Fatal("Expected non-nil thumbnail")
	}

	if format != "png" {
		t.Errorf("Expected format 'png', got '%s'", format)
	}

	bounds := thumbnail.Bounds()
	if bounds.Dx() != 50 || bounds.Dy() != 50 {
		t.Errorf("Expected 50x50 thumbnail, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestImageToThumbnail_NonSquareLandscape(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "landscape.png")
	createTestImage(t, imagePath, 400, 200) // 2:1 landscape

	thumbnail, _, err := ImageToThumbnail(imagePath, 50, 50)
	if err != nil {
		t.Fatalf("ImageToThumbnail failed: %v", err)
	}

	bounds := thumbnail.Bounds()
	if bounds.Dx() != 50 || bounds.Dy() != 50 {
		t.Errorf("Expected 50x50 thumbnail, got %dx%d (landscape input must be cropped, not squished)", bounds.Dx(), bounds.Dy())
	}
}

func TestImageToThumbnail_NonSquarePortrait(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "portrait.png")
	createTestImage(t, imagePath, 200, 400) // 1:2 portrait

	thumbnail, _, err := ImageToThumbnail(imagePath, 50, 50)
	if err != nil {
		t.Fatalf("ImageToThumbnail failed: %v", err)
	}

	bounds := thumbnail.Bounds()
	if bounds.Dx() != 50 || bounds.Dy() != 50 {
		t.Errorf("Expected 50x50 thumbnail, got %dx%d (portrait input must be cropped, not squished)", bounds.Dx(), bounds.Dy())
	}
}

func TestRotate90(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 3))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})

	rotated := rotate90(img)
	bounds := rotated.Bounds()

	if bounds.Dx() != 3 || bounds.Dy() != 2 {
		t.Errorf("Expected 3x2, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestRotate180(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})

	rotated := rotate180(img)
	bounds := rotated.Bounds()

	if bounds.Dx() != 2 || bounds.Dy() != 2 {
		t.Errorf("Expected 2x2, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestRotate270(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 3))

	rotated := rotate270(img)
	bounds := rotated.Bounds()

	if bounds.Dx() != 3 || bounds.Dy() != 2 {
		t.Errorf("Expected 3x2, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestFlipHorizontal(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})
	img.Set(1, 0, color.RGBA{0, 255, 0, 255})

	flipped := flipHorizontal(img)

	r1, g1, _, _ := flipped.At(0, 0).RGBA()
	r2, g2, _, _ := flipped.At(1, 0).RGBA()

	if g1 <= r1 {
		t.Error("Expected left pixel to be green after horizontal flip")
	}

	if r2 <= g2 {
		t.Error("Expected right pixel to be red after horizontal flip")
	}
}

func TestFlipVertical(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})
	img.Set(0, 1, color.RGBA{0, 255, 0, 255})

	flipped := flipVertical(img)

	r1, g1, _, _ := flipped.At(0, 0).RGBA()
	r2, g2, _, _ := flipped.At(0, 1).RGBA()

	if g1 <= r1 {
		t.Error("Expected top pixel to be green after vertical flip")
	}

	if r2 <= g2 {
		t.Error("Expected bottom pixel to be red after vertical flip")
	}
}

func TestGenerateThumbnail(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "test.png")
	createTestImage(t, imagePath, 100, 100)

	params := GenerateThumbnailParams{
		FilePath: imagePath,
		Width:    25,
		Height:   25,
	}

	result, err := GenerateThumbnail(params)
	if err != nil {
		t.Fatalf("GenerateThumbnail failed: %v", err)
	}

	if result.Thumbnail == nil {
		t.Fatal("Expected non-nil thumbnail")
	}

	if result.Format != "png" {
		t.Errorf("Expected format 'png', got '%s'", result.Format)
	}
}

func TestGenerateThumbnail_Error(t *testing.T) {
	// Test with non-existent file to trigger error
	params := GenerateThumbnailParams{
		FilePath: "/nonexistent/file.jpg",
		Width:    50,
		Height:   50,
	}

	result, err := GenerateThumbnail(params)
	if err == nil {
		t.Fatal("Expected error for non-existent file")
	}

	if result != nil {
		t.Error("Expected nil result on error")
	}
}

func TestGenerateThumbnail_UnsupportedFileType(t *testing.T) {
	tmpDir := t.TempDir()
	unsupported := filepath.Join(tmpDir, "document.psd")
	os.WriteFile(unsupported, []byte("fake psd content"), 0644)

	result, err := GenerateThumbnail(GenerateThumbnailParams{
		FilePath: unsupported,
		Width:    50,
		Height:   50,
	})
	if err == nil {
		t.Fatal("Expected error for unsupported file type")
	}
	if result != nil {
		t.Error("Expected nil result for unsupported file type")
	}
}

func TestFilterPhotoFiles_EmptyList(t *testing.T) {
	result := FilterPhotoFiles([]os.FileInfo{})
	if len(result) != 0 {
		t.Errorf("Expected empty result, got %d items", len(result))
	}
}

func TestFilterPhotoFiles_MixedFiles(t *testing.T) {
	tmpDir := t.TempDir()

	// Create test files
	createTestImage(t, filepath.Join(tmpDir, "image.jpg"), 10, 10)
	os.WriteFile(filepath.Join(tmpDir, "document.pdf"), []byte("pdf"), 0644)
	os.Mkdir(filepath.Join(tmpDir, "subdir"), 0755)

	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		t.Fatalf("Failed to read directory: %v", err)
	}

	var fileInfos []os.FileInfo
	for _, entry := range entries {
		info, _ := entry.Info()
		fileInfos = append(fileInfos, info)
	}

	photos := FilterPhotoFiles(fileInfos)

	if len(photos) != 1 {
		t.Errorf("Expected 1 photo file, got %d", len(photos))
	}
}

func TestFindAllPhotosRecursively_EmptyDirectory(t *testing.T) {
	tmpDir := t.TempDir()

	photos, err := FindAllPhotosRecursively(tmpDir)
	if err != nil {
		t.Fatalf("FindAllPhotosRecursively failed: %v", err)
	}

	if len(photos) != 0 {
		t.Errorf("Expected 0 photos in empty directory, got %d", len(photos))
	}
}

func TestFindAllPhotosRecursively_NonExistentDirectory(t *testing.T) {
	_, err := FindAllPhotosRecursively("/nonexistent/path/that/does/not/exist")
	if err == nil {
		t.Error("Expected error for non-existent directory")
	}
}

func TestImageToThumbnail_NonExistentFile(t *testing.T) {
	_, _, err := ImageToThumbnail("/nonexistent/file.jpg", 50, 50)
	if err == nil {
		t.Error("Expected error for non-existent file")
	}
}

func TestImageToThumbnail_InvalidImage(t *testing.T) {
	tmpDir := t.TempDir()
	invalidFile := filepath.Join(tmpDir, "invalid.jpg")
	os.WriteFile(invalidFile, []byte("not an image"), 0644)

	_, _, err := ImageToThumbnail(invalidFile, 50, 50)
	if err == nil {
		t.Error("Expected error for invalid image file")
	}
}

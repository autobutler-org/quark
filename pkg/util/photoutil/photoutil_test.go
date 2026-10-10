package photoutil

import (
	"image"
	"image/color"
	_ "image/jpeg" // Import JPEG decoder
	"image/png"
	"os"
	"path/filepath"
	"testing"
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

func TestGenerateThumbnail_Crops(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "test.png")
	createTestImage(t, imagePath, 200, 200)

	result, err := GenerateThumbnail(GenerateThumbnailParams{FilePath: imagePath, Width: 50, Height: 50})
	if err != nil {
		t.Fatalf("GenerateThumbnail failed: %v", err)
	}
	thumbnail, format := result.Thumbnail, result.Format

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

func TestGenerateThumbnail_Crops_NonSquareLandscape(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "landscape.png")
	createTestImage(t, imagePath, 400, 200) // 2:1 landscape

	result, err := GenerateThumbnail(GenerateThumbnailParams{FilePath: imagePath, Width: 50, Height: 50})
	if err != nil {
		t.Fatalf("GenerateThumbnail failed: %v", err)
	}
	thumbnail := result.Thumbnail

	bounds := thumbnail.Bounds()
	if bounds.Dx() != 50 || bounds.Dy() != 50 {
		t.Errorf("Expected 50x50 thumbnail, got %dx%d (landscape input must be cropped, not squished)", bounds.Dx(), bounds.Dy())
	}
}

func TestGenerateThumbnail_Crops_NonSquarePortrait(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "portrait.png")
	createTestImage(t, imagePath, 200, 400) // 1:2 portrait

	result, err := GenerateThumbnail(GenerateThumbnailParams{FilePath: imagePath, Width: 50, Height: 50})
	if err != nil {
		t.Fatalf("GenerateThumbnail failed: %v", err)
	}
	thumbnail := result.Thumbnail

	bounds := thumbnail.Bounds()
	if bounds.Dx() != 50 || bounds.Dy() != 50 {
		t.Errorf("Expected 50x50 thumbnail, got %dx%d (portrait input must be cropped, not squished)", bounds.Dx(), bounds.Dy())
	}
}

func TestRotate90(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 3))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})

	rotated := applyExifOrientation(img, 6)
	bounds := rotated.Bounds()

	if bounds.Dx() != 3 || bounds.Dy() != 2 {
		t.Errorf("Expected 3x2, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestRotate180(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})

	rotated := applyExifOrientation(img, 3)
	bounds := rotated.Bounds()

	if bounds.Dx() != 2 || bounds.Dy() != 2 {
		t.Errorf("Expected 2x2, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestRotate270(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 3))

	rotated := applyExifOrientation(img, 8)
	bounds := rotated.Bounds()

	if bounds.Dx() != 3 || bounds.Dy() != 2 {
		t.Errorf("Expected 3x2, got %dx%d", bounds.Dx(), bounds.Dy())
	}
}

func TestFlipHorizontal(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})
	img.Set(1, 0, color.RGBA{0, 255, 0, 255})

	flipped := applyExifOrientation(img, 2)

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

	flipped := applyExifOrientation(img, 4)

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

func TestGenerateThumbnail_NonExistentFile(t *testing.T) {
	_, err := GenerateThumbnail(GenerateThumbnailParams{FilePath: "/nonexistent/file.jpg", Width: 50, Height: 50})
	if err == nil {
		t.Error("Expected error for non-existent file")
	}
}

func TestSortPhotos_ByAddedDefaultsNewestFirst(t *testing.T) {
	photos := []PhotoSummary{
		{FileName: "old.jpg", MTime: 100},
		{FileName: "new.jpg", MTime: 300},
		{FileName: "mid.jpg", MTime: 200},
	}
	sortPhotos(photos, "", "")
	want := []string{"new.jpg", "mid.jpg", "old.jpg"}
	for i, name := range want {
		if photos[i].FileName != name {
			t.Fatalf("got order %v, want %v", photoNames(photos), want)
		}
	}
}

func TestSortPhotos_ByAddedAscending(t *testing.T) {
	photos := []PhotoSummary{
		{FileName: "new.jpg", MTime: 300},
		{FileName: "old.jpg", MTime: 100},
		{FileName: "mid.jpg", MTime: 200},
	}
	sortPhotos(photos, SortAdded, OrderAsc)
	want := []string{"old.jpg", "mid.jpg", "new.jpg"}
	for i, name := range want {
		if photos[i].FileName != name {
			t.Fatalf("got order %v, want %v", photoNames(photos), want)
		}
	}
}

func TestSortPhotos_ByNameCaseInsensitive(t *testing.T) {
	photos := []PhotoSummary{
		{FileName: "Charlie.jpg"},
		{FileName: "alpha.jpg"},
		{FileName: "Bravo.jpg"},
	}
	sortPhotos(photos, SortName, OrderAsc)
	want := []string{"alpha.jpg", "Bravo.jpg", "Charlie.jpg"}
	for i, name := range want {
		if photos[i].FileName != name {
			t.Fatalf("got order %v, want %v", photoNames(photos), want)
		}
	}
}

func photoNames(photos []PhotoSummary) []string {
	names := make([]string, len(photos))
	for i, p := range photos {
		names[i] = p.FileName
	}
	return names
}

func TestGenerateThumbnail_InvalidImage(t *testing.T) {
	tmpDir := t.TempDir()
	invalidFile := filepath.Join(tmpDir, "invalid.jpg")
	os.WriteFile(invalidFile, []byte("not an image"), 0644)

	_, err := GenerateThumbnail(GenerateThumbnailParams{FilePath: invalidFile, Width: 50, Height: 50})
	if err == nil {
		t.Error("Expected error for invalid image file")
	}
}

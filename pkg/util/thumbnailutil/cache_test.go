package thumbnailutil

import (
	"image"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestCacheKey(t *testing.T) {
	// Same inputs should produce the same key
	key1 := CacheKey("serial1", "/photos/test.jpg", 0, SizeLg)
	key2 := CacheKey("serial1", "/photos/test.jpg", 0, SizeLg)
	if key1 != key2 {
		t.Errorf("CacheKey not deterministic: %s != %s", key1, key2)
	}

	// Different serial should produce a different key
	key3 := CacheKey("serial2", "/photos/test.jpg", 0, SizeLg)
	if key1 == key3 {
		t.Errorf("CacheKey collision on different serials: %s == %s", key1, key3)
	}

	// Different path should produce a different key
	key4 := CacheKey("serial1", "/photos/other.jpg", 0, SizeLg)
	if key1 == key4 {
		t.Errorf("CacheKey collision on different paths: %s == %s", key1, key4)
	}

	// Empty serial should work (default case)
	key5 := CacheKey("", "/photos/test.jpg", 0, SizeLg)
	if key5 == "" {
		t.Error("CacheKey returned empty string for empty serial")
	}
	if key5 == key1 {
		t.Errorf("CacheKey should differ for empty vs non-empty serial")
	}

	// Different rotation should produce a different key
	key6 := CacheKey("serial1", "/photos/test.jpg", 1, SizeLg)
	if key1 == key6 {
		t.Errorf("CacheKey collision on different rotation: %s == %s", key1, key6)
	}

	// Different size should produce a different key
	keySm := CacheKey("serial1", "/photos/test.jpg", 0, SizeSm)
	keyMd := CacheKey("serial1", "/photos/test.jpg", 0, SizeMd)
	if key1 == keySm {
		t.Errorf("CacheKey collision: lg == sm")
	}
	if key1 == keyMd {
		t.Errorf("CacheKey collision: lg == md")
	}
	if keySm == keyMd {
		t.Errorf("CacheKey collision: sm == md")
	}
}

func TestParseSize(t *testing.T) {
	tests := []struct {
		input    string
		expected Size
	}{
		{"sm", SizeSm},
		{"md", SizeMd},
		{"lg", SizeLg},
		{"", SizeLg},   // empty defaults to lg
		{"xl", SizeLg}, // unknown defaults to lg
	}
	for _, tt := range tests {
		got := ParseSize(tt.input)
		if got != tt.expected {
			t.Errorf("ParseSize(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestDimensions(t *testing.T) {
	tests := []struct {
		size Size
		w, h uint
	}{
		{SizeSm, 96, 96},
		{SizeMd, 240, 240},
		{SizeLg, 400, 400},
		{"unknown", 400, 400}, // unknown falls back to lg
	}
	for _, tt := range tests {
		w, h := Dimensions(tt.size)
		if w != tt.w || h != tt.h {
			t.Errorf("Dimensions(%q) = (%d, %d), want (%d, %d)", tt.size, w, h, tt.w, tt.h)
		}
	}
}

func TestETagFromModTime(t *testing.T) {
	now := time.Now()
	etag := ETagFromModTime(now)

	// Should be quoted
	if etag[0] != '"' || etag[len(etag)-1] != '"' {
		t.Errorf("ETag should be quoted, got: %s", etag)
	}

	// Same time should produce same etag
	etag2 := ETagFromModTime(now)
	if etag != etag2 {
		t.Errorf("ETagFromModTime not deterministic: %s != %s", etag, etag2)
	}

	// Different time should produce different etag
	etag3 := ETagFromModTime(now.Add(time.Second))
	if etag == etag3 {
		t.Errorf("ETagFromModTime collision on different times: %s == %s", etag, etag3)
	}
}

func TestContentTypeForExt(t *testing.T) {
	tests := []struct {
		ext      string
		expected string
	}{
		{".png", "image/png"},
		{".jpg", "image/jpeg"},
		{".jpeg", "image/jpeg"},
		{".webp", "image/jpeg"},
		{".gif", "image/jpeg"},
		{"", "image/jpeg"},
	}
	for _, tt := range tests {
		got := ContentTypeForExt(tt.ext)
		if got != tt.expected {
			t.Errorf("ContentTypeForExt(%q) = %q, want %q", tt.ext, got, tt.expected)
		}
	}
}

func TestCacheDir(t *testing.T) {
	// CacheDir should create the directory and return a valid path.
	// Skip if the data directory is not writable in this test environment.
	dir, err := CacheDir()
	if err != nil {
		t.Skipf("skipping: cannot create cache dir in test environment: %v", err)
	}

	info, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("cache directory does not exist: %v", err)
	}
	if !info.IsDir() {
		t.Fatalf("cache path is not a directory: %s", dir)
	}

	// Should end with the expected path suffix
	if filepath.Base(dir) != "thumbnails" {
		t.Errorf("cache directory should end with 'thumbnails', got: %s", dir)
	}
}

// Concurrent first requests for one thumbnail all generate it and commit the
// same entry. Sharing one temporary path made all but one of them fail.
func TestWriteCacheConcurrentSameEntry(t *testing.T) {
	cachedPath := filepath.Join(t.TempDir(), "entry")
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))

	const writers = 16
	errs := make([]error, writers)
	var wg sync.WaitGroup
	for i := range writers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, errs[i] = writeCache(cachedPath, img, false)
		}()
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Errorf("writer %d: %v", i, err)
		}
	}
	entries, err := os.ReadDir(filepath.Dir(cachedPath))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Errorf("cache dir holds %d files, want only the committed entry", len(entries))
	}
}

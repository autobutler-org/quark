// cspell:words thumbversionutil

package v0_thumbnails_test

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/thumbversionutil"
)

// TestGetThumbnail_VersionedIsImmutable: a thumbnail URL whose v names the
// photo's current version, <mtime>.<rotation>, is cacheable as immutable and
// private; one without v, or with a stale v, is answered exactly as before:
// no-cache, revalidated by ETag (#4217).
func TestGetThumbnail_VersionedIsImmutable(t *testing.T) {
	engine, dir, database := newThumbnailEngine(t, true)
	path := filepath.Join(dir, "red.png")
	if err := os.WriteFile(path, pngBytes(t), 0o644); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	mtime := info.ModTime().Unix()
	url := func(v string) string {
		if v == "" {
			return "/api/v0/thumbnails/red.png?size=sm"
		}
		return "/api/v0/thumbnails/red.png?size=sm&v=" + v
	}

	cases := []struct {
		name, v, want string
	}{
		{"unversioned", "", "no-cache"},
		{"current", fmt.Sprintf("%d.0", mtime), thumbversionutil.Immutable},
		{"stale mtime", fmt.Sprintf("%d.0", mtime-60), "no-cache"},
		{"stale rotation", fmt.Sprintf("%d.1", mtime), "no-cache"},
	}
	for _, tc := range cases {
		w := get(engine, url(tc.v))
		expectSmallPNG(t, w)
		if got := w.Header().Get("Cache-Control"); got != tc.want {
			t.Errorf("%s: Cache-Control = %q, want %q", tc.name, got, tc.want)
		}
		if w.Header().Get("ETag") == "" {
			t.Errorf("%s: no ETag", tc.name)
		}
	}
	if thumbversionutil.Immutable != "private, max-age=31536000, immutable" {
		t.Errorf("Immutable = %q: a shared cache must never store a thumbnail", thumbversionutil.Immutable)
	}

	// An unversioned revalidation still gets its 304.
	first := get(engine, url(""))
	req := httptest.NewRequest(http.MethodGet, url(""), nil)
	req.Header.Set("If-None-Match", first.Header().Get("ETag"))
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	if w.Code != http.StatusNotModified || w.Header().Get("Cache-Control") != "no-cache" {
		t.Errorf("revalidation = %d %q, want 304 no-cache", w.Code, w.Header().Get("Cache-Control"))
	}

	// A rotation moves the version: the old v goes stale, the new one is current.
	if err := database.Queries.UpsertPhotoRotation(context.Background(), db.UpsertPhotoRotationParams{
		RelPath: "red.png", RotationQuarters: 1,
	}); err != nil {
		t.Fatal(err)
	}
	if got := get(engine, url(fmt.Sprintf("%d.0", mtime))).Header().Get("Cache-Control"); got != "no-cache" {
		t.Errorf("pre-rotation v after rotating: Cache-Control = %q, want no-cache", got)
	}
	if got := get(engine, url(fmt.Sprintf("%d.1", mtime))).Header().Get("Cache-Control"); got != thumbversionutil.Immutable {
		t.Errorf("rotated v: Cache-Control = %q, want immutable", got)
	}
}

// TestGetThumbnail_ArchiveEntryNeverImmutable: an archive entry has no version
// a client could name, so even a v gets no-cache.
func TestGetThumbnail_ArchiveEntryNeverImmutable(t *testing.T) {
	engine, dir, _ := newThumbnailEngine(t, true)
	writeZipWithPNG(t, dir)
	w := get(engine, "/api/v0/thumbnails/photos.zip/pics/red.png?size=sm&v=0.0")
	expectSmallPNG(t, w)
	if got := w.Header().Get("Cache-Control"); got != "no-cache" {
		t.Errorf("Cache-Control = %q, want no-cache", got)
	}
}

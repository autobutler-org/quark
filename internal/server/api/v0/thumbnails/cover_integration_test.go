package v0_thumbnails_test

import (
	"bytes"
	"context"
	"encoding/binary"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// flacWithCover is a short FLAC file embedding picture as its front cover,
// or no picture when it is nil.
func flacWithCover(picture []byte) []byte {
	cat := func(parts ...[]byte) []byte { return bytes.Join(parts, nil) }
	be32 := func(n uint32) []byte { return binary.BigEndian.AppendUint32(nil, n) }
	block := func(typ byte, last bool, body []byte) []byte {
		if last {
			typ |= 0x80
		}
		return cat([]byte{typ, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}, body)
	}
	const rate = 44100
	info := make([]byte, 34)
	binary.BigEndian.PutUint64(info[10:18], uint64(rate)<<44|uint64(1)<<41|uint64(15)<<36|10*rate)
	out := cat([]byte("fLaC"), block(0, picture == nil, info))
	if picture != nil {
		mime := "image/jpeg"
		pic := cat(be32(3), be32(uint32(len(mime))), []byte(mime), be32(0), make([]byte, 16), be32(uint32(len(picture))), picture)
		out = cat(out, block(6, true, pic))
	}
	return append(out, make([]byte, 64)...)
}

// coverJPEG is a 200x200 JPEG.
func coverJPEG(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 200, 200)), nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// writeTracks writes each track into the internal drive and indexes it into
// the music library.
func (h thumbnailHarness) writeTracks(t *testing.T, tracks map[string][]byte) {
	t.Helper()
	fsys, err := vfs.NewLocalVFS(h.filesDir, vfs.FilesNamespace(""))
	if err != nil {
		t.Fatal(err)
	}
	for rel, data := range tracks {
		full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, data, 0o644); err != nil {
			t.Fatal(err)
		}
		if _, err := musicutil.IndexTrack(musicutil.IndexTrackParams{
			Ctx: context.Background(), DB: h.database.Db, FS: fsys, RelPath: rel,
		}); err != nil {
			t.Fatalf("index %s: %v", rel, err)
		}
	}
}

// TestGetThumbnail_TrackCover: a track's thumbnail is its cover art, a JPEG
// at the requested size, and a track with none is a 404 the client draws a
// placeholder for.
func TestGetThumbnail_TrackCover(t *testing.T) {
	h := newThumbnailHarness(t)
	h.writeTracks(t, map[string][]byte{
		"Album/01.flac":   flacWithCover(coverJPEG(t)),
		"Album/bare.flac": flacWithCover(nil),
	})

	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/thumbnails/Album/01.flac?size=sm", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("cover: got %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/jpeg" {
		t.Errorf("Content-Type = %q, want image/jpeg", ct)
	}
	cfg, err := jpeg.DecodeConfig(w.Body)
	if err != nil {
		t.Fatalf("body is not a JPEG: %v", err)
	}
	if cfg.Width != 96 || cfg.Height != 96 {
		t.Errorf("cover is %dx%d, want 96x96", cfg.Width, cfg.Height)
	}

	if code := h.get("/api/v0/thumbnails/Album/bare.flac"); code != http.StatusNotFound {
		t.Errorf("track without a cover: got %d, want 404", code)
	}
	if code := h.get("/api/v0/thumbnails/Album/missing.flac"); code != http.StatusNotFound {
		t.Errorf("missing track: got %d, want 404", code)
	}
}

// TestThumbnailAccess_SharedCover: two tracks share one cached cover, and a
// user who may read only one of them gets the cover of that one alone. The
// shared cache entry leaks nothing because access is checked on the track.
func TestThumbnailAccess_SharedCover(t *testing.T) {
	h := newThumbnailHarness(t)
	art := coverJPEG(t)
	h.writeTracks(t, map[string][]byte{
		"Shared/01.flac":  flacWithCover(art),
		"Private/02.flac": flacWithCover(art),
	})
	h.grantRead(t, "Shared")

	// The admin warms the shared entry through the track the user cannot read.
	if code := h.get("/api/v0/thumbnails/Private/02.flac"); code != http.StatusOK {
		t.Fatalf("admin: got %d, want 200", code)
	}

	h.asUser()
	if code := h.get("/api/v0/thumbnails/Private/02.flac"); code != http.StatusNotFound {
		t.Errorf("unreadable track: got %d, want 404", code)
	}
	if code := h.get("/api/v0/thumbnails/Shared/01.flac"); code != http.StatusOK {
		t.Errorf("readable track: got %d, want 200", code)
	}
}

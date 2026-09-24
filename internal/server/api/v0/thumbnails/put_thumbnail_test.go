package v0_thumbnails_test

import (
	"bytes"
	"context"
	"database/sql"
	"image"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func jpegOf(t *testing.T, w, h int) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, w, h)), nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// derivativesBody builds the multipart body PUT /thumbnails takes: one part
// per derivative, named for its kind.
func derivativesBody(t *testing.T, parts map[string][]byte) (*bytes.Buffer, string) {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	for name, data := range parts {
		w, err := mw.CreateFormFile(name, name+".jpg")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(data); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return &body, mw.FormDataContentType()
}

func (h thumbnailHarness) put(t *testing.T, path string, parts map[string][]byte) *httptest.ResponseRecorder {
	t.Helper()
	body, contentType := derivativesBody(t, parts)
	req := httptest.NewRequest(http.MethodPut, path, body)
	req.Header.Set("Content-Type", contentType)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func (h thumbnailHarness) do(path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w
}

func (h thumbnailHarness) grant(t *testing.T, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: rel,
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

// writeUndecodable writes a media file the device cannot render, so any
// thumbnail served for it came from what the client uploaded.
func writeUndecodable(t *testing.T, filesDir, rel string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte("not decodable here"), 0o600); err != nil {
		t.Fatal(err)
	}
}

func expectJPEG(t *testing.T, w *httptest.ResponseRecorder, width, height int) {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("got %d, want 200: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/jpeg" {
		t.Errorf("Content-Type = %q, want image/jpeg", ct)
	}
	cfg, err := jpeg.DecodeConfig(w.Body)
	if err != nil {
		t.Fatalf("body is not a JPEG: %v", err)
	}
	if cfg.Width != width || cfg.Height != height {
		t.Errorf("got %dx%d, want %dx%d", cfg.Width, cfg.Height, width, height)
	}
}

// TestPutThumbnail_ServesStoredDerivatives covers the client path: a video and
// a HEIC the device cannot decode get the thumbnail and preview their client
// uploaded, down both serving branches.
func TestPutThumbnail_ServesStoredDerivatives(t *testing.T) {
	for _, withVFS := range []bool{true, false} {
		for _, rel := range []string{"clips/clip.mov", "photos/photo.heic"} {
			h := newThumbnailHarness(t, withVFS)
			writeUndecodable(t, h.filesDir, rel)

			w := h.put(t, "/api/v0/thumbnails/"+rel, map[string][]byte{
				"thumbnail": jpegOf(t, 400, 300),
				"preview":   jpegOf(t, 2048, 1536),
			})
			if w.Code != http.StatusOK {
				t.Fatalf("withVFS=%v PUT %s = %d: %s", withVFS, rel, w.Code, w.Body.String())
			}

			expectJPEG(t, h.do("/api/v0/thumbnails/"+rel+"?size=sm"), 96, 96)
			expectJPEG(t, h.do("/api/v0/thumbnails/"+rel+"?size=lg"), 400, 400)
			expectJPEG(t, h.do("/api/v0/thumbnails/"+rel+"?size=preview"), 2048, 1536)
		}
	}
}

// TestGetThumbnail_PreviewWithoutStoredOneIsNotFound: nothing generates a
// preview on the device, so a file without one is a 404 and the viewer
// offers the original instead.
func TestGetThumbnail_PreviewWithoutStoredOneIsNotFound(t *testing.T) {
	h := newThumbnailHarness(t, false)
	writeJPEG(t, h.filesDir, "a.jpg")
	if w := h.do("/api/v0/thumbnails/a.jpg?size=preview"); w.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404", w.Code)
	}
}

func TestPutThumbnail_Rejections(t *testing.T) {
	h := newThumbnailHarness(t, false)
	writeUndecodable(t, h.filesDir, "clip.mov")
	writeUndecodable(t, h.filesDir, "notes.txt")
	valid := map[string][]byte{"thumbnail": jpegOf(t, 400, 300)}

	for name, tc := range map[string]struct {
		path  string
		parts map[string][]byte
		want  int
	}{
		"not a jpeg":      {"/api/v0/thumbnails/clip.mov", map[string][]byte{"thumbnail": []byte("nope")}, http.StatusBadRequest},
		"too large":       {"/api/v0/thumbnails/clip.mov", map[string][]byte{"thumbnail": jpegOf(t, 3000, 2000)}, http.StatusBadRequest},
		"no derivatives":  {"/api/v0/thumbnails/clip.mov", map[string][]byte{"other": jpegOf(t, 4, 4)}, http.StatusBadRequest},
		"not media":       {"/api/v0/thumbnails/notes.txt", valid, http.StatusBadRequest},
		"missing file":    {"/api/v0/thumbnails/gone.mov", valid, http.StatusNotFound},
		"escapes the dir": {"/api/v0/thumbnails/../clip.mov", valid, http.StatusNotFound},
	} {
		t.Run(name, func(t *testing.T) {
			if w := h.put(t, tc.path, tc.parts); w.Code != tc.want {
				t.Errorf("got %d, want %d: %s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}

func TestPutThumbnail_NeedsWriteAccess(t *testing.T) {
	h := newThumbnailHarness(t, false)
	writeUndecodable(t, h.filesDir, "shared/clip.mov")
	parts := map[string][]byte{"thumbnail": jpegOf(t, 400, 300)}
	h.asUser()

	if w := h.put(t, "/api/v0/thumbnails/shared/clip.mov", parts); w.Code != http.StatusNotFound {
		t.Errorf("no access: got %d, want 404", w.Code)
	}
	h.grant(t, "shared", accessutil.Read)
	if w := h.put(t, "/api/v0/thumbnails/shared/clip.mov", parts); w.Code != http.StatusForbidden {
		t.Errorf("read only: got %d, want 403", w.Code)
	}
	h.grant(t, "shared", accessutil.Write)
	if w := h.put(t, "/api/v0/thumbnails/shared/clip.mov", parts); w.Code != http.StatusOK {
		t.Errorf("writable: got %d, want 200: %s", w.Code, w.Body.String())
	}
}

// TestGetThumbnail_StoredDerivativeFollowsFileIntoTrash: the Trash page asks
// for a trashed item's TrashPath, and a video's stored thumbnail went into the
// trash with it.
func TestGetThumbnail_StoredDerivativeFollowsFileIntoTrash(t *testing.T) {
	h := newThumbnailHarness(t, false)
	writeUndecodable(t, h.filesDir, "clip.mov")
	if w := h.put(t, "/api/v0/thumbnails/clip.mov", map[string][]byte{"thumbnail": jpegOf(t, 400, 300)}); w.Code != http.StatusOK {
		t.Fatalf("PUT = %d: %s", w.Code, w.Body.String())
	}
	result, err := storageutil.TrashFilesImpl(storageutil.TrashFilesParams{FilePaths: []string{"clip.mov"}}, h.filesDir)
	if err != nil || len(result.Trashed) != 1 {
		t.Fatalf("trashing clip.mov: %v, %+v", err, result)
	}
	expectJPEG(t, h.do("/api/v0/thumbnails/"+storageutil.TrashPath(result.Trashed[0].TrashName, "")+"?size=sm"), 96, 96)
}

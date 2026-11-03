package v0_photos_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

func orientationOnDisk(t *testing.T, path string) int {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	return photoutil.GetOrientation(f, photoutil.ImageFormatFromPath(path))
}

func TestRotatePhoto_TurnsTheFileTwiceOverAndTheMetadataHasNoRotation(t *testing.T) {
	h := newPhotoHarness(t)
	disk := filepath.Join(h.filesDir, "shared", "a.jpg")

	for _, want := range []int{6, 3} {
		w := h.do(http.MethodPost, "/api/v0/photos/rotate", `{"relPath":"shared/a.jpg","quarters":1}`)
		if w.Code != http.StatusOK {
			t.Fatalf("rotate = %d: %s", w.Code, w.Body.String())
		}
		var body struct {
			Orientation int `json:"orientation"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body.Orientation != want {
			t.Errorf("response = %s (%v), want orientation %d", w.Body.String(), err, want)
		}
		if got := orientationOnDisk(t, disk); got != want {
			t.Errorf("file orientation = %d, want %d", got, want)
		}
	}

	w := h.do(http.MethodGet, "/api/v0/photos/metadata?relPath=shared/a.jpg", "")
	var meta map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &meta); err != nil {
		t.Fatal(err)
	}
	if _, has := meta["rotationQuarters"]; has {
		t.Error("metadata still reports rotationQuarters")
	}
}

func TestRotatePhoto_UnsupportedFormatIs422(t *testing.T) {
	h := newPhotoHarness(t)
	if err := os.WriteFile(filepath.Join(h.filesDir, "shared", "p.png"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if w := h.do(http.MethodPost, "/api/v0/photos/rotate", `{"relPath":"shared/p.png","quarters":1}`); w.Code != http.StatusUnprocessableEntity {
		t.Errorf("rotate png = %d, want 422: %s", w.Code, w.Body.String())
	}
}

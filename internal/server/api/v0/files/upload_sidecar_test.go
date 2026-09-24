package v0_files_test

import (
	"bytes"
	"image"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/gin-gonic/gin"
)

// uploadPart is one part of a multipart upload body.
type uploadPart struct {
	form, name string
	data       []byte
}

func uploadParts(t *testing.T, engine *gin.Engine, path string, parts ...uploadPart) int {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for _, p := range parts {
		w, err := mw.CreateFormFile(p.form, p.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write(p.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return doRequest(engine, http.MethodPost, path, &buf, mw.FormDataContentType()).Code
}

func sidecarJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, w, h)), nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func hasDerivative(filesDir, rel string, kind derivativeutil.Kind) bool {
	_, err := os.Stat(derivativeutil.Path(filepath.Join(filesDir, filepath.FromSlash(rel)), kind))
	return err == nil
}

// sidecarEngines are the two multipart writers: the VFS for the internal
// device, and the StorageService for everything the VFS does not cover.
func sidecarEngines(t *testing.T) map[string]func() (*gin.Engine, string) {
	return map[string]func() (*gin.Engine, string){
		"vfs": func() (*gin.Engine, string) {
			deps, filesDir := newStorageVFSDeps(t)
			return newEngineForDeps(deps.WithDatabase(dbtest.NewDB(t))), filesDir
		},
		"storage service": func() (*gin.Engine, string) {
			deps, filesDir := newStorageVFSDeps(t)
			return newEngineForDeps(deps.WithVFSRegistry(nil).WithDatabase(dbtest.NewDB(t))), filesDir
		},
	}
}

// TestUploadWithSidecars: a client sends each file's thumbnail and preview
// right after it, as parts named for the kind whose filename names the file.
func TestUploadWithSidecars(t *testing.T) {
	for name, build := range sidecarEngines(t) {
		t.Run(name, func(t *testing.T) {
			engine, filesDir := build()
			code := uploadParts(t, engine, "/api/v0/files/upload/album",
				uploadPart{"files", "clip.mov", []byte("video")},
				uploadPart{"thumbnail", "clip.mov", sidecarJPEG(t, 400, 225)},
				uploadPart{"preview", "clip.mov", sidecarJPEG(t, 2048, 1152)},
				uploadPart{"files", "photo.heic", []byte("heic")},
				uploadPart{"thumbnail", "photo.heic", sidecarJPEG(t, 300, 400)},
				uploadPart{"files", "notes.txt", []byte("text")},
			)
			if code != http.StatusOK {
				t.Fatalf("upload = %d", code)
			}
			for _, want := range []struct {
				rel  string
				kind derivativeutil.Kind
				has  bool
			}{
				{"album/clip.mov", derivativeutil.KindThumbnail, true},
				{"album/clip.mov", derivativeutil.KindPreview, true},
				{"album/photo.heic", derivativeutil.KindThumbnail, true},
				{"album/photo.heic", derivativeutil.KindPreview, false},
				{"album/notes.txt", derivativeutil.KindThumbnail, false},
			} {
				if got := hasDerivative(filesDir, want.rel, want.kind); got != want.has {
					t.Errorf("%s %s stored = %v, want %v", want.rel, want.kind, got, want.has)
				}
			}
		})
	}
}

// TestUploadSidecarFollowsKeepBothRename: the sidecar names the file as the
// client sent it, and lands on wherever keepBoth put it.
func TestUploadSidecarFollowsKeepBothRename(t *testing.T) {
	for name, build := range sidecarEngines(t) {
		t.Run(name, func(t *testing.T) {
			engine, filesDir := build()
			writeFixture(t, filesDir, "clip.mov")
			code := uploadParts(t, engine, "/api/v0/files/upload?keepBoth=true",
				uploadPart{"files", "clip.mov", []byte("video")},
				uploadPart{"thumbnail", "clip.mov", sidecarJPEG(t, 400, 225)},
			)
			if code != http.StatusOK {
				t.Fatalf("upload = %d", code)
			}
			if hasDerivative(filesDir, "clip.mov", derivativeutil.KindThumbnail) {
				t.Error("the thumbnail landed on the file that was already there")
			}
			entries, err := os.ReadDir(filepath.Join(filesDir, derivativeutil.DirName))
			if err != nil || len(entries) != 1 || entries[0].Name() == "clip.mov" {
				t.Errorf("want the renamed upload's thumbnail alone, got %v (%v)", entries, err)
			}
		})
	}
}

// TestUploadIgnoresUnpairedOrBadSidecars: an older client sends none, a
// confused one sends them for a file not in the upload or not a JPEG; the
// files land either way.
func TestUploadIgnoresUnpairedOrBadSidecars(t *testing.T) {
	for name, build := range sidecarEngines(t) {
		t.Run(name, func(t *testing.T) {
			engine, filesDir := build()
			code := uploadParts(t, engine, "/api/v0/files/upload",
				uploadPart{"thumbnail", "early.mov", sidecarJPEG(t, 400, 225)},
				uploadPart{"files", "early.mov", []byte("video")},
				uploadPart{"files", "bad.mov", []byte("video")},
				uploadPart{"thumbnail", "bad.mov", []byte("not a jpeg")},
				uploadPart{"thumbnail", "absent.mov", sidecarJPEG(t, 400, 225)},
			)
			if code != http.StatusOK {
				t.Fatalf("upload = %d", code)
			}
			for _, rel := range []string{"early.mov", "bad.mov"} {
				assertFileExists(t, filepath.Join(filesDir, rel))
				if hasDerivative(filesDir, rel, derivativeutil.KindThumbnail) {
					t.Errorf("%s got a thumbnail it should not have", rel)
				}
			}
		})
	}
}

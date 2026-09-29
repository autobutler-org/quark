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

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
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

// sidecarEnv is an upload engine over a real files directory, with the
// thumbnail cache kept inside the test.
type sidecarEnv struct {
	engine   *gin.Engine
	filesDir string
	database *db.DatabaseSqlc
}

// hasThumbnail reports whether the file at rel has a client thumbnail to
// serve its tiers from.
func (e sidecarEnv) hasThumbnail(t *testing.T, rel string) bool {
	t.Helper()
	info, err := os.Stat(filepath.Join(e.filesDir, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatalf("%s did not land: %v", rel, err)
	}
	result, err := thumbnailutil.FromClientThumbnail(thumbnailutil.FromClientThumbnailParams{
		Queries: e.database.Queries, RelPath: rel, FilePath: "/" + rel,
		SourceModTime: info.ModTime(), Size: thumbnailutil.SizeSm,
	})
	if err != nil {
		t.Fatal(err)
	}
	return result.Found
}

// sidecarEnvs are the two multipart writers: the VFS for the internal
// device, and the StorageService for everything the VFS does not cover.
func sidecarEnvs(t *testing.T) map[string]func() sidecarEnv {
	build := func(withVFS bool) sidecarEnv {
		t.Setenv("HOME", t.TempDir())
		deps, filesDir := newStorageVFSDeps(t)
		if !withVFS {
			deps = deps.WithVFSRegistry(nil)
		}
		database := dbtest.NewDB(t)
		return sidecarEnv{engine: newEngineForDeps(deps.WithDatabase(database)), filesDir: filesDir, database: database}
	}
	return map[string]func() sidecarEnv{
		"vfs":             func() sidecarEnv { return build(true) },
		"storage service": func() sidecarEnv { return build(false) },
	}
}

// TestUploadWithThumbnails: a client sends each file's thumbnail right after
// it, as a part named thumbnail whose filename names the file.
func TestUploadWithThumbnails(t *testing.T) {
	for name, build := range sidecarEnvs(t) {
		t.Run(name, func(t *testing.T) {
			env := build()
			code := uploadParts(t, env.engine, "/api/v0/files/upload/album",
				uploadPart{"files", "clip.mov", []byte("video")},
				uploadPart{"thumbnail", "clip.mov", sidecarJPEG(t, 400, 225)},
				uploadPart{"files", "photo.heic", []byte("heic")},
				uploadPart{"thumbnail", "photo.heic", sidecarJPEG(t, 300, 400)},
				uploadPart{"files", "notes.txt", []byte("text")},
				uploadPart{"thumbnail", "notes.txt", sidecarJPEG(t, 300, 400)},
			)
			if code != http.StatusOK {
				t.Fatalf("upload = %d", code)
			}
			for rel, want := range map[string]bool{
				"album/clip.mov":   true,
				"album/photo.heic": true,
				"album/notes.txt":  false,
			} {
				if got := env.hasThumbnail(t, rel); got != want {
					t.Errorf("%s thumbnail stored = %v, want %v", rel, got, want)
				}
			}
		})
	}
}

// TestUploadThumbnailFollowsKeepBothRename: the thumbnail names the file as
// the client sent it, and lands on wherever keepBoth put it.
func TestUploadThumbnailFollowsKeepBothRename(t *testing.T) {
	for name, build := range sidecarEnvs(t) {
		t.Run(name, func(t *testing.T) {
			env := build()
			writeFixture(t, env.filesDir, "clip.mov")
			code := uploadParts(t, env.engine, "/api/v0/files/upload?keepBoth=true",
				uploadPart{"files", "clip.mov", []byte("video")},
				uploadPart{"thumbnail", "clip.mov", sidecarJPEG(t, 400, 225)},
			)
			if code != http.StatusOK {
				t.Fatalf("upload = %d", code)
			}
			if env.hasThumbnail(t, "clip.mov") {
				t.Error("the thumbnail landed on the file that was already there")
			}
			if !env.hasThumbnail(t, "clip_(1).mov") {
				t.Error("the renamed upload has no thumbnail")
			}
		})
	}
}

// TestUploadIgnoresUnpairedOrBadThumbnails: an older client sends none, a
// confused one sends them for a file not in the upload or not a JPEG, or a
// preview this server does not take; the files land either way.
func TestUploadIgnoresUnpairedOrBadThumbnails(t *testing.T) {
	for name, build := range sidecarEnvs(t) {
		t.Run(name, func(t *testing.T) {
			env := build()
			code := uploadParts(t, env.engine, "/api/v0/files/upload",
				uploadPart{"thumbnail", "early.mov", sidecarJPEG(t, 400, 225)},
				uploadPart{"files", "early.mov", []byte("video")},
				uploadPart{"files", "bad.mov", []byte("video")},
				uploadPart{"thumbnail", "bad.mov", []byte("not a jpeg")},
				uploadPart{"files", "other.mov", []byte("video")},
				uploadPart{"preview", "other.mov", sidecarJPEG(t, 400, 225)},
				uploadPart{"thumbnail", "absent.mov", sidecarJPEG(t, 400, 225)},
			)
			if code != http.StatusOK {
				t.Fatalf("upload = %d", code)
			}
			for _, rel := range []string{"early.mov", "bad.mov", "other.mov"} {
				if env.hasThumbnail(t, rel) {
					t.Errorf("%s got a thumbnail it should not have", rel)
				}
			}
		})
	}
}

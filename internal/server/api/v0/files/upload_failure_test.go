package v0_files_test

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"testing"
)

// uploadFailure is the body of a batch upload that stopped partway: the
// error, and the files-relative path of every file that landed before it
// (#3533), so a client resends only the rest.
type uploadFailure struct {
	Error  string   `json:"error"`
	Landed []string `json:"landed"`
}

func decodeUploadFailure(t *testing.T, w *httptest.ResponseRecorder) uploadFailure {
	t.Helper()
	var got uploadFailure
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode upload failure: %v\nbody: %s", err, w.Body.String())
	}
	if got.Error == "" {
		t.Errorf("failure body carries no error: %s", w.Body.String())
	}
	return got
}

// A name clash partway through a batch is a 409 that names the files before
// it, which landed, and not the clash or anything after it, which did not.
func TestUploadConflictReportsLandedFiles(t *testing.T) {
	t.Parallel()

	for _, eng := range uploadTargets {
		t.Run(eng.name, func(t *testing.T) {
			t.Parallel()
			e, filesDir := eng.engine(t)
			if w := uploadFile(t, e, eng.on("/api/v0/files/upload/notes"), "b.txt", "original"); w.Code != http.StatusOK {
				t.Fatalf("first upload returned %d: %s", w.Code, w.Body.String())
			}
			w := postUpload(t, e, eng.on("/api/v0/files/upload/notes"), func(t *testing.T, mw *multipart.Writer) {
				writeUploadPart(t, mw, "files", "a.txt", "a")
				writeUploadPart(t, mw, "files", "b.txt", "b")
				writeUploadPart(t, mw, "files", "c.txt", "c")
			})
			if w.Code != http.StatusConflict {
				t.Fatalf("batch returned %d, want 409: %s", w.Code, w.Body.String())
			}
			if got := decodeUploadFailure(t, w).Landed; !slices.Equal(got, []string{"notes/a.txt"}) {
				t.Fatalf("landed = %v, want [notes/a.txt]", got)
			}
			assertContents(t, filepath.Join(filesDir, "notes"), map[string]string{
				"a.txt": "a", "b.txt": "original", "c.txt": "",
			})
		})
	}
}

// A body cut off mid-file is a 400 that names the files that arrived whole.
func TestUploadCutBodyReportsLandedFiles(t *testing.T) {
	t.Parallel()

	for _, eng := range uploadTargets {
		t.Run(eng.name, func(t *testing.T) {
			t.Parallel()
			e, filesDir := eng.engine(t)
			var buf bytes.Buffer
			mw := multipart.NewWriter(&buf)
			writeUploadPart(t, mw, "files", "a.txt", "first file")
			writeUploadPart(t, mw, "files", "b.txt", "second file")
			writeUploadPart(t, mw, "files", "c.txt", "third file, cut off")
			if err := mw.Close(); err != nil {
				t.Fatal(err)
			}
			at := bytes.Index(buf.Bytes(), []byte("third file"))
			if at < 0 {
				t.Fatal("c.txt not found in the request body")
			}
			cut := io.LimitReader(&buf, int64(at+5))

			w := doRequest(e, http.MethodPost, eng.on("/api/v0/files/upload/notes"), cut, mw.FormDataContentType())
			if w.Code != http.StatusBadRequest {
				t.Fatalf("cut batch returned %d, want 400: %s", w.Code, w.Body.String())
			}
			if got := decodeUploadFailure(t, w).Landed; !slices.Equal(got, []string{"notes/a.txt", "notes/b.txt"}) {
				t.Fatalf("landed = %v, want [notes/a.txt notes/b.txt]", got)
			}
			assertContents(t, filepath.Join(filesDir, "notes"), map[string]string{
				"a.txt": "first file", "b.txt": "second file", "c.txt": "",
			})
		})
	}
}

// A batch that fails before anything lands still answers with an empty
// list, so a client reads one shape.
func TestUploadFailureBeforeAnyFileReportsNoneLanded(t *testing.T) {
	t.Parallel()

	e, _ := newStorageVFSTestEngine(t)
	if w := uploadFile(t, e, "/api/v0/files/upload/notes", "a.txt", "original"); w.Code != http.StatusOK {
		t.Fatalf("first upload returned %d: %s", w.Code, w.Body.String())
	}
	w := uploadFile(t, e, "/api/v0/files/upload/notes", "a.txt", "again")
	if w.Code != http.StatusConflict {
		t.Fatalf("upload returned %d, want 409: %s", w.Code, w.Body.String())
	}
	got := decodeUploadFailure(t, w)
	if got.Landed == nil || len(got.Landed) != 0 {
		t.Fatalf("landed = %#v, want []", got.Landed)
	}
}

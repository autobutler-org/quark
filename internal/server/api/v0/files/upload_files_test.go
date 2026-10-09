package v0_files_test

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// A directory smuggled into the multipart filename is dropped: the upload
// lands at the upload root under the filename's basename. Two layers enforce
// that — multipart.Part.FileName() already applies filepath.Base per RFC 7578
// §4.2, and the handler applies it again — so removing either one on its own
// does not change the behavior these tests assert.
//
// That silent flattening is what made "New Document" 404: the frontend sent
// "notes/meeting.qdoc" as the filename and then navigated to /docs/notes/
// meeting.qdoc, while the file was written to the root as meeting.qdoc
// (#1603). The fix is client-side — a "/" is now rejected in the New Document
// / New Spreadsheet dialog — so what these tests pin is the backend half of
// the invariant: for a flat name, the path the caller navigates to and the
// path the backend writes are the same string, and a name that is not flat
// never silently becomes one somewhere else.
func TestUploadStripsDirectoryFromFileName(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name     string
		uploaded string
		want     string
		wantGone string
	}{
		{
			name:     "nested name flattens to its basename",
			uploaded: "notes/meeting.qdoc",
			want:     "meeting.qdoc",
			wantGone: "notes",
		},
		{
			name:     "traversal cannot escape the upload root",
			uploaded: "../../escape.qdoc",
			want:     "escape.qdoc",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name+" (storage service)", func(t *testing.T) {
			t.Parallel()
			e, filesDir := newTestEngine(t)
			assertUploadLandsAt(t, e, filesDir, tc.uploaded, tc.want, tc.wantGone)
		})
		t.Run(tc.name+" (vfs)", func(t *testing.T) {
			t.Parallel()
			e, filesDir := newStorageVFSTestEngine(t)
			assertUploadLandsAt(t, e, filesDir, tc.uploaded, tc.want, tc.wantGone)
		})
	}
}

// TestUploadIntoNestedRootDirKeepsTheDirectory is the other half: a directory
// passed as the upload path (not smuggled into the filename) is honored, and
// the file is reachable at rootDir/basename. This is the shape option (a) of
// #1603 would build on if creating docs in subfolders is ever wanted.
func TestUploadIntoNestedRootDirKeepsTheDirectory(t *testing.T) {
	t.Parallel()

	e, filesDir := newStorageVFSTestEngine(t)
	w := uploadFile(t, e, "/api/v0/files/upload/notes", "meeting.qdoc", "{}")
	if w.Code != http.StatusOK {
		t.Fatalf("upload returned %d: %s", w.Code, w.Body.String())
	}
	assertFileExists(t, filepath.Join(filesDir, "notes", "meeting.qdoc"))
}

func assertUploadLandsAt(
	t *testing.T,
	e *gin.Engine,
	filesDir, uploaded, want, wantGone string,
) {
	t.Helper()

	w := uploadFile(t, e, "/api/v0/files/upload", uploaded, "{}")
	if w.Code != http.StatusOK {
		t.Fatalf("upload of %q returned %d: %s", uploaded, w.Code, w.Body.String())
	}

	assertFileExists(t, filepath.Join(filesDir, want))

	if wantGone != "" {
		gone := filepath.Join(filesDir, wantGone)
		if _, err := os.Stat(gone); err == nil {
			t.Fatalf("upload of %q created %s; the directory should have been stripped", uploaded, gone)
		}
	}

	// Nothing may be written above the upload root.
	outside := filepath.Join(filepath.Dir(filesDir), want)
	if _, err := os.Stat(outside); err == nil {
		t.Fatalf("upload of %q escaped the upload root to %s", uploaded, outside)
	}
}

func assertFileExists(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("expected a file at %s: %v", path, err)
	}
}

// The client uploads several files at once now, and a folder upload sends a
// whole directory's worth concurrently to the same nested rootDir. Each
// request calls MkdirAll on that directory before writing, so they race on
// creating it. os.MkdirAll tolerates the directory already existing, but that
// is the kind of thing worth holding still rather than assuming.
func TestConcurrentUploadsIntoTheSameNestedDir(t *testing.T) {
	t.Parallel()

	const workers = 8

	for _, tc := range []struct {
		name   string
		engine func(t *testing.T) (*gin.Engine, string)
	}{
		{name: "storage service", engine: newTestEngine},
		{name: "vfs", engine: newStorageVFSTestEngine},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			e, filesDir := tc.engine(t)

			var wg sync.WaitGroup
			codes := make([]int, workers)
			for i := range workers {
				wg.Add(1)
				go func() {
					defer wg.Done()
					name := fmt.Sprintf("file%d.txt", i)
					w := uploadFile(t, e, "/api/v0/files/upload/notes/2024", name, name)
					codes[i] = w.Code
				}()
			}
			wg.Wait()

			for i, code := range codes {
				if code != http.StatusOK {
					t.Errorf("upload %d returned %d, want %d", i, code, http.StatusOK)
				}
			}

			// Every file is present, in the one directory they all created.
			for i := range workers {
				assertFileExists(t, filepath.Join(filesDir, "notes", "2024", fmt.Sprintf("file%d.txt", i)))
			}
		})
	}
}

// Saving over an editor document snapshots what it replaces first (#1173),
// so the history holds the state the save overwrote. Any other file is
// overwritten without one, and a new document has nothing to snapshot.
func TestUploadOverwriteSnapshotsEditorDocuments(t *testing.T) {
	t.Parallel()
	e, filesDir := newStorageVFSTestEngine(t)
	for _, name := range []string{"deck.qslide", "notes.txt"} {
		if w := uploadFile(t, e, "/api/v0/files/upload/docs", name, "first"); w.Code != http.StatusOK {
			t.Fatalf("upload %s returned %d: %s", name, w.Code, w.Body.String())
		}
		if w := uploadFile(t, e, "/api/v0/files/upload/docs?overwrite=true", name, "second"); w.Code != http.StatusOK {
			t.Fatalf("overwrite %s returned %d: %s", name, w.Code, w.Body.String())
		}
	}
	store := filepath.Join(filesDir, "docs", storageutil.VersionsDirName)
	snaps, err := filepath.Glob(filepath.Join(store, "deck.qslide", "*.snap"))
	if err != nil || len(snaps) != 1 {
		t.Fatalf("deck.qslide snapshots = %v (%v), want one", snaps, err)
	}
	if b, err := os.ReadFile(snaps[0]); err != nil || string(b) != "first" {
		t.Errorf("snapshot holds %q (%v), want the content the save replaced", b, err)
	}
	if b, err := os.ReadFile(filepath.Join(filesDir, "docs", "deck.qslide")); err != nil || string(b) != "second" {
		t.Errorf("deck.qslide holds %q (%v), want the saved content", b, err)
	}
	if _, err := os.Stat(filepath.Join(store, "notes.txt")); !os.IsNotExist(err) {
		t.Errorf("notes.txt was versioned (stat err %v); only editor documents are", err)
	}
}

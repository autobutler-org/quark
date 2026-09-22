package v0_files_test

import (
	"crypto/rand"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// TestDownloadFolder_ZipFileName verifies a folder download names its archive
// after the folder with a .zip extension, quoted so a space survives.
func TestDownloadFolder_ZipFileName(t *testing.T) {
	engine, vfsRoot := newVFSTestEngine(t)

	dir := filepath.Join(vfsRoot, "my photos")
	if err := os.Mkdir(dir, 0755); err != nil {
		t.Fatalf("Mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("a"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=my%20photos", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", w.Code)
	}
	const want = `attachment; filename="my photos.zip"`
	if got := w.Header().Get("Content-Disposition"); got != want {
		t.Errorf("Content-Disposition: got %q, want %q", got, want)
	}
	if w.Body.Len() == 0 {
		t.Error("archive body empty")
	}
}

// TestDownloadFolder_IgnoresRange verifies a folder, zipped on the fly, answers
// a Range request with the whole archive and no Accept-Ranges. The download
// token store reads that header to decide a response cannot be resumed, so a
// folder's token ends with its first response (#2270).
func TestDownloadFolder_IgnoresRange(t *testing.T) {
	engine, vfsRoot := newVFSTestEngine(t)

	dir := filepath.Join(vfsRoot, "album")
	if err := os.Mkdir(dir, 0755); err != nil {
		t.Fatalf("Mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("a"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=album", nil)
	req.Header.Set("Range", "bytes=10-")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", w.Code)
	}
	if got := w.Header().Get("Accept-Ranges"); got != "" {
		t.Errorf("Accept-Ranges: got %q, want none", got)
	}
}

// failingWriter is a client that goes away after its first write.
type failingWriter struct {
	*httptest.ResponseRecorder
	writes int
}

func (w *failingWriter) Write(p []byte) (int, error) {
	w.writes++
	if w.writes > 1 {
		return 0, errors.New("connection reset by peer")
	}
	return w.ResponseRecorder.Write(p)
}

// TestDownloadFolder_MarksAnInterruptedZip verifies a folder zip cut off
// partway marks the request "downloadInterrupted", which keeps its download
// token alive for a retry (#2270), and answers nothing more, while a zip that
// completes leaves no mark.
func TestDownloadFolder_MarksAnInterruptedZip(t *testing.T) {
	deps, filesDir := newStorageVFSDeps(t)
	dir := filepath.Join(filesDir, "big")
	if err := os.Mkdir(dir, 0755); err != nil {
		t.Fatal(err)
	}
	// Two incompressible entries larger than the zip writer's buffer, so the
	// archive is written in more than one piece.
	for _, name := range []string{"a.bin", "b.bin"} {
		content := make([]byte, 64<<10)
		_, _ = rand.Read(content)
		if err := os.WriteFile(filepath.Join(dir, name), content, 0644); err != nil {
			t.Fatal(err)
		}
	}

	var interrupted bool
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
		interrupted, _ = ctxutil.Get[bool](c, "downloadInterrupted")
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_files.NewRouter())
	request := func() *http.Request {
		return httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=big", nil)
	}

	w := &failingWriter{ResponseRecorder: httptest.NewRecorder()}
	engine.ServeHTTP(w, request())
	if !interrupted {
		t.Error("interrupted zip: downloadInterrupted not set")
	}
	if w.Code != http.StatusOK {
		t.Errorf("interrupted zip: status %d, want the 200 already sent", w.Code)
	}

	engine.ServeHTTP(httptest.NewRecorder(), request())
	if interrupted {
		t.Error("complete zip: downloadInterrupted set")
	}
}

package v0_files_test

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/zipselectionutil"
	"github.com/gin-gonic/gin"
)

// selectionEngine serves the files router as the system principal over deps,
// marking requests as token-authenticated when viaToken is set.
func selectionEngine(deps deputil.Dependencies, viaToken bool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c = ctxutil.With(c, "username", "admin")
		if viaToken {
			c = ctxutil.With(c, "downloadToken", true)
		}
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_files.NewRouter())
	return engine
}

// postSelection submits the selection form, the way a browser does.
func postSelection(t *testing.T, engine *gin.Engine, query string, paths []zipselectionutil.Path) *httptest.ResponseRecorder {
	t.Helper()
	encoded, err := json.Marshal(paths)
	if err != nil {
		t.Fatal(err)
	}
	form := url.Values{"paths": {string(encoded)}}.Encode()
	return doRequest(engine, http.MethodPost, "/api/v0/files/download-selection"+query,
		strings.NewReader(form), "application/x-www-form-urlencoded")
}

// zipEntries reads a response's archive back as its entry names, in order,
// and their contents.
func zipEntries(t *testing.T, w *httptest.ResponseRecorder) ([]string, map[string]string) {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("download = %d: %s", w.Code, w.Body.String())
	}
	body := w.Body.Bytes()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("not a zip: %v", err)
	}
	var names []string
	contents := map[string]string{}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		b, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			t.Fatal(err)
		}
		names = append(names, f.Name)
		contents[f.Name] = string(b)
	}
	return names, contents
}

func writeAt(t *testing.T, dir, rel, content string) {
	t.Helper()
	full := filepath.Join(dir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// Three photos from two folders, one of them on a USB drive, land in one zip
// with nothing skipped.
func TestDownloadSelection_ZipsPhotosFromTwoFolders(t *testing.T) {
	deps, internalDir, usbDir := newDeviceUploadDeps(t)
	writeAt(t, internalDir, "Trip/a.jpg", "a")
	writeAt(t, internalDir, "Trip/b.jpg", "b")
	writeAt(t, usbDir, "Camera/c.jpg", "c")

	w := postSelection(t, selectionEngine(deps, false), "", []zipselectionutil.Path{
		{FilePath: "Trip/a.jpg"},
		{FilePath: "Trip/b.jpg"},
		{Serial: testUsbSerial, FilePath: "Camera/c.jpg"},
	})
	names, contents := zipEntries(t, w)
	if want := []string{"a.jpg", "b.jpg", "c.jpg"}; !slices.Equal(names, want) {
		t.Fatalf("entries = %v, want %v", names, want)
	}
	if contents["c.jpg"] != "c" {
		t.Errorf("c.jpg = %q, want the USB drive's file", contents["c.jpg"])
	}
	if got := w.Header().Get("Content-Disposition"); !strings.Contains(got, "selection.zip") {
		t.Errorf("Content-Disposition = %q, want selection.zip", got)
	}
}

// A file the caller has no access to, and one that is gone, are left out and
// named in skipped.txt; the download still succeeds.
func TestDownloadSelection_SkipsWhatTheCallerCannotRead(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/a.jpg")
	writeFixture(t, h.filesDir, "private/b.jpg")
	h.grant(t, "shared", accessutil.Read)

	encoded, err := json.Marshal([]zipselectionutil.Path{
		{FilePath: "shared/a.jpg"}, {FilePath: "private/b.jpg"}, {FilePath: "shared/gone.jpg"},
	})
	if err != nil {
		t.Fatal(err)
	}
	w := doRequest(h.engine, http.MethodPost, "/api/v0/files/download-selection",
		strings.NewReader(url.Values{"paths": {string(encoded)}}.Encode()), "application/x-www-form-urlencoded")
	names, contents := zipEntries(t, w)
	if want := []string{"a.jpg", zipselectionutil.SkippedListName}; !slices.Equal(names, want) {
		t.Fatalf("entries = %v, want %v", names, want)
	}
	list := contents[zipselectionutil.SkippedListName]
	if !strings.Contains(list, "private/b.jpg") || !strings.Contains(list, "shared/gone.jpg") {
		t.Errorf("skipped.txt does not name both left-out files:\n%s", list)
	}
}

// The same file name in two folders is numbered rather than overwritten.
func TestDownloadSelection_RenamesCollisions(t *testing.T) {
	deps, internalDir, _ := newDeviceUploadDeps(t)
	writeAt(t, internalDir, "2023/IMG_0001.jpg", "first")
	writeAt(t, internalDir, "2024/IMG_0001.jpg", "second")

	names, contents := zipEntries(t, postSelection(t, selectionEngine(deps, false), "", []zipselectionutil.Path{
		{FilePath: "2023/IMG_0001.jpg"}, {FilePath: "2024/IMG_0001.jpg"},
	}))
	if want := []string{"IMG_0001.jpg", "IMG_0001 (1).jpg"}; !slices.Equal(names, want) {
		t.Fatalf("entries = %v, want %v", names, want)
	}
	if contents["IMG_0001 (1).jpg"] != "second" {
		t.Errorf("renamed entry = %q, want the second file", contents["IMG_0001 (1).jpg"])
	}
}

// More than 2000 paths is refused by both the token and the download, as is
// an empty selection.
func TestDownloadSelection_RefusesOversizedSelections(t *testing.T) {
	deps, _, _ := newDeviceUploadDeps(t)
	engine := selectionEngine(deps, false)
	tooMany := make([]zipselectionutil.Path, zipselectionutil.MaxPaths+1)
	for i := range tooMany {
		tooMany[i].FilePath = fmt.Sprintf("p%d.jpg", i)
	}
	for name, paths := range map[string][]zipselectionutil.Path{"too many": tooMany, "empty": {}} {
		if w := postSelection(t, engine, "", paths); w.Code != http.StatusBadRequest {
			t.Errorf("%s download = %d, want 400", name, w.Code)
		}
		body, err := json.Marshal(map[string]any{"paths": paths})
		if err != nil {
			t.Fatal(err)
		}
		if w := doRequest(engine, http.MethodPost, "/api/v0/files/download-selection-token", bytes.NewReader(body), "application/json"); w.Code != http.StatusBadRequest {
			t.Errorf("%s token = %d, want 400", name, w.Code)
		}
	}
	if w := doRequest(engine, http.MethodPost, "/api/v0/files/download-selection",
		strings.NewReader("paths=not-json"), "application/x-www-form-urlencoded"); w.Code != http.StatusBadRequest {
		t.Errorf("malformed paths = %d, want 400", w.Code)
	}
}

// A token is issued for one selection: the download it authenticates must
// post those paths and name that selection, and is then an attachment.
func TestDownloadSelection_TokenIsBoundToItsSelection(t *testing.T) {
	deps, internalDir, _ := newDeviceUploadDeps(t)
	writeAt(t, internalDir, "a.jpg", "a")
	writeAt(t, internalDir, "b.jpg", "b")
	selection := []zipselectionutil.Path{{FilePath: "a.jpg"}}

	body, err := json.Marshal(map[string]any{"paths": selection})
	if err != nil {
		t.Fatal(err)
	}
	w := doRequest(selectionEngine(deps, false), http.MethodPost, "/api/v0/files/download-selection-token", bytes.NewReader(body), "application/json")
	if w.Code != http.StatusOK {
		t.Fatalf("token = %d: %s", w.Code, w.Body.String())
	}
	var issued struct {
		Token     string `json:"token"`
		Selection string `json:"selection"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &issued); err != nil {
		t.Fatal(err)
	}
	if issued.Token == "" || issued.Selection != zipselectionutil.SelectionKey(selection) {
		t.Fatalf("issued = %+v, want a token for %s", issued, zipselectionutil.SelectionKey(selection))
	}

	viaToken := selectionEngine(deps, true)
	query := "?filePath=" + url.QueryEscape(issued.Selection)
	if w := postSelection(t, viaToken, query, []zipselectionutil.Path{{FilePath: "b.jpg"}}); w.Code != http.StatusUnauthorized {
		t.Errorf("other paths under the token = %d, want 401", w.Code)
	}
	w = postSelection(t, viaToken, query, selection)
	if names, _ := zipEntries(t, w); !slices.Equal(names, []string{"a.jpg"}) {
		t.Errorf("entries = %v, want [a.jpg]", names)
	}
	if got := w.Header().Get("Content-Disposition"); got != `attachment; filename=selection.zip` {
		t.Errorf("Content-Disposition = %q, want an attachment", got)
	}
}

package v0_previews_test

// cspell:ignore descr

import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_previews "github.com/autobutler-org/quark/internal/server/api/v0/previews"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/docreadutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// imageBytes stands in for a picture; nothing on the server decodes it.
const imageBytes = "\x89PNG\r\n\x1a\nfake image"

const docNamespaces = `xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" ` +
	`xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ` +
	`xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" ` +
	`xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ` +
	`xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"`

// pictureBody is a heading-less document: a paragraph, then an inline
// picture of word/media/image1.png.
const pictureBody = `<w:p><w:r><w:t>Quarterly report</w:t></w:r></w:p>` +
	`<w:p><w:r><w:drawing><wp:inline><wp:extent cx="6096000" cy="3429000"/><wp:docPr id="1" name="Picture 1" descr="Revenue"/>` +
	`<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:blipFill>` +
	`<a:blip r:embed="rImg"/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>`

type fakeDetector struct{ mountPoint string }

func (f fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

// harness is the previews router over a real files directory and a migrated
// database, signed in as a non-admin who can read "shared" and nothing else.
type harness struct {
	engine   *gin.Engine
	filesDir string
}

func newHarness(t *testing.T) harness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(fakeDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: accessutil.Canonical("shared"),
		UserID:  sql.NullInt64{Int64: user.ID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithDatabase(database)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: user.ID})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_previews.NewRouter())
	return harness{engine: engine, filesDir: filesDir}
}

// writeDocx packages body as a DOCX at rel, with the picture pictureBody
// names and a non-image part in its media folder.
func (h harness) writeDocx(t *testing.T, rel, body string) {
	t.Helper()
	const relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	parts := map[string]string{
		"[Content_Types].xml": `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>`,
		"_rels/.rels": `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="` + relNS + `/officeDocument" Target="word/document.xml"/></Relationships>`,
		"word/document.xml": `<w:document ` + docNamespaces + `><w:body>` + body + `</w:body></w:document>`,
		"word/_rels/document.xml.rels": `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rImg" Type="` + relNS + `/image" Target="media/image1.png"/></Relationships>`,
		"word/media/image1.png": imageBytes,
		"word/media/readme.txt": "not an image",
	}
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, content := range parts {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	h.writeFile(t, rel, buf.Bytes())
}

func (h harness) writeFile(t *testing.T, rel string, content []byte) {
	t.Helper()
	full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, content, 0o644); err != nil {
		t.Fatal(err)
	}
}

func (h harness) get(route string, query map[string]string) *httptest.ResponseRecorder {
	q := url.Values{}
	for k, v := range query {
		q.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/previews/"+route+"?"+q.Encode(), nil))
	return w
}

// lines decodes an NDJSON body into its objects.
func lines(t *testing.T, body string) []map[string]any {
	t.Helper()
	var out []map[string]any
	sc := bufio.NewScanner(strings.NewReader(body))
	sc.Buffer(nil, 1<<20)
	for sc.Scan() {
		var line map[string]any
		if err := json.Unmarshal(sc.Bytes(), &line); err != nil {
			t.Fatalf("line %q is not JSON: %v", sc.Text(), err)
		}
		out = append(out, line)
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestPreviewDocument_StreamsBlocks(t *testing.T) {
	h := newHarness(t)
	h.writeDocx(t, "shared/report.docx", pictureBody)

	w := h.get("document", map[string]string{"filePath": "shared/report.docx"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != docreadutil.NDJSONContentType {
		t.Errorf("Content-Type = %q", ct)
	}
	got := lines(t, w.Body.String())
	if len(got) != 4 {
		t.Fatalf("got %d lines, want meta, paragraph, image, end: %s", len(got), w.Body.String())
	}
	if got[0]["type"] != "meta" || got[0]["format"] != "docx" {
		t.Errorf("first line = %v", got[0])
	}
	if got[2]["type"] != "image" || got[2]["part"] != "word/media/image1.png" || got[2]["alt"] != "Revenue" {
		t.Errorf("image line = %v", got[2])
	}
	if end := got[3]; end["type"] != "end" || end["truncated"] != false || end["words"] != float64(2) {
		t.Errorf("end line = %v", end)
	}
}

func TestPreviewDocument_TruncatedStreamStillEnds(t *testing.T) {
	h := newHarness(t)
	body := strings.Repeat(`<w:p><w:r><w:t>x</w:t></w:r></w:p>`, docreadutil.DefaultMaxBlocks+10)
	h.writeDocx(t, "shared/long.docx", body)

	w := h.get("document", map[string]string{"filePath": "shared/long.docx"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	got := lines(t, w.Body.String())
	end := got[len(got)-1]
	if end["type"] != "end" || end["truncated"] != true {
		t.Errorf("last line = %v, want an end line marked truncated", end)
	}
	// meta, the admitted blocks, end.
	if len(got) != docreadutil.DefaultMaxBlocks+2 {
		t.Errorf("got %d lines, want %d", len(got), docreadutil.DefaultMaxBlocks+2)
	}
}

func TestPreviewDocument_Refusals(t *testing.T) {
	h := newHarness(t)
	h.writeDocx(t, "other/secret.docx", pictureBody)
	h.writeFile(t, "shared/fake.docx", []byte("this is plain text"))
	h.writeFile(t, "shared/notes.txt", []byte("notes"))

	for name, tc := range map[string]struct {
		filePath string
		want     int
	}{
		"no access":          {"other/secret.docx", http.StatusNotFound},
		"missing":            {"shared/missing.docx", http.StatusNotFound},
		"not what it claims": {"shared/fake.docx", http.StatusBadRequest},
		"not a document":     {"shared/notes.txt", http.StatusBadRequest},
		"no filePath":        {"", http.StatusBadRequest},
	} {
		w := h.get("document", map[string]string{"filePath": tc.filePath})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
		if ct := w.Header().Get("Content-Type"); strings.Contains(ct, "ndjson") {
			t.Errorf("%s: a refusal was labeled %q", name, ct)
		}
	}
}

func TestGetPart_ServesAMediaImage(t *testing.T) {
	h := newHarness(t)
	h.writeDocx(t, "shared/report.docx", pictureBody)

	w := h.get("part", map[string]string{"filePath": "shared/report.docx", "part": "word/media/image1.png"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	if w.Body.String() != imageBytes || w.Header().Get("Content-Type") != "image/png" {
		t.Errorf("served %q as %q", w.Body.String(), w.Header().Get("Content-Type"))
	}
	if w.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Error("an image part must not be sniffed")
	}
}

func TestGetPart_Refusals(t *testing.T) {
	h := newHarness(t)
	h.writeDocx(t, "shared/report.docx", pictureBody)
	h.writeDocx(t, "other/secret.docx", pictureBody)
	h.writePptx(t, "shared/talk.pptx")
	// Every part below is present, so a 404 is the allow-list refusing it.
	h.writePackage(t, "shared/macros.pptm", map[string]string{
		"ppt/vbaProject.bin":   "macros",
		"vbaProject.bin":       "macros",
		"ppt/presentation.xml": "<p:presentation/>",
		"ppt/media/image1.png": "\x89PNG",
	})

	for name, tc := range map[string]struct {
		filePath, part string
		want           int
	}{
		"no access":            {"other/secret.docx", "word/media/image1.png", http.StatusNotFound},
		"traversal":            {"shared/report.docx", "word/media/../document.xml", http.StatusNotFound},
		"traversal out":        {"shared/report.docx", "word/media/../../../../etc/passwd.png", http.StatusNotFound},
		"absolute":             {"shared/report.docx", "/word/media/image1.png", http.StatusNotFound},
		"non-media part":       {"shared/report.docx", "word/document.xml", http.StatusNotFound},
		"package relationship": {"shared/report.docx", "_rels/.rels", http.StatusNotFound},
		"non-image in media":   {"shared/report.docx", "word/media/readme.txt", http.StatusNotFound},
		"absent image":         {"shared/report.docx", "word/media/image9.png", http.StatusNotFound},
		"no part":              {"shared/report.docx", "", http.StatusBadRequest},
		"pptx slide":           {"shared/talk.pptx", "ppt/slides/slide1.xml", http.StatusNotFound},
		"pptx macros":          {"shared/macros.pptm", "ppt/vbaProject.bin", http.StatusNotFound},
		"pptx root macros":     {"shared/macros.pptm", "vbaProject.bin", http.StatusNotFound},
		"pptx traversal":       {"shared/macros.pptm", "ppt/media/../presentation.xml", http.StatusNotFound},
	} {
		w := h.get("part", map[string]string{"filePath": tc.filePath, "part": tc.part})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
	}
}

// writePackage writes parts as a zip at rel.
func (h harness) writePackage(t *testing.T, rel string, parts map[string]string) {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, content := range parts {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	h.writeFile(t, rel, buf.Bytes())
}

func TestGetProperties_EachFormat(t *testing.T) {
	h := newHarness(t)
	h.writePackage(t, "shared/a.docx", map[string]string{
		"docProps/core.xml": `<coreProperties><title>Report</title><creator>Ada</creator></coreProperties>`,
		"docProps/app.xml":  `<Properties><Application>Word</Application><Pages>3</Pages><Words>40</Words></Properties>`,
	})
	h.writePackage(t, "shared/a.odt", map[string]string{
		"meta.xml": `<document-meta><meta><title>Notes</title><document-statistic page-count="2" word-count="9"/></meta></document-meta>`,
	})
	h.writeFile(t, "shared/a.rtf", []byte(`{\rtf1{\info{\title Memo}\nofpages5}}`))

	for file, want := range map[string]map[string]any{
		"shared/a.docx": {"title": "Report", "author": "Ada", "application": "Word", "pages": float64(3), "words": float64(40)},
		"shared/a.odt":  {"title": "Notes", "pages": float64(2), "words": float64(9)},
		"shared/a.rtf":  {"title": "Memo", "pages": float64(5)},
	} {
		w := h.get("properties", map[string]string{"filePath": file})
		if w.Code != http.StatusOK {
			t.Fatalf("%s: status = %d: %s", file, w.Code, w.Body.String())
		}
		var body map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatalf("%s: %v: %s", file, err, w.Body.String())
		}
		if body["countsSource"] != "saved" {
			t.Errorf("%s: countsSource = %v", file, body["countsSource"])
		}
		for k, v := range want {
			if body[k] != v {
				t.Errorf("%s: %s = %v, want %v (%v)", file, k, body[k], v, body)
			}
		}
	}
}

func TestGetProperties_Refusals(t *testing.T) {
	h := newHarness(t)
	h.writePackage(t, "other/secret.docx", map[string]string{"docProps/core.xml": `<a><title>x</title></a>`})
	h.writeFile(t, "shared/fake.docx", []byte("this is plain text"))
	h.writeFile(t, "shared/notes.txt", []byte("notes"))
	h.writePackage(t, "shared/huge.docx", map[string]string{
		"docProps/core.xml": "<a>" + strings.Repeat("x", 2<<20) + "</a>",
	})

	for name, tc := range map[string]struct {
		filePath string
		want     int
	}{
		"no access":          {"other/secret.docx", http.StatusNotFound},
		"missing":            {"shared/missing.docx", http.StatusNotFound},
		"not what it claims": {"shared/fake.docx", http.StatusBadRequest},
		"not a document":     {"shared/notes.txt", http.StatusBadRequest},
		"oversize metadata":  {"shared/huge.docx", http.StatusBadRequest},
		"no filePath":        {"", http.StatusBadRequest},
	} {
		w := h.get("properties", map[string]string{"filePath": tc.filePath})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
	}
}

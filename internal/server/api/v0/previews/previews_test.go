package v0_previews_test

// cspell:ignore descr xlink xmlns

import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"image"
	"image/png"
	"io"
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
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
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

// writePptx exports a two-slide deck whose slides show the same picture as a
// .pptx at rel, and returns the picture.
func (h harness) writePptx(t *testing.T, rel string) []byte {
	t.Helper()
	var pic bytes.Buffer
	if err := png.Encode(&pic, image.NewGray(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	const deck = `{"schemaVersion":1,"title":"Talk","slides":[
		{"id":"s1","elements":[{"id":"a","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"dog.png"}]},
		{"id":"s2","elements":[{"id":"b","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"dog.png"}]}]}`
	var out bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(deck),
		Out:    &out,
		OpenImage: func(string) (io.ReadCloser, int64, error) {
			return io.NopCloser(bytes.NewReader(pic.Bytes())), int64(pic.Len()), nil
		},
	}); err != nil {
		t.Fatal(err)
	}
	h.writeFile(t, rel, out.Bytes())
	return pic.Bytes()
}

func TestPreviewSlides_StreamsTheDeckAndItsPicturesServe(t *testing.T) {
	h := newHarness(t)
	pic := h.writePptx(t, "shared/talk.pptx")

	w := h.get("slides", map[string]string{"filePath": "shared/talk.pptx"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Errorf("Content-Type = %q", ct)
	}
	var got struct {
		Deck struct {
			Slides []struct {
				Elements []struct {
					Source string `json:"source"`
				} `json:"elements"`
			} `json:"slides"`
		} `json:"deck"`
		Warnings []any `json:"warnings"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("body is not one JSON object: %v\n%s", err, w.Body.String())
	}
	if len(got.Deck.Slides) != 2 || got.Warnings == nil {
		t.Fatalf("preview = %+v", got)
	}
	ref := got.Deck.Slides[0].Elements[0].Source
	part, ok := strings.CutPrefix(ref, "part:")
	if !ok || !strings.HasPrefix(part, "ppt/media/") {
		t.Fatalf("picture reference = %q, want part:ppt/media/...", ref)
	}

	w = h.get("part", map[string]string{"filePath": "shared/talk.pptx", "part": part})
	if w.Code != http.StatusOK || !bytes.Equal(w.Body.Bytes(), pic) || w.Header().Get("Content-Type") != "image/png" {
		t.Errorf("part %s: status %d, %d bytes as %q", part, w.Code, w.Body.Len(), w.Header().Get("Content-Type"))
	}
}

func TestPreviewSlides_Refusals(t *testing.T) {
	h := newHarness(t)
	h.writePptx(t, "other/secret.pptx")
	h.writeFile(t, "shared/fake.pptx", []byte("this is plain text"))
	h.writeFile(t, "shared/legacy.ppt", []byte("binary"))

	for name, tc := range map[string]struct {
		filePath string
		want     int
	}{
		"no access":            {"other/secret.pptx", http.StatusNotFound},
		"missing":              {"shared/missing.pptx", http.StatusNotFound},
		"not what it claims":   {"shared/fake.pptx", http.StatusBadRequest},
		"legacy binary format": {"shared/legacy.ppt", http.StatusBadRequest},
		"no filePath":          {"", http.StatusBadRequest},
	} {
		w := h.get("slides", map[string]string{"filePath": tc.filePath})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
		if strings.Contains(w.Body.String(), `"deck"`) {
			t.Errorf("%s: a refusal started a deck: %s", name, w.Body.String())
		}
	}
}

func TestGetPart_ServesOnlyAPresentationsMediaFolder(t *testing.T) {
	h := newHarness(t)
	h.writePptx(t, "shared/talk.pptx")

	for _, part := range []string{
		"ppt/presentation.xml", "ppt/slides/slide1.xml", "ppt/media/../presentation.xml",
		"word/media/image1.png", "ppt/media/image9.png",
	} {
		w := h.get("part", map[string]string{"filePath": "shared/talk.pptx", "part": part})
		if w.Code != http.StatusNotFound {
			t.Errorf("%s: status = %d, want 404", part, w.Code)
		}
	}
}

// writeOds packages a one-sheet OpenDocument spreadsheet at rel.
func (h harness) writeOds(t *testing.T, rel string) {
	t.Helper()
	const mime = "application/vnd.oasis.opendocument.spreadsheet"
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, p := range []struct{ name, body string }{
		{"mimetype", mime},
		{"META-INF/manifest.xml", `<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">` +
			`<manifest:file-entry manifest:full-path="/" manifest:media-type="` + mime + `"/>` +
			`<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>`},
		{"content.xml", `<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ` +
			`xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">` +
			`<office:body><office:spreadsheet><table:table table:name="Ledger"><table:table-row>` +
			`<table:table-cell office:value-type="string"><text:p>Item</text:p></table:table-cell>` +
			`<table:table-cell office:value-type="float" office:value="3.5"><text:p>3.50</text:p></table:table-cell>` +
			`</table:table-row></table:table></office:spreadsheet></office:body></office:document-content>`},
	} {
		w, err := zw.Create(p.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, p.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	h.writeFile(t, rel, buf.Bytes())
}

// writeXls copies xlsutil's LibreOffice-saved Excel 97 workbook to rel.
func (h harness) writeXls(t *testing.T, rel string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "..", "pkg", "util", "xlsutil", "testdata", "libreoffice.xls"))
	if err != nil {
		t.Fatal(err)
	}
	h.writeFile(t, rel, raw)
}

func TestPreviewSheet_StreamsEachReader(t *testing.T) {
	h := newHarness(t)
	h.writeOds(t, "shared/ledger.ods")
	h.writeXls(t, "shared/budget.xls")

	for rel, want := range map[string]struct {
		tab   string
		first []string
	}{
		"shared/ledger.ods": {"Ledger", []string{"Item", "3.5"}},
		"shared/budget.xls": {"Budget", []string{"Item", "Cost", "Due"}},
	} {
		w := h.get("sheet", map[string]string{"filePath": rel})
		if w.Code != http.StatusOK {
			t.Fatalf("%s: status = %d: %s", rel, w.Code, w.Body.String())
		}
		if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
			t.Errorf("%s: Content-Type = %q", rel, ct)
		}
		var got struct {
			Tabs []struct {
				Name string `json:"name"`
				Data struct {
					Rows [][]string `json:"rows"`
				} `json:"data"`
			} `json:"tabs"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
			t.Fatalf("%s: body is not one JSON object: %v\n%s", rel, err, w.Body.String())
		}
		if len(got.Tabs) == 0 || got.Tabs[0].Name != want.tab || len(got.Tabs[0].Data.Rows) == 0 ||
			strings.Join(got.Tabs[0].Data.Rows[0], "|") != strings.Join(want.first, "|") {
			t.Errorf("%s: preview = %+v", rel, got)
		}
	}
}

func TestPreviewSheet_Refusals(t *testing.T) {
	h := newHarness(t)
	h.writeOds(t, "other/secret.ods")
	h.writeFile(t, "shared/fake.xls", []byte("this is plain text"))
	h.writeFile(t, "shared/fake.ods", []byte("this is plain text"))
	h.writeFile(t, "shared/notes.csv", []byte("a,b"))

	for name, tc := range map[string]struct {
		filePath string
		want     int
	}{
		"no access":      {"other/secret.ods", http.StatusNotFound},
		"missing":        {"shared/missing.xlsx", http.StatusNotFound},
		"not an xls":     {"shared/fake.xls", http.StatusBadRequest},
		"not an ods":     {"shared/fake.ods", http.StatusBadRequest},
		"not a workbook": {"shared/notes.csv", http.StatusBadRequest},
		"no filePath":    {"", http.StatusBadRequest},
	} {
		w := h.get("sheet", map[string]string{"filePath": tc.filePath})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
		if strings.Contains(w.Body.String(), `"tabs"`) {
			t.Errorf("%s: a refusal started a sheet: %s", name, w.Body.String())
		}
	}
}

// odpXMLNS is the namespace declarations an .odp's parts carry.
const odpXMLNS = `xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ` +
	`xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" ` +
	`xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ` +
	`xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" ` +
	`xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" ` +
	`xmlns:xlink="http://www.w3.org/1999/xlink" ` +
	`xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" ` +
	`xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"`

// odpPicture is the one picture odpPackage's slides show.
const odpPicture = "Pictures/10000000000001.png"

// odpPackage is a two-slide OpenDocument presentation whose slides show the
// same picture, the second with notes. An encrypted one marks content.xml
// password-protected in its manifest.
func odpPackage(t *testing.T, encrypted bool) []byte {
	t.Helper()
	const mime = "application/vnd.oasis.opendocument.presentation"
	var pic bytes.Buffer
	if err := png.Encode(&pic, image.NewGray(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	contentEntry := `<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>`
	if encrypted {
		contentEntry = `<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml">` +
			`<manifest:encryption-data/></manifest:file-entry>`
	}
	picture := `<draw:frame svg:x="1cm" svg:y="1cm" svg:width="4cm" svg:height="3cm">` +
		`<draw:image xlink:href="` + odpPicture + `"/></draw:frame>`
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, p := range []struct{ name, body string }{
		{"mimetype", mime},
		{"META-INF/manifest.xml", `<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">` +
			`<manifest:file-entry manifest:full-path="/" manifest:media-type="` + mime + `"/>` + contentEntry +
			`</manifest:manifest>`},
		{"styles.xml", `<office:document-styles ` + odpXMLNS + `><office:automatic-styles>` +
			`<style:page-layout style:name="PM1"><style:page-layout-properties fo:page-width="28cm" fo:page-height="15.75cm"/></style:page-layout>` +
			`</office:automatic-styles><office:master-styles>` +
			`<style:master-page style:name="Default" style:page-layout-name="PM1"/>` +
			`</office:master-styles></office:document-styles>`},
		{"content.xml", `<office:document-content ` + odpXMLNS + `><office:body><office:presentation>` +
			`<draw:page draw:name="one" draw:master-page-name="Default">` + picture + `</draw:page>` +
			`<draw:page draw:name="two" draw:master-page-name="Default">` + picture +
			`<presentation:notes><draw:frame presentation:class="notes" svg:x="0cm" svg:y="0cm" svg:width="4cm" svg:height="4cm">` +
			`<draw:text-box><text:p>Thanks</text:p></draw:text-box></draw:frame></presentation:notes></draw:page>` +
			`</office:presentation></office:body></office:document-content>`},
		{odpPicture, pic.String()},
	} {
		w, err := zw.Create(p.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, p.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestPreviewSlides_StreamsAnOdpAndItsPicturesServe(t *testing.T) {
	h := newHarness(t)
	h.writeFile(t, "shared/talk.odp", odpPackage(t, false))

	w := h.get("slides", map[string]string{"filePath": "shared/talk.odp"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	var got struct {
		Deck struct {
			Slides []struct {
				Elements []struct {
					Source string `json:"source"`
				} `json:"elements"`
			} `json:"slides"`
		} `json:"deck"`
		Warnings []any `json:"warnings"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("body is not one JSON object: %v\n%s", err, w.Body.String())
	}
	if len(got.Deck.Slides) != 2 || got.Warnings == nil {
		t.Fatalf("preview = %+v", got)
	}
	ref := got.Deck.Slides[0].Elements[0].Source
	if ref != "part:"+odpPicture {
		t.Fatalf("picture reference = %q, want part:%s", ref, odpPicture)
	}

	w = h.get("part", map[string]string{"filePath": "shared/talk.odp", "part": odpPicture})
	if w.Code != http.StatusOK || !bytes.HasPrefix(w.Body.Bytes(), []byte("\x89PNG")) || w.Header().Get("Content-Type") != "image/png" {
		t.Errorf("part: status %d, %d bytes as %q", w.Code, w.Body.Len(), w.Header().Get("Content-Type"))
	}
}

func TestPreviewSlides_OdpRefusals(t *testing.T) {
	h := newHarness(t)
	h.writeFile(t, "other/secret.odp", odpPackage(t, false))
	h.writeFile(t, "shared/fake.odp", []byte("this is plain text"))
	h.writeFile(t, "shared/locked.odp", odpPackage(t, true))

	for name, tc := range map[string]struct {
		filePath string
		want     int
	}{
		"no access":          {"other/secret.odp", http.StatusNotFound},
		"missing":            {"shared/missing.odp", http.StatusNotFound},
		"not what it claims": {"shared/fake.odp", http.StatusBadRequest},
		"encrypted":          {"shared/locked.odp", http.StatusBadRequest},
	} {
		w := h.get("slides", map[string]string{"filePath": tc.filePath})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
		if strings.Contains(w.Body.String(), `"deck"`) {
			t.Errorf("%s: a refusal started a deck: %s", name, w.Body.String())
		}
	}
}

func TestGetPart_ServesOnlyTheOdpPicturesFolder(t *testing.T) {
	h := newHarness(t)
	h.writeFile(t, "shared/talk.odp", odpPackage(t, false))
	h.writeFile(t, "other/secret.odp", odpPackage(t, false))

	for _, part := range []string{
		"content.xml", "META-INF/manifest.xml", "Pictures/../content.xml", "ppt/media/image1.png", "Pictures/missing.png",
	} {
		w := h.get("part", map[string]string{"filePath": "shared/talk.odp", "part": part})
		if w.Code != http.StatusNotFound {
			t.Errorf("%s: status = %d, want 404", part, w.Code)
		}
	}
	if w := h.get("part", map[string]string{"filePath": "other/secret.odp", "part": odpPicture}); w.Code != http.StatusNotFound {
		t.Errorf("unreadable presentation: status = %d, want 404", w.Code)
	}
}

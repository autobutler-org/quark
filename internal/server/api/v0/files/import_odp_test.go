package v0_files_test

// cspell:ignore xlink xmlns

import (
	"archive/zip"
	"bytes"
	"image"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

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

func TestImportOdp_WritesAQslideBesideThePresentation(t *testing.T) {
	h := newAccessHarness(t, true)
	seedFile(t, h.filesDir, "shared/Talk.odp", odpPackage(t, false))

	got := importResponse(t, h.post("/api/v0/files/import/odp?filePath=shared/Talk.odp"))
	if got.Path != "shared/Talk.qslide" || got.MediaDir != "shared/Talk_media" || got.Slides != 2 ||
		got.Pictures != 1 || got.Warnings == nil {
		t.Errorf("import = %+v", got)
	}
	if names, want := h.names(t, "shared"), []string{"Talk.odp", "Talk.qslide", "Talk_media"}; !slices.Equal(names, want) {
		t.Errorf("folder = %v, want %v", names, want)
	}
	if names := h.names(t, "shared/Talk_media"); !slices.Equal(names, []string{"10000000000001.png"}) {
		t.Errorf("media = %v", names)
	}

	again := importResponse(t, h.post("/api/v0/files/import/odp?filePath=shared/Talk.odp&rootDir=decks"))
	if again.Path != "decks/Talk.qslide" || again.MediaDir != "decks/Talk_media" {
		t.Errorf("import into decks = %+v", again)
	}
}

func TestImportOdp_RejectsBadRequests(t *testing.T) {
	h := newAccessHarness(t, true)
	writePptx(t, h.filesDir, "Talk.pptx")
	seedFile(t, h.filesDir, "Broken.odp", []byte("not a zip"))
	seedFile(t, h.filesDir, "Locked.odp", odpPackage(t, true))

	expectCodes(t, http.StatusBadRequest, map[string]*httptest.ResponseRecorder{
		"no path":      h.post("/api/v0/files/import/odp"),
		"a pptx":       h.post("/api/v0/files/import/odp?filePath=Talk.pptx"),
		"broken odp":   h.post("/api/v0/files/import/odp?filePath=Broken.odp"),
		"encrypted":    h.post("/api/v0/files/import/odp?filePath=Locked.odp"),
		"climbing out": h.post("/api/v0/files/import/odp?filePath=Broken.odp&rootDir=../x"),
	})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"missing": h.post("/api/v0/files/import/odp?filePath=Missing.odp"),
	})
	if names, want := h.names(t, ""), []string{"Broken.odp", "Locked.odp", "Talk.pptx"}; !slices.Equal(names, want) {
		t.Errorf("a failed import left files behind: %v", names)
	}
}

func TestImportOdp_NeedsReadOnThePresentationAndWriteOnTheFolder(t *testing.T) {
	h := newAccessHarness(t, false)
	seedFile(t, h.filesDir, "shared/Talk.odp", odpPackage(t, false))
	seedFile(t, h.filesDir, "other/Talk.odp", odpPackage(t, false))
	h.grant(t, "shared", accessutil.Read)
	h.grant(t, "mine", accessutil.Write)

	expectCodes(t, http.StatusForbidden, map[string]*httptest.ResponseRecorder{
		"read-only folder": h.post("/api/v0/files/import/odp?filePath=shared/Talk.odp"),
	})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"unreadable presentation": h.post("/api/v0/files/import/odp?filePath=other/Talk.odp&rootDir=mine"),
	})

	got := importResponse(t, h.post("/api/v0/files/import/odp?filePath=shared/Talk.odp&rootDir=mine"))
	if got.Path != "mine/Talk.qslide" {
		t.Errorf("import = %+v", got)
	}
	levels := h.levels(t)
	for _, p := range []string{"mine/Talk.qslide", "mine/Talk_media"} {
		if levels[accessutil.Canonical(p)] != accessutil.Owner.String() {
			t.Errorf("%s: level %q, want owner (rows %v)", p, levels[accessutil.Canonical(p)], levels)
		}
	}
}

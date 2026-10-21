package fileutil_test

// cspell:ignore xlink xmlns

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"image"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
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

// seedOdp writes odpPackage as an .odp at rel under root.
func seedOdp(t *testing.T, root, rel string) {
	t.Helper()
	writeTestFile(t, root, rel, odpPackage(t, false))
}

func TestImportOdpToQslideWritesThePresentationAndItsPictures(t *testing.T) {
	f := newImportFixture(t)
	seedOdp(t, f.root, "decks/Talk.odp")

	params := fileutil.ImportOdpParams(f.params)
	params.FilePath = "decks/Talk.odp"
	params.RootDir = "decks"
	result, err := fileutil.ImportOdpToQslide(params)
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if result.Path != "decks/Talk.qslide" || result.MediaDir != "decks/Talk_media" || !result.MediaDirCreated ||
		result.Slides != 2 || result.Pictures != 1 {
		t.Errorf("result = %+v", result)
	}
	if got, want := f.tree(t), []string{
		"decks", "decks/Talk.odp", "decks/Talk.qslide", "decks/Talk_media", "decks/Talk_media/10000000000001.png",
	}; !slices.Equal(got, want) {
		t.Errorf("tree = %v, want %v", got, want)
	}

	raw, err := os.ReadFile(filepath.Join(f.root, "decks", "Talk.qslide"))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		Title  string `json:"title"`
		Slides []struct {
			Elements []struct {
				Source string `json:"source"`
			} `json:"elements"`
			Notes string `json:"notes"`
		} `json:"slides"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("not a .qslide: %v\n%s", err, raw)
	}
	if doc.Title != "Talk" || len(doc.Slides) != 2 || doc.Slides[1].Notes != "Thanks" {
		t.Errorf("presentation = %s", raw)
	}
	for _, s := range doc.Slides {
		if len(s.Elements) != 1 || s.Elements[0].Source != "decks/Talk_media/10000000000001.png" {
			t.Errorf("slide elements = %+v", s.Elements)
		}
	}
}

func TestImportOdpToQslideRejectsOtherFiles(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "Talk.pptx")
	writeTestFile(t, f.root, "Broken.odp", []byte("not a zip"))
	writeTestFile(t, f.root, "Locked.odp", odpPackage(t, true))
	for _, p := range []string{"Talk.pptx", "Broken.odp", "Locked.odp"} {
		params := fileutil.ImportOdpParams(f.params)
		params.FilePath = p
		_, err := fileutil.ImportOdpToQslide(params)
		var unsupported *fileutil.UnsupportedError
		if !errors.As(err, &unsupported) {
			t.Errorf("%s: %v, want an UnsupportedError", p, err)
		}
	}
	params := fileutil.ImportOdpParams(f.params)
	params.FilePath = "Missing.odp"
	var notFound *fileutil.NotFoundError
	if _, err := fileutil.ImportOdpToQslide(params); !errors.As(err, &notFound) {
		t.Errorf("missing: %v, want a NotFoundError", err)
	}
	if got := f.tree(t); !slices.Equal(got, []string{"Broken.odp", "Locked.odp", "Talk.pptx"}) {
		t.Errorf("tree = %v", got)
	}

	// The PowerPoint import refuses an .odp in turn.
	seedOdp(t, f.root, "Talk.odp")
	pptx := f.params
	pptx.FilePath = "Talk.odp"
	var unsupported *fileutil.UnsupportedError
	if _, err := fileutil.ImportPptxToQslide(pptx); !errors.As(err, &unsupported) {
		t.Errorf("pptx import of an .odp: %v, want an UnsupportedError", err)
	}
}

func TestIsOdpPath(t *testing.T) {
	for p, want := range map[string]bool{
		"a.odp": true, "b.ODP": true, "c.otp": false, "d.pptx": false, "e.odt": false,
	} {
		if got := fileutil.IsOdpPath(p); got != want {
			t.Errorf("IsOdpPath(%q) = %v, want %v", p, got, want)
		}
	}
}

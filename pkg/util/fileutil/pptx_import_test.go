package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// pptxDeck is a two-slide deck whose slides show the same picture.
const pptxDeck = `{"schemaVersion":1,"title":"Talk","slides":[
	{"id":"s1","elements":[{"id":"a","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"dog.png"}]},
	{"id":"s2","elements":[{"id":"b","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"dog.png"}],
	 "notes":"Thanks"}]}`

// seedPptx exports pptxDeck as a .pptx at rel under root.
func seedPptx(t *testing.T, root, rel string) {
	t.Helper()
	var pic bytes.Buffer
	if err := png.Encode(&pic, image.NewGray(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(pptxDeck),
		Out:    &out,
		OpenImage: func(string) (io.ReadCloser, int64, error) {
			return io.NopCloser(bytes.NewReader(pic.Bytes())), int64(pic.Len()), nil
		},
	}); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, root, rel, out.Bytes())
}

func writeTestFile(t *testing.T, root, rel string, body []byte) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, body, 0o600); err != nil {
		t.Fatal(err)
	}
}

// importFixture is a files namespace and the event bus imports publish on.
type importFixture struct {
	root   string
	bus    *eventbus.Bus
	params fileutil.ImportPptxParams
}

func newImportFixture(t *testing.T) importFixture {
	t.Helper()
	root := t.TempDir()
	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatal(err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files", MountPath: "/"}, fsys); err != nil {
		t.Fatal(err)
	}
	bus := eventbus.New()
	return importFixture{root: root, bus: bus, params: fileutil.ImportPptxParams{
		Ctx: context.Background(), Registry: registry, EventBus: bus,
	}}
}

// tree lists every file and folder under root, files-relative.
func (f importFixture) tree(t *testing.T) []string {
	t.Helper()
	var out []string
	err := filepath.WalkDir(f.root, func(p string, _ os.DirEntry, err error) error {
		if err != nil || p == f.root {
			return err
		}
		rel, _ := filepath.Rel(f.root, p)
		out = append(out, filepath.ToSlash(rel))
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	slices.Sort(out)
	return out
}

func TestImportPptxToQslideWritesThePresentationAndItsPictures(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "decks/Talk.pptx")
	events, unsubscribe := f.bus.Subscribe("test")
	defer unsubscribe()

	params := f.params
	params.FilePath = "decks/Talk.pptx"
	params.RootDir = "decks"
	result, err := fileutil.ImportPptxToQslide(params)
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if result.Path != "decks/Talk.qslide" || result.MediaDir != "decks/Talk_media" || !result.MediaDirCreated ||
		result.Slides != 2 || result.Pictures != 1 || len(result.Warnings) != 0 {
		t.Errorf("result = %+v", result)
	}
	if got, want := f.tree(t), []string{
		"decks", "decks/Talk.pptx", "decks/Talk.qslide", "decks/Talk_media", "decks/Talk_media/image1.png",
	}; !slices.Equal(got, want) {
		t.Errorf("tree = %v, want %v", got, want)
	}

	raw, err := os.ReadFile(filepath.Join(f.root, "decks", "Talk.qslide"))
	if err != nil {
		t.Fatal(err)
	}
	var doc struct {
		SchemaVersion int    `json:"schemaVersion"`
		Title         string `json:"title"`
		Slides        []struct {
			Elements []struct {
				Source string `json:"source"`
			} `json:"elements"`
			Notes string `json:"notes"`
		} `json:"slides"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("not a .qslide: %v\n%s", err, raw)
	}
	if doc.SchemaVersion != 1 || doc.Title != "Talk" || len(doc.Slides) != 2 || doc.Slides[1].Notes != "Thanks" {
		t.Errorf("presentation = %s", raw)
	}
	for _, s := range doc.Slides {
		if len(s.Elements) != 1 || s.Elements[0].Source != "decks/Talk_media/image1.png" {
			t.Errorf("slide elements = %+v", s.Elements)
		}
	}

	// The folder and the media folder are announced once each, after the
	// import finished.
	var paths []string
	timeout := time.After(time.Second)
	for len(paths) < 2 {
		select {
		case e := <-events:
			if e.Kind == eventbus.EventUpload {
				paths = append(paths, e.Path)
			}
		case <-timeout:
			t.Fatalf("events = %v, want the folder and the media folder", paths)
		}
	}
	if !slices.Equal(paths, []string{"decks", "decks/Talk_media"}) {
		t.Errorf("event paths = %v", paths)
	}
}

func TestImportPptxToQslideKeepsBoth(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "Talk.pptx")
	params := f.params
	params.FilePath = "Talk.pptx"
	if _, err := fileutil.ImportPptxToQslide(params); err != nil {
		t.Fatal(err)
	}
	result, err := fileutil.ImportPptxToQslide(params)
	if err != nil {
		t.Fatal(err)
	}
	if result.Path != "Talk_(1).qslide" || result.MediaDirCreated ||
		!slices.Equal(result.Media, []string{"Talk_media/image1_(1).png"}) {
		t.Errorf("second import = %+v", result)
	}
	if got, want := f.tree(t), []string{
		"Talk.pptx", "Talk.qslide", "Talk_(1).qslide", "Talk_media", "Talk_media/image1.png", "Talk_media/image1_(1).png",
	}; !slices.Equal(got, want) {
		t.Errorf("tree = %v, want %v", got, want)
	}
}

func TestImportPptxToQslideLeavesNothingBehindWhenALaterSlideFails(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "Talk.pptx")
	// Slide 2 inflates past the XML cap, after slide 1's picture is stored.
	full := filepath.Join(f.root, "Talk.pptx")
	body, err := os.ReadFile(full)
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for _, part := range zr.File {
		if part.Name == "ppt/slides/slide2.xml" {
			w, _ := zw.Create(part.Name)
			_, _ = io.WriteString(w, "<p:sld>")
			for range pptxutil.MaxXMLPartBytes>>20 + 1 {
				_, _ = w.Write(bytes.Repeat([]byte(" "), 1<<20))
			}
			continue
		}
		if err := zw.Copy(part); err != nil {
			t.Fatal(err)
		}
	}
	_ = zw.Close()
	writeTestFile(t, f.root, "Talk.pptx", out.Bytes())

	params := f.params
	params.FilePath = "Talk.pptx"
	_, err = fileutil.ImportPptxToQslide(params)
	var unsupported *fileutil.UnsupportedError
	if !errors.As(err, &unsupported) {
		t.Fatalf("import = %v, want an UnsupportedError", err)
	}
	if got := f.tree(t); !slices.Equal(got, []string{"Talk.pptx"}) {
		t.Errorf("tree after a failed import = %v", got)
	}
}

func TestImportPptxToQslideRejectsOtherFiles(t *testing.T) {
	f := newImportFixture(t)
	writeTestFile(t, f.root, "notes.txt", []byte("hello"))
	writeTestFile(t, f.root, "Broken.pptx", []byte("not a zip"))
	for _, p := range []string{"notes.txt", "Broken.pptx"} {
		params := f.params
		params.FilePath = p
		_, err := fileutil.ImportPptxToQslide(params)
		var unsupported *fileutil.UnsupportedError
		if !errors.As(err, &unsupported) {
			t.Errorf("%s: %v, want an UnsupportedError", p, err)
		}
	}
	params := f.params
	params.FilePath = "Missing.pptx"
	if _, err := fileutil.ImportPptxToQslide(params); err == nil {
		t.Error("a missing file imported")
	}
	params.FilePath = "notes.txt"
	params.RootDir = "../outside"
	if _, err := fileutil.ImportPptxToQslide(params); err == nil {
		t.Error("an import climbed out of the files root")
	}
	if got := f.tree(t); !slices.Equal(got, []string{"Broken.pptx", "notes.txt"}) {
		t.Errorf("tree = %v", got)
	}
}

func TestIsPptxPath(t *testing.T) {
	for p, want := range map[string]bool{
		"a.pptx": true, "b.PPTX": true, "c.pptm": true, "d.ppsx": true, "e.ppt": false, "f.qslide": false,
	} {
		if got := fileutil.IsPptxPath(p); got != want {
			t.Errorf("IsPptxPath(%q) = %v", p, got)
		}
	}
}

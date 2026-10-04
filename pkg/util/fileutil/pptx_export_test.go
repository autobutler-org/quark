package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"image"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// pictureDeck shows a picture beside the deck, one in a private folder, one
// that climbs out of the files root, and an uploaded asset.
const pictureDeck = `{"schemaVersion":1,"title":"Talk","slides":[
	{"id":"s1","elements":[
		{"id":"a","type":"image","frame":{"x":0,"y":0,"width":100,"height":100},"source":"/talks/dog.png"},
		{"id":"b","type":"image","frame":{"x":0,"y":0,"width":100,"height":100},"source":"private/cat.png"},
		{"id":"c","type":"image","frame":{"x":0,"y":0,"width":100,"height":100},"source":"talks/../../etc/x.png"},
		{"id":"d","type":"image","frame":{"x":0,"y":0,"width":100,"height":100},"source":"asset:logo"}
	],"notes":"Hi"}]}`

// newPptxFixture is a files namespace holding files, by path.
func newPptxFixture(t *testing.T, files map[string][]byte) (string, fileutil.ExportPptxParams) {
	t.Helper()
	root := t.TempDir()
	for name, body := range files {
		full := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, body, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS failed: %v", err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files", MountPath: "/"}, fsys); err != nil {
		t.Fatalf("Register failed: %v", err)
	}
	return root, fileutil.ExportPptxParams{
		Ctx:      context.Background(),
		Registry: registry,
		CanRead:  func(p string) bool { return !strings.HasPrefix(p, "private/") },
	}
}

func smallPNG(t *testing.T) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewGray(image.Rect(0, 0, 4, 2))); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func TestExportQslideToPptxEmbedsOnlyReadablePictures(t *testing.T) {
	dog := smallPNG(t)
	root, params := newPptxFixture(t, map[string][]byte{
		"talks/Talk.qslide":  []byte(pictureDeck),
		"talks/dog.png":      dog,
		"private/cat.png":    smallPNG(t),
		"talks/unrelated.md": []byte("x"),
	})
	params.FilePath = "talks/Talk.qslide"
	var out bytes.Buffer
	params.Out = &out

	result, err := fileutil.ExportQslideToPptx(params)
	if err != nil {
		t.Fatalf("ExportQslideToPptx: %v", err)
	}
	if result.Slides != 1 || result.Pictures != 1 || result.MissingPictures != 3 {
		t.Errorf("result = %+v", result)
	}
	if got := fileutil.PptxExportName(params.FilePath); got != "Talk.pptx" {
		t.Errorf("PptxExportName = %q", got)
	}

	zr, err := zip.NewReader(bytes.NewReader(out.Bytes()), int64(out.Len()))
	if err != nil {
		t.Fatalf("not a zip: %v", err)
	}
	var media []string
	for _, f := range zr.File {
		if strings.HasPrefix(f.Name, "ppt/media/") {
			media = append(media, f.Name)
			rc, _ := f.Open()
			body, _ := io.ReadAll(rc)
			rc.Close()
			if !bytes.Equal(body, dog) {
				t.Errorf("%s is not dog.png", f.Name)
			}
		}
	}
	if !slices.Equal(media, []string{"ppt/media/image1.png"}) {
		t.Errorf("media = %v, want only dog.png", media)
	}

	// Export only reads: the folder holds what it held.
	entries, err := os.ReadDir(filepath.Join(root, "talks"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Errorf("folder after export has %d entries, want 3", len(entries))
	}
}

func TestExportQslideToPptxRefusesWithOutUntouched(t *testing.T) {
	_, params := newPptxFixture(t, map[string][]byte{
		"Broken.qslide": []byte("not json"),
		"Newer.qslide":  []byte(`{"schemaVersion":99,"slides":[]}`),
		"notes.txt":     []byte("hello"),
		"Dir.qslide/x":  []byte("x"),
	})
	for _, tc := range []struct {
		path        string
		unsupported bool
	}{
		{"Broken.qslide", true},
		{"Newer.qslide", true},
		{"notes.txt", true},
		{"Dir.qslide", true},
		{"Missing.qslide", false},
	} {
		var out bytes.Buffer
		params.FilePath = tc.path
		params.Out = &out
		_, err := fileutil.ExportQslideToPptx(params)
		var unsupported *fileutil.UnsupportedError
		var notFound *fileutil.NotFoundError
		switch {
		case tc.unsupported && !errors.As(err, &unsupported):
			t.Errorf("%s: err = %v, want UnsupportedError", tc.path, err)
		case !tc.unsupported && !errors.As(err, &notFound):
			t.Errorf("%s: err = %v, want NotFoundError", tc.path, err)
		}
		if out.Len() != 0 {
			t.Errorf("%s: wrote %d bytes before failing", tc.path, out.Len())
		}
	}
}

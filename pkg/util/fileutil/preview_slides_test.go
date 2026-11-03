package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func newSlidesFixture(t *testing.T) (string, vfs.Registry) {
	t.Helper()
	root, registry := newDocumentFixture(t, documentParts(helloBody))
	seedPptx(t, root, "talk.pptx")
	return root, registry
}

func TestPreviewSlidesNamesPicturesInPlace(t *testing.T) {
	root, registry := newSlidesFixture(t)
	var out bytes.Buffer
	result, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
		Ctx: context.Background(), Registry: registry, FilePath: "talk.pptx", Out: &out,
	})
	if err != nil {
		t.Fatalf("preview: %v", err)
	}
	if result.Slides != 2 {
		t.Errorf("slides = %d, want 2", result.Slides)
	}
	var deck struct {
		Slides []struct {
			Elements []struct{ Source string }
			Notes    string
		}
	}
	if err := json.Unmarshal(out.Bytes(), &deck); err != nil {
		t.Fatalf("not JSON: %v\n%s", err, out.String())
	}
	if len(deck.Slides) != 2 || deck.Slides[1].Notes != "Thanks" {
		t.Fatalf("deck = %+v", deck)
	}
	source := deck.Slides[0].Elements[0].Source
	if source != "part:ppt/media/image1.png" || deck.Slides[1].Elements[0].Source != source {
		t.Errorf("sources = %q, %q", source, deck.Slides[1].Elements[0].Source)
	}

	// The reference is one the part endpoint serves.
	part, err := fileutil.OpenDocumentPart(fileutil.OpenDocumentPartParams{
		Ctx: context.Background(), Registry: registry, FilePath: "talk.pptx", Part: source[len(fileutil.PackagePartPrefix):],
	})
	if err != nil {
		t.Fatalf("open the part: %v", err)
	}
	body, err := io.ReadAll(part.Reader)
	if closeErr := part.Close(); err != nil || closeErr != nil || part.ContentType != "image/png" || !bytes.HasPrefix(body, []byte("\x89PNG")) {
		t.Errorf("part: read %v, close %v, %s", err, closeErr, part.ContentType)
	}

	// Nothing was stored: no media folder beside it.
	if _, err := os.Stat(root + "/talk_media"); !os.IsNotExist(err) {
		t.Errorf("a preview stored media: %v", err)
	}
}

func TestPreviewSlidesRefusesWhatIsNotAPresentation(t *testing.T) {
	root, registry := newSlidesFixture(t)
	writeTestFile(t, root, "fake.pptx", []byte("plain text"))
	for _, name := range []string{"fake.pptx", "report.docx"} {
		var out bytes.Buffer
		_, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
			Ctx: context.Background(), Registry: registry, FilePath: name, Out: &out,
		})
		var unsupported *fileutil.UnsupportedError
		if !errors.As(err, &unsupported) || out.Len() != 0 {
			t.Errorf("%s: err = %v, wrote %d bytes; want UnsupportedError before any output", name, err, out.Len())
		}
	}
}

func TestPreviewSlidesStopsWhenCanceled(t *testing.T) {
	_, registry := newSlidesFixture(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
		Ctx: ctx, Registry: registry, FilePath: "talk.pptx", Out: io.Discard,
	})
	if !errors.Is(err, context.Canceled) {
		t.Errorf("err = %v, want context.Canceled", err)
	}
}

func TestOpenDocumentPartServesPptxMediaOnly(t *testing.T) {
	_, registry := newSlidesFixture(t)
	for _, part := range []string{"ppt/slides/slide1.xml", "ppt/media/../presentation.xml", "word/media/image1.png", "ppt/media/"} {
		var notFound *fileutil.NotFoundError
		if _, err := fileutil.OpenDocumentPart(fileutil.OpenDocumentPartParams{
			Ctx: context.Background(), Registry: registry, FilePath: "talk.pptx", Part: part,
		}); !errors.As(err, &notFound) {
			t.Errorf("part %q: err = %v, want NotFoundError", part, err)
		}
	}
}

func TestPreviewSlidesSkipsAPictureTooLarge(t *testing.T) {
	root, registry := newSlidesFixture(t)
	// Swap the picture for one that declares more than the picture limit.
	body, err := os.ReadFile(filepath.Join(root, "talk.pptx"))
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	var huge bytes.Buffer
	zw := zip.NewWriter(&huge)
	for _, f := range zr.File {
		if f.Name == "ppt/media/image1.png" {
			w, err := zw.CreateRaw(&zip.FileHeader{
				Name: f.Name, Method: zip.Store, UncompressedSize64: pptxutil.MaxImageBytes + 1, CompressedSize64: 4,
			})
			if err != nil {
				t.Fatal(err)
			}
			_, _ = w.Write([]byte("\x89PNG"))
			continue
		}
		if err := zw.Copy(f); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, root, "huge.pptx", huge.Bytes())

	var out bytes.Buffer
	result, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
		Ctx: context.Background(), Registry: registry, FilePath: "huge.pptx", Out: &out,
	})
	if err != nil {
		t.Fatalf("preview: %v", err)
	}
	if result.Slides != 2 {
		t.Errorf("slides = %d, want 2", result.Slides)
	}
	if !slices.ContainsFunc(result.Warnings, func(w pptxutil.ImportWarning) bool {
		return strings.Contains(w.Message, "larger than")
	}) {
		t.Errorf("warnings = %+v, want the picture named as too large", result.Warnings)
	}
	if strings.Contains(out.String(), fileutil.PackagePartPrefix) {
		t.Errorf("the oversized picture was referenced: %s", out.String())
	}
}

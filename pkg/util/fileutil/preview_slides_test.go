package fileutil_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
)

// slidesPreview is what a slides preview decodes to.
type slidesPreview struct {
	Deck struct {
		Title  string `json:"title"`
		Slides []struct {
			Elements []struct {
				Source string `json:"source"`
			} `json:"elements"`
			Notes string `json:"notes"`
		} `json:"slides"`
	} `json:"deck"`
	Warnings []struct {
		Slide   int    `json:"slide"`
		Message string `json:"message"`
	} `json:"warnings"`
}

func previewSlidesParams(f importFixture, filePath string, out io.Writer) fileutil.PreviewSlidesParams {
	return fileutil.PreviewSlidesParams{
		Ctx: context.Background(), Registry: f.params.Registry, FilePath: filePath, Out: out,
	}
}

func TestPreviewSlidesStreamsTheDeckWithPicturesNamedInPlace(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "decks/Talk.pptx")
	before := f.tree(t)

	var out bytes.Buffer
	result, err := fileutil.PreviewSlides(previewSlidesParams(f, "decks/Talk.pptx", &out))
	if err != nil {
		t.Fatalf("preview: %v", err)
	}
	if result.Slides != 2 || result.Pictures != 1 {
		t.Errorf("result = %+v", result)
	}
	var got slidesPreview
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("not one JSON object: %v\n%s", err, out.String())
	}
	if got.Deck.Title != "Talk" || len(got.Deck.Slides) != 2 || got.Deck.Slides[1].Notes != "Thanks" {
		t.Fatalf("deck = %+v", got.Deck)
	}
	ref := got.Deck.Slides[0].Elements[0].Source
	if !strings.HasPrefix(ref, "part:ppt/media/") || got.Deck.Slides[1].Elements[0].Source != ref {
		t.Errorf("picture references = %q, %q", ref, got.Deck.Slides[1].Elements[0].Source)
	}
	if got.Warnings == nil || len(got.Warnings) != 0 {
		t.Errorf("warnings = %+v, want an empty list", got.Warnings)
	}
	if after := f.tree(t); strings.Join(after, ",") != strings.Join(before, ",") {
		t.Errorf("a preview wrote files: %v -> %v", before, after)
	}

	// The reference is one the part endpoint serves.
	opened, err := fileutil.OpenDocumentPart(fileutil.OpenDocumentPartParams{
		Ctx: context.Background(), Registry: f.params.Registry, FilePath: "decks/Talk.pptx",
		Part: strings.TrimPrefix(ref, fileutil.SlidePartPrefix),
	})
	if err != nil {
		t.Fatalf("open %s: %v", ref, err)
	}
	defer opened.Close()
	body, err := io.ReadAll(opened.Reader)
	if err != nil || !bytes.HasPrefix(body, []byte("\x89PNG")) || opened.ContentType != "image/png" {
		t.Errorf("part = %d bytes, %q, %v", len(body), opened.ContentType, err)
	}
}

func TestPreviewSlidesWritesNothingForAFileThatIsNotAPresentation(t *testing.T) {
	f := newImportFixture(t)
	writeTestFile(t, f.root, "Fake.pptx", []byte("not a zip"))
	writeTestFile(t, f.root, "Old.ppt", []byte("legacy"))

	for _, name := range []string{"Fake.pptx", "Old.ppt"} {
		var out bytes.Buffer
		_, err := fileutil.PreviewSlides(previewSlidesParams(f, name, &out))
		var unsupported *fileutil.UnsupportedError
		if !errors.As(err, &unsupported) {
			t.Errorf("%s: err = %v, want UnsupportedError", name, err)
		}
		if out.Len() != 0 {
			t.Errorf("%s: wrote %q before failing", name, out.String())
		}
	}

	var out bytes.Buffer
	_, err := fileutil.PreviewSlides(previewSlidesParams(f, "Missing.pptx", &out))
	var notFound *fileutil.NotFoundError
	if !errors.As(err, &notFound) || out.Len() != 0 {
		t.Errorf("missing: err = %v, wrote %q", err, out.String())
	}
}

func TestPreviewSlidesStopsAtItsDeadline(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "Talk.pptx")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	params := previewSlidesParams(f, "Talk.pptx", io.Discard)
	params.Ctx = ctx
	if _, err := fileutil.PreviewSlides(params); err == nil {
		t.Error("a canceled preview succeeded")
	}
}

func TestOpenDocumentPartServesOnlyThePresentationsMediaFolder(t *testing.T) {
	f := newImportFixture(t)
	seedPptx(t, f.root, "Talk.pptx")

	for _, part := range []string{
		"ppt/presentation.xml", "ppt/slides/slide1.xml", "[Content_Types].xml",
		"ppt/media/../presentation.xml", "word/media/image1.png", "ppt/media/", "ppt/media/missing.png",
	} {
		_, err := fileutil.OpenDocumentPart(fileutil.OpenDocumentPartParams{
			Ctx: context.Background(), Registry: f.params.Registry, FilePath: "Talk.pptx", Part: part,
		})
		var notFound *fileutil.NotFoundError
		if !errors.As(err, &notFound) {
			t.Errorf("%s: err = %v, want NotFoundError", part, err)
		}
	}
}

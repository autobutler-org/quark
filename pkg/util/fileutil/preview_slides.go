package fileutil

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// SlidePartPrefix marks a picture reference in a slides preview as an entry
// inside the presentation itself, served by the part endpoint, rather than a
// file: "part:ppt/media/image3.png".
const SlidePartPrefix = "part:"

// PreviewSlidesParams says which presentation to preview and where the deck
// goes.
type PreviewSlidesParams struct {
	// Ctx ends the preview early when it is done.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// FilePath is the files-relative path of the presentation.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Out receives {"deck": <.qslide>, "warnings": [...]}. Nothing is
	// written to it until the presentation has opened, so a file that cannot
	// be previewed fails before the first byte.
	Out io.Writer
}

// SlidesPreview is the shape of what [PreviewSlides] writes. It is never
// built whole: the deck is streamed as it is read.
type SlidesPreview struct {
	// Deck is the presentation as .qslide JSON.
	Deck map[string]any `json:"deck" swaggertype:"object"`
	// Warnings lists what was left out or approximated, slide by slide.
	Warnings []SlideWarning `json:"warnings"`
}

// SlideWarning is one thing a slides preview left out or approximated.
type SlideWarning struct {
	// Slide is the slide's number in show order, from 1; 0 is the deck.
	Slide int `json:"slide"`
	// Message says what, in a sentence a user can read.
	Message string `json:"message"`
}

// PreviewSlidesResult reports what a preview came to.
type PreviewSlidesResult struct {
	// Slides and Pictures are what the deck holds.
	Slides   int
	Pictures int
	// Warnings lists what was left out or approximated, slide by slide.
	Warnings []pptxutil.ImportWarning
}

// PreviewSlides streams a PowerPoint presentation as the .qslide deck the
// presentation viewer draws (docs/architecture/read-only-documents.md,
// Slides). It is the import's reader with nothing stored: each picture is
// named in place, as [SlidePartPrefix] and its entry in the package, and
// streamed past into io.Discard, which is the read the import's size limits
// are counted on. Out gets {"deck": ..., "warnings": [...]}, the deck
// written slide by slide as it is read and the warnings after it, since they
// are known only at the end. A failure before output begins is a
// [NotFoundError] or an [UnsupportedError]; one after it leaves the object
// unclosed, which is how the client tells a cut-off deck from a whole one.
func PreviewSlides(params PreviewSlidesParams) (PreviewSlidesResult, error) {
	if !IsPptxPath(params.FilePath) {
		return PreviewSlidesResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a presentation Quark can show: %s", filepath.Base(params.FilePath)),
		}
	}
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return PreviewSlidesResult{}, err
	}
	source, size, closer, err := openXlsx(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return PreviewSlidesResult{}, err
	}
	defer closer.Close()

	out := &envelopeWriter{w: params.Out, prefix: `{"deck":`}
	imported, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{
		Source: ctxReaderAt{ctx: params.Ctx, r: source},
		Size:   size,
		Out:    out,
		StoreMedia: func(part, _ string, r io.Reader) (string, error) {
			if _, err := io.Copy(io.Discard, r); err != nil {
				return "", err
			}
			return SlidePartPrefix + part, nil
		},
		Title: titleFromPath(params.FilePath),
	})
	if err != nil {
		return PreviewSlidesResult{}, importError(err)
	}
	warnings := make([]SlideWarning, 0, len(imported.Warnings))
	for _, w := range imported.Warnings {
		warnings = append(warnings, SlideWarning(w))
	}
	tail, err := json.Marshal(warnings)
	if err != nil {
		return PreviewSlidesResult{}, err
	}
	if _, err := fmt.Fprintf(out, `,"warnings":%s}`+"\n", tail); err != nil {
		return PreviewSlidesResult{}, err
	}
	return PreviewSlidesResult{
		Slides:   imported.Slides,
		Pictures: imported.Pictures,
		Warnings: imported.Warnings,
	}, nil
}

// titleFromPath is a presentation's title when the package names none: its
// file name without the extension, as an import names the .qslide.
func titleFromPath(filePath string) string {
	base := filepath.Base(filePath)
	return base[:len(base)-len(filepath.Ext(base))]
}

// envelopeWriter writes prefix ahead of the first byte, so a preview that
// fails before writing anything leaves its writer untouched.
type envelopeWriter struct {
	w       io.Writer
	prefix  string
	started bool
}

func (e *envelopeWriter) Write(p []byte) (int, error) {
	if !e.started {
		e.started = true
		if _, err := io.WriteString(e.w, e.prefix); err != nil {
			return 0, err
		}
	}
	return e.w.Write(p)
}

// ctxReaderAt fails every read once ctx is done, which is how a reader that
// takes no context is stopped at a deadline.
type ctxReaderAt struct {
	ctx context.Context
	r   io.ReaderAt
}

func (c ctxReaderAt) ReadAt(p []byte, off int64) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.r.ReadAt(p, off)
}

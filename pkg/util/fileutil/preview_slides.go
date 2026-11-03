package fileutil

import (
	"context"
	"fmt"
	"io"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// PackagePartPrefix starts the picture reference a slides preview writes:
// part:ppt/media/image3.png names an entry GET /previews/part serves.
const PackagePartPrefix = "part:"

// PreviewSlidesParams says which presentation to preview and where its
// .qslide JSON goes.
type PreviewSlidesParams struct {
	// Ctx ends the preview early when it is done, at the next slide or
	// picture.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// FilePath is the files-relative path of the presentation.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Out receives the .qslide JSON, a slide at a time. Nothing is written
	// to it until the package has opened, so a file that is not a
	// presentation fails before the first byte.
	Out io.Writer
}

// PreviewSlidesResult reports what a preview wrote.
type PreviewSlidesResult struct {
	// Slides is the number of slides written.
	Slides int
	// Warnings lists what was left out or approximated, slide by slide, as
	// an import reports it.
	Warnings []pptxutil.ImportWarning
}

// PreviewSlides streams a PowerPoint file as the .qslide JSON the
// presentation viewer draws (docs/architecture/read-only-documents.md,
// presentations). It is an import that stores nothing: each picture is
// named by its entry in the package, as [PackagePartPrefix] followed by the
// entry, and the bytes stay in the file. The reader each picture comes with
// is drained to io.Discard rather than dropped, because the import checks its
// size limits against what is read: a deck shows the pictures "Open as Quark
// slides" would bring in, and no others. Draining streams; nothing is held.
//
// A failure before output begins is a [NotFoundError] or an
// [UnsupportedError]; one after it leaves the JSON unfinished.
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
	source, size, closer, err := openZip(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return PreviewSlidesResult{}, err
	}
	defer closer.Close()

	base := path.Base(cleanRelPath(params.FilePath))
	result, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{
		Source: source,
		Size:   size,
		// pptxutil takes no context, so the writer and the picture
		// callback are where a deadline stops it.
		Out: ctxWriter{ctx: params.Ctx, w: params.Out},
		StoreMedia: func(part, _ string, r io.Reader) (string, error) {
			if err := params.Ctx.Err(); err != nil {
				return "", err
			}
			if _, err := io.Copy(io.Discard, r); err != nil {
				return "", err
			}
			return PackagePartPrefix + part, nil
		},
		Title: strings.TrimSuffix(base, filepath.Ext(base)),
	})
	if err != nil {
		return PreviewSlidesResult{}, importError(err)
	}
	return PreviewSlidesResult{Slides: result.Slides, Warnings: result.Warnings}, nil
}

// ctxWriter fails a write once its context is done.
type ctxWriter struct {
	ctx context.Context
	w   io.Writer
}

func (c ctxWriter) Write(p []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.w.Write(p)
}

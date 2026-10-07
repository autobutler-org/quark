package fileutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ExportPptxParams is one .qslide to stream out as a .pptx.
type ExportPptxParams struct {
	// Ctx bounds the reads.
	Ctx context.Context
	// Registry reads through the VFS when no serial routes past it.
	Registry vfs.Registry
	// Storage serves the request for a device-scoped path, or when there is
	// no VFS namespace to route to.
	Storage *storageutil.StorageService
	// FilePath is the files-relative path of the .qslide.
	FilePath string
	// Serial identifies the device, empty for the internal one. Pictures are
	// read from the same device.
	Serial string
	// CanRead reports whether the caller may read a picture the presentation
	// shows, by its files-relative path. A picture it refuses is left out as
	// one that is missing would be, so an export never carries a file its
	// caller could not download. Nil refuses every picture.
	CanRead func(filePath string) bool
	// Out receives the presentation as each slide is read. Nothing is written
	// to it before the first slide has been read, so a source that is
	// missing or not a .qslide fails with Out untouched.
	Out io.Writer
}

// ExportPptxResult reports the presentation that was written.
type ExportPptxResult struct {
	// Slides is the number of slides written.
	Slides int
	// Pictures is the number of distinct pictures embedded.
	Pictures int
	// MissingPictures is the number of distinct pictures left as
	// placeholders: missing, unreadable to the caller, or not a format
	// PowerPoint shows.
	MissingPictures int
}

// ExportQslideToPptx streams the .qslide at params.FilePath to params.Out as
// a .pptx that PowerPoint, Keynote, LibreOffice and Google Slides open
// (#1172). Pictures are read from the files they name and copied into the
// package as it is written. It only reads: nothing is written beside the
// presentation, so the file tree does not change and there is no event to
// publish. What carries across is [pptxutil.ExportQslide]'s to say.
func ExportQslideToPptx(params ExportPptxParams) (ExportPptxResult, error) {
	if !strings.EqualFold(filepath.Ext(params.FilePath), ".qslide") {
		return ExportPptxResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a Quark presentation: %s", filepath.Base(params.FilePath)),
		}
	}

	source, _, err := openExportFile(params.Ctx, params.Registry, params.Storage, params.FilePath, params.Serial)
	if err != nil {
		return ExportPptxResult{}, err
	}
	defer source.Close()

	exported, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: source,
		Out:    params.Out,
		OpenImage: func(ref string) (io.ReadCloser, int64, error) {
			imagePath, ok := slideImagePath(ref)
			if !ok || params.CanRead == nil || !params.CanRead(imagePath) {
				return nil, 0, errNoSlideImage
			}
			return openExportFile(params.Ctx, params.Registry, params.Storage, imagePath, params.Serial)
		},
	})
	if errors.Is(err, pptxutil.ErrNotQslide) || errors.Is(err, pptxutil.ErrTooLarge) {
		err = &UnsupportedError{Err: err}
	}
	return ExportPptxResult{
		Slides:          exported.Slides,
		Pictures:        exported.Pictures,
		MissingPictures: exported.MissingPictures,
	}, err
}

// PptxExportName is the name to offer the export of the .qslide at filePath
// under: the presentation's own, with .pptx in place of .qslide.
func PptxExportName(filePath string) string {
	base := filepath.Base(filePath)
	return strings.TrimSuffix(base, filepath.Ext(base)) + ".pptx"
}

// errNoSlideImage is a picture the export leaves out.
var errNoSlideImage = errors.New("picture not available to export")

// slideImagePath is the files-relative path a picture reference names, as the
// slide editor reads it: leading slashes dropped. An uploaded-asset reference
// (asset:<id>) names no file, and a path that climbs out of the files root
// names none the caller may read.
func slideImagePath(ref string) (string, bool) {
	ref = strings.TrimLeft(strings.TrimSpace(ref), "/")
	if ref == "" || strings.HasPrefix(ref, "asset:") {
		return "", false
	}
	cleaned := path.Clean(ref)
	if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return "", false
	}
	return cleaned, true
}

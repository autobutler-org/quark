package fileutil

import (
	"context"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/odputil"
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// ImportOdpParams imports one OpenDocument presentation as a .qslide the
// Slides editor opens. Its fields are [ImportPptxParams]', with FilePath
// naming the .odp.
type ImportOdpParams ImportPptxParams

// ImportOdpResult reports the .qslide that was written. Its fields are
// [ImportPptxResult]'.
type ImportOdpResult ImportPptxResult

// ImportOdpToQslide reads the OpenDocument presentation at params.FilePath
// and writes it as a .qslide in params.RootDir, named after it, exactly as
// [ImportPptxToQslide] imports a PowerPoint file: its pictures copied into a
// <name>_media folder beside it, nothing written over, everything streamed,
// and nothing left behind by a file that fails partway. The .odp itself is
// left untouched.
func ImportOdpToQslide(params ImportOdpParams) (ImportOdpResult, error) {
	if !IsOdpPath(params.FilePath) {
		return ImportOdpResult{}, &UnsupportedError{
			Err: fmt.Errorf("not an OpenDocument presentation Quark can import: %s", filepath.Base(params.FilePath)),
		}
	}
	result, err := importSlides(ImportPptxParams(params), readOdp)
	return ImportOdpResult(result), err
}

// IsOdpPath reports whether a path names an OpenDocument presentation this
// can import. The .otp template is not one.
func IsOdpPath(filePath string) bool {
	return strings.EqualFold(filepath.Ext(filePath), ".odp")
}

// readOdp is the [slideReader] for OpenDocument presentations.
func readOdp(ctx context.Context, source io.ReaderAt, size int64, out io.Writer,
	store pptxutil.StoreMediaFunc, title string) (slideOutcome, error) {
	imported, err := odputil.ImportOdp(odputil.ImportOdpParams{
		Ctx:        ctx,
		Source:     source,
		Size:       size,
		Out:        out,
		StoreMedia: odputil.StoreMediaFunc(store),
		Title:      title,
	})
	warnings := make([]SlideWarning, 0, len(imported.Warnings))
	for _, w := range imported.Warnings {
		warnings = append(warnings, SlideWarning(w))
	}
	return slideOutcome{Slides: imported.Slides, Pictures: imported.Pictures, Warnings: warnings}, err
}

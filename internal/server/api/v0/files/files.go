// Package v0_files serves /api/v0/files: listing, searching and stat-ing files, uploads (including resumable upload
// sessions), downloads and archive views, moves, deletes and new folders, spreadsheet conversions between .xlsx
// and .qsheet (the .xlsx export streamed back as a download), and a presentation's .pptx export and import. The
// .pptx routes (GET /files/export/pptx, POST /files/import/pptx) are a 404 while an admin has the slides feature
// flag turned off (PUT /settings/features/slides).
package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// FileNodeJSON is a JSON-serializable representation of a file node. The
// listings build it in fileutil; the alias is what the endpoint annotations
// name it by.
type FileNodeJSON = fileutil.FileNode

// ConvertXlsxJSON reports the .qsheet a workbook was converted into, and what
// it holds. The client opens Path; the counts are what it tells the user it
// brought across.
type ConvertXlsxJSON struct {
	Path  string `json:"path"`
	Tabs  int    `json:"tabs"`
	Rows  int    `json:"rows"`
	Cells int    `json:"cells"`
}

// ImportPptxJSON reports the .qslide a PowerPoint file was imported as. The
// client opens Path and shows the warnings: what the import left out or
// approximated.
type ImportPptxJSON struct {
	Path string `json:"path"`
	// MediaDir is the folder the pictures were stored in, empty when the
	// presentation has none.
	MediaDir string              `json:"mediaDir,omitempty"`
	Slides   int                 `json:"slides"`
	Pictures int                 `json:"pictures"`
	Warnings []ImportWarningJSON `json:"warnings"`
}

// ImportWarningJSON is one thing an import left out or approximated, on the
// slide numbered Slide from 1; 0 is the whole presentation.
type ImportWarningJSON struct {
	Slide   int    `json:"slide"`
	Message string `json:"message"`
}

func NewRouter() serverutil.Router {
	return &router{}
}

// NewSlidesRouter returns the routes that export and import a presentation
// as a PowerPoint file. Mount it behind
// middleware.RequireFeatureEnabled(featureflagutil.Slides).
func NewSlidesRouter() serverutil.Router {
	return &slidesRouter{}
}

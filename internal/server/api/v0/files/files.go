// Package v0_files serves /api/v0/files: listing, searching and stat-ing files, uploads (including resumable upload
// sessions), downloads and archive views, and moves, deletes and new folders.
package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// FileNodeJSON is a JSON-serializable representation of a file node. The
// listings build it in fileutil; the alias is what the endpoint annotations
// name it by.
type FileNodeJSON = fileutil.FileNode

// FileNodeWithTimeJSON extends FileNodeJSON with modification time for sorting/display
type FileNodeWithTimeJSON = fileutil.FileNodeWithTime

// ConvertXlsxJSON reports the .qsheet a workbook was converted into, and what
// it holds. The client opens Path; the counts are what it tells the user it
// brought across.
type ConvertXlsxJSON struct {
	Path  string `json:"path"`
	Tabs  int    `json:"tabs"`
	Rows  int    `json:"rows"`
	Cells int    `json:"cells"`
}

func NewRouter() serverutil.Router {
	return &router{}
}

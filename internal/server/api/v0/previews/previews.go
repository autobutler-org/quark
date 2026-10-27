// Package v0_previews serves /api/v0/previews, read-only views of office documents the client cannot open itself:
// a word-processing document as a stream of blocks (GET /previews/document), a presentation as a .qslide deck
// (GET /previews/slides), a workbook as a .qsheet (GET /previews/sheet), one image from inside a document or
// presentation (GET /previews/part), and the properties a document carries (GET /previews/properties). Every route
// checks read access on the document and writes nothing. No route is admin-only.
package v0_previews

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

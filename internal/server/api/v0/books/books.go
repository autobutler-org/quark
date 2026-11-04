// Package v0_books serves GET /api/v0/books, which lists the PDF and EPUB files on every managed drive.
package v0_books

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

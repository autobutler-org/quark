// Package v0_books serves /api/v0/books, which finds the books in the files directory.
package v0_books

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// Router for /api/v0/books endpoints
// Registers the /books route

func NewRouter() serverutil.Router {
	return &router{}
}

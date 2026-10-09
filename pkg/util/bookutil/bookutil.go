// Package bookutil finds the book files (PDF and EPUB) in a files namespace.
package bookutil

import (
	"context"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// FindBooksParams names the namespace to search for books.
type FindBooksParams struct {
	// FS is the files namespace to walk, the whole of it.
	FS vfs.VFS
}

// FindBooksResult is every book found, in walk order.
type FindBooksResult struct {
	// Books are the PDF and EPUB files; each Path is relative to the
	// namespace root.
	Books []vfs.FileInfo
}

// FindBooks walks the whole namespace through vfs.Walk and returns its PDF and
// EPUB files. The walk streams and is best-effort: an unreadable folder is
// skipped, and the trash and other internal names are never visited. A
// namespace whose root is missing is an error.
func FindBooks(ctx context.Context, params FindBooksParams) (FindBooksResult, error) {
	return findBooks(ctx, params)
}

package bookutil

import (
	"context"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func findBooks(ctx context.Context, params FindBooksParams) (FindBooksResult, error) {
	result := FindBooksResult{Books: make([]vfs.FileInfo, 0)}
	err := vfs.Walk(ctx, params.FS, "", func(fi vfs.FileInfo) error {
		if !fi.IsDir && isBook(fi.Name) {
			result.Books = append(result.Books, fi)
		}
		return nil
	})
	if err != nil {
		return FindBooksResult{}, fmt.Errorf("finding books: %w", err)
	}
	return result, nil
}

// isBook reports whether name is a PDF or an EPUB.
func isBook(name string) bool {
	fileType := storageutil.DetermineFileTypeFromPath(name)
	return fileType == storageutil.FileTypePDF || fileType == storageutil.FileTypeEpub
}

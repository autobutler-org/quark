package v0_books

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/bookutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

type BookJSON struct {
	RelPath  string `json:"relPath"`
	FileName string `json:"fileName"`
	Size     int64  `json:"size"`
	Type     string `json:"type"`
	MTime    int64  `json:"mtime"`
}

// listBooks godoc
// @Summary List books
// @Description Finds all books in the files directory
// @Tags books
// @Produce json
// @Success 200 {array} BookJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /books [get]
func listBooks(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	// Books are listed from the internal drive's namespace alone, which
	// answers to the empty serial (#2647).
	registry := deps.VFSRegistry()
	if registry == nil {
		return serverutil.InternalServerError(nil)
	}
	fsys, ok := registry.Get(vfs.FilesNamespace(""))
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	found, err := bookutil.FindBooks(c.Request.Context(), bookutil.FindBooksParams{FS: fsys})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]BookJSON, 0, len(found.Books))
	for _, book := range found.Books {
		if !access.Check("", book.Path, accessutil.Read).Readable {
			continue
		}
		result = append(result, BookJSON{
			RelPath:  book.Path,
			FileName: book.Name,
			Size:     book.Size,
			MTime:    book.ModTime.Unix(),
			Type:     string(storageutil.DetermineFileTypeFromPath(book.Name)),
		})
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listBooksRoute = serverutil.ApiRoute(
	"GET", "/books", listBooks,
)

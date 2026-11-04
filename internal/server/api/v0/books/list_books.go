package v0_books

import (
	"maps"
	"slices"

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
	// DeviceSerial is the drive the book is on. Empty for the internal drive.
	DeviceSerial string `json:"deviceSerial"`
}

// listBooks godoc
// @Summary List books
// @Description Finds every PDF and EPUB on every managed drive. deviceSerial is empty for the internal drive.
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
	// Every managed drive. The internal drive answers to the empty serial
	// (#2647, #3712). A server with no internal namespace is misconfigured.
	registry := deps.VFSRegistry()
	namespaces := vfs.FilesNamespaces(registry)
	if _, ok := namespaces[""]; !ok {
		return serverutil.InternalServerError(nil)
	}

	result := make([]BookJSON, 0)
	for _, serial := range slices.Sorted(maps.Keys(namespaces)) {
		found, err := bookutil.FindBooks(c.Request.Context(), bookutil.FindBooksParams{FS: namespaces[serial]})
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		for _, book := range found.Books {
			if !access.Check(serial, book.Path, accessutil.Read).Readable {
				continue
			}
			result = append(result, BookJSON{
				RelPath:      book.Path,
				FileName:     book.Name,
				Size:         book.Size,
				MTime:        book.ModTime.Unix(),
				Type:         string(storageutil.DetermineFileTypeFromPath(book.Name)),
				DeviceSerial: serial,
			})
		}
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listBooksRoute = serverutil.ApiRoute(
	"GET", "/books", listBooks,
)

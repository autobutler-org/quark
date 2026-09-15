package v0_books

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/bookutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

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
	rootDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.NewResponse().WithStatusCode(500).WithError(err)
	}
	books, err := bookutil.FindAllBooksRecursively(rootDir)
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]BookJSON, 0, len(books))
	for _, book := range books {
		// The walk covers the internal drive, which answers to the empty serial.
		if !access.Check("", book.RelPath, accessutil.Read).Readable {
			continue
		}
		info := book.FileInfo
		fileType := storageutil.DetermineFileTypeFromPath(info.Name())
		result = append(result, BookJSON{
			RelPath:  book.RelPath,
			FileName: info.Name(),
			Size:     info.Size(),
			MTime:    info.ModTime().Unix(),
			Type:     string(fileType),
		})
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listBooksRoute = serverutil.ApiRoute(
	"GET", "/books", listBooks,
)

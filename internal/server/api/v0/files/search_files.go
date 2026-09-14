package v0_files

import (
	"errors"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// searchFiles godoc
// @Summary Searches for files
// @Schemes http https
// @Description searches for a file across all managed devices for the given search term. If deviceSerial is empty, search across all devices. Otherwise, only for the specified device
// @Tags files
// @Produce json
// @Success 200 {array} FileNodeJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Param query query string false "Search term to find"
// @Param serial query string false "Device serial number to filter by"
// @Router /files/search [get]
func searchFiles(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := fileutil.SearchFiles(fileutil.SearchFilesParams{
		Ctx:      c.Request.Context(),
		Index:    deps.FileIndex(),
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		Query:    strings.TrimSpace(c.Query("query")),
		Serials:  c.QueryArray("serial"),
		Access:   access,
	})
	if err != nil {
		if errors.Is(err, fileutil.ErrNoFilesNamespace) {
			// A registry without the namespace is a misconfigured server, not
			// something to describe to the client.
			return serverutil.InternalServerError(nil)
		}
		return fileError(err)
	}
	return serverutil.Ok().WithData(result.Files)
}

var searchFilesRoute = serverutil.ApiRoute(
	"GET", "/files/search", func(c *gin.Context) *serverutil.Response {
		return searchFiles(c)
	},
)

package v0_photos

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listDuplicates godoc
// @Summary List duplicate photos
// @Description Returns groups of exact duplicates (same SHA-256 content hash) and near-duplicates (perceptual dHash Hamming distance within threshold). Requires photo hashes to have been computed via the thumbnail or hash-index endpoints.
// @Tags photos
// @Produce json
// @Param threshold query int false "Hamming distance threshold for near-duplicates (default 10, max 20)"
// @Success 200 {object} object{groups=[]photoutil.DuplicateGroup}
// @Failure 500 {object} serverutil.Response
// @Router /photos/duplicates [get]
func listDuplicates(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(fmt.Errorf("dependencies not found in context"))
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	result, err := photoutil.ListDuplicates(photoutil.ListDuplicatesParams{
		Ctx:       c.Request.Context(),
		Queries:   deps.Database().Queries,
		Threshold: photoutil.ParseDuplicateThreshold(c.Query("threshold")),
		Access:    access,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(gin.H{"groups": result.Groups})
}

var listDuplicatesRoute = serverutil.ApiRoute("GET", "/photos/duplicates", listDuplicates)

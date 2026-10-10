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
// @Description Returns groups of duplicate photos, each photo in at most one group. A group is exact when every photo shares a SHA-256 content hash, and near when their perceptual dHashes are within the threshold. Each group carries maxDistance, the largest Hamming distance between any two of its dHashes (0 for exact). Exact groups come first, then near groups by ascending maxDistance; ties sort by first photo, and photos within a group by device, then path. Photos are hashed when a thumbnail is rendered or uploaded, and a pass at server start hashes the rest of the library; trashed photos and photos no longer on disk are left out.
// @Tags photos
// @Produce json
// @Param threshold query int false "Hamming distance threshold for near-duplicates (default 10, max 20)"
// @Success 200 {object} object{groups=[]photoutil.DuplicateGroup}
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
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
		Exists:    photoutil.ExistsIn(c.Request.Context(), deps.VFSRegistry()),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(gin.H{"groups": result.Groups})
}

var listDuplicatesRoute = serverutil.ApiRoute("GET", "/photos/duplicates", listDuplicates)

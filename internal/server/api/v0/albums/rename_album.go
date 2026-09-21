package v0_albums

import (
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// renameAlbum godoc
// @Summary Rename a photo album
// @Description Updates the name of one of the caller's albums. The name cannot contain / and must be unique among the album's siblings ignoring case; changing only the case of the album's own name is allowed.
// @Tags albums
// @Accept json
// @Produce json
// @Param id path int true "Album ID"
// @Param body body renameAlbumRequest true "New album name"
// @Success 200 {object} AlbumJSON
// @Failure 400 {object} serverutil.Response "Bad Request: invalid id, missing name, or a / in the name"
// @Failure 403 {object} serverutil.Response "Forbidden: system album"
// @Failure 404 {object} serverutil.Response "Not Found: no album of the caller's has that id"
// @Failure 409 {object} serverutil.Response "Conflict: an album with that name already exists here"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /albums/{id}/rename [patch]
func renameAlbum(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid album id"))
	}

	var req renameAlbumRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("name is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	userID := callerID(c)
	if resp := rejectSystemAlbum(c.Request.Context(), deps.Database().Queries, userID, id); resp != nil {
		return resp
	}

	result, err := albumutil.RenameAlbum(c.Request.Context(), albumutil.RenameAlbumParams{
		Queries: deps.Database().Queries,
		UserID:  userID,
		ID:      id,
		Name:    req.Name,
	})
	if err != nil {
		return albumWriteError(err)
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	count := countItems(deps.Database().Queries, access, result.Album.ID)

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(toAlbumJSON(result.Album, count))
}

var renameAlbumRoute = serverutil.ApiRoute(
	"PATCH", "/albums/:id/rename", renameAlbum,
)

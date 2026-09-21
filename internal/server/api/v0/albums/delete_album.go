package v0_albums

import (
	"context"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteAlbum godoc
// @Summary Delete a photo album
// @Description Deletes one of the caller's albums and all its children (cascades). Does not delete photos from disk.
// @Tags albums
// @Produce json
// @Param id path int true "Album ID"
// @Success 204 {object} serverutil.Response "No Content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden: system album"
// @Failure 404 {object} serverutil.Response "Not Found: no album of the caller's has that id"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /albums/{id} [delete]
func deleteAlbum(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid album id"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	userID := callerID(c)
	if resp := rejectSystemAlbum(c.Request.Context(), deps.Database().Queries, userID, id); resp != nil {
		return resp
	}

	if err := deps.Database().Queries.DeleteAlbum(context.Background(), db.DeleteAlbumParams{ID: id, UserID: userID}); err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithStatusCode(204)
}

var deleteAlbumRoute = serverutil.ApiRoute(
	"DELETE", "/albums/:id", deleteAlbum,
)

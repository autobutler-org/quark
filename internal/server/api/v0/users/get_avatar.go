package v0_users

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
	"github.com/gin-gonic/gin"
)

// getAvatar godoc
// @Summary Get a user's profile picture
// @Description Serves a user's 256x256 profile picture to any signed-in user, with an ETag derived from its version; a matching If-None-Match gets 304. Clients add the picture's avatarUpdatedAt as the v query parameter, so a changed picture is a new URL. A user with no picture is a 404.
// @Tags users
// @Produce jpeg,png
// @Param id path int true "User id"
// @Param v query int false "Cache-buster, the picture's avatarUpdatedAt; ignored by the Quark"
// @Success 200 {file} file
// @Failure 304 "Not Modified"
// @Failure 400 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /users/{id}/avatar [get]
func getAvatar(c *gin.Context) *serverutil.Response {
	userID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || userID <= 0 {
		return serverutil.BadRequest(errors.New("the user id must be a positive integer"))
	}
	opened, err := avatarutil.Open(avatarutil.OpenParams{
		DataDir: storageutil.GetDataDir(),
		UserID:  userID,
	})
	if errors.Is(err, avatarutil.ErrNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	defer opened.File.Close()

	etag := thumbnailutil.ETagFromModTime(opened.UpdatedAt)
	c.Header("ETag", etag)
	c.Header("Cache-Control", "no-cache")
	c.Header("Content-Type", opened.ContentType)
	if c.GetHeader("If-None-Match") == etag {
		c.Status(http.StatusNotModified)
		return nil
	}
	http.ServeContent(c.Writer, c.Request, "", opened.UpdatedAt, opened.File)
	return nil
}

var getAvatarRoute = serverutil.ApiRoute("GET", "/users/:id/avatar", getAvatar)

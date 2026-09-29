package v0_users

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// setAvatar godoc
// @Summary Set your profile picture
// @Description Replaces the caller's profile picture with the image in the multipart field "file" (JPEG, PNG, WebP, HEIC, GIF, BMP or TIFF, at most 10 MiB). The Quark center-crops and resizes it to 256x256 and keeps only the re-encoded file, so EXIF and location data are dropped. Publishes account_changed.
// @Tags users
// @Accept multipart/form-data
// @Produce json
// @Param file formData file true "The image"
// @Success 200 {object} SetAvatarResponse
// @Failure 400 {object} serverutil.Response "Not an image"
// @Failure 401 {object} serverutil.Response
// @Failure 413 {object} serverutil.Response "Larger than 10 MiB"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /users/me/avatar [put]
func setAvatar(c *gin.Context) *serverutil.Response {
	userID, err := callerID(c)
	if err != nil {
		return serverutil.Unauthorized(err)
	}
	part, err := filePart(c)
	if err != nil {
		return serverutil.BadRequest(err)
	}
	defer part.Close()

	result, err := avatarutil.Save(avatarutil.SaveParams{
		DataDir: storageutil.GetDataDir(),
		UserID:  userID,
		Source:  part,
	})
	switch {
	case errors.Is(err, avatarutil.ErrTooLarge):
		return serverutil.NewResponse().WithStatusCode(http.StatusRequestEntityTooLarge).WithError(err)
	case errors.Is(err, avatarutil.ErrNotImage):
		return serverutil.BadRequest(avatarutil.ErrNotImage)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	publishAccountChanged(c)
	return serverutil.Ok().WithData(SetAvatarResponse{AvatarUpdatedAt: result.UpdatedAt.UnixMilli()})
}

var setAvatarRoute = serverutil.ApiRoute("PUT", "/users/me/avatar", setAvatar)

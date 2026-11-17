package v0_files

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/zipselectionutil"

	"github.com/gin-gonic/gin"
)

// createSelectionDownloadToken godoc
// @Summary Issue a download token for a selection
// @Description Issues a token that authenticates one POST /files/download-selection of the same paths, passed as the downloadToken query parameter with the returned selection as filePath. It is the selection counterpart of POST /files/download-token, for a browser form that cannot send an Authorization header. The paths may be on any devices; each is checked for read access when the zip is built, not here. A selection names 1 to 2000 paths.
// @Tags files
// @Accept json
// @Produce json
// @Param request body selectionRequest true "The selected files"
// @Success 200 {object} createSelectionDownloadTokenResponse "OK"
// @Failure 400 {object} serverutil.Response "No paths, or more than 2000"
// @Failure 401 {object} serverutil.Response "Unauthorized"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/download-selection-token [post]
func createSelectionDownloadToken(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	username, ok := ctxutil.Get[string](c, "username")
	if !ok || username == "" {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}
	var request selectionRequest
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxSelectionBody)
	if err := c.ShouldBindJSON(&request); err != nil {
		return serverutil.BadRequest(errors.New("invalid request body"))
	}
	if err := zipselectionutil.Validate(request.Paths); err != nil {
		return serverutil.BadRequest(err)
	}
	access, resp := loadAccess(c, deps)
	if resp != nil {
		return resp
	}

	selection := zipselectionutil.SelectionKey(request.Paths)
	result, err := deps.DownloadTokens().IssueToken(downloadutil.IssueTokenParams{
		Username: username,
		UserID:   access.Principal().UserID,
		FilePath: selection,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(createSelectionDownloadTokenResponse{
		Token:     result.Token,
		ExpiresAt: result.ExpiresAt.UTC(),
		Selection: selection,
	})
}

var createSelectionDownloadTokenRoute = serverutil.ApiRoute(
	"POST", "/files/download-selection-token", createSelectionDownloadToken,
)

package v0_files

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// createDownloadToken godoc
// @Summary Issue a single-use download token
// @Description Issues a token that authenticates one GET /files/download (or /files/download-archive-file, where filePath is the archive) of the same filePath and serial, passed as the downloadToken query parameter. A browser link cannot send an Authorization header; this lets the web client hand the download to the browser, which streams it to disk. The token works once, runs as the caller, makes the response an attachment, and expires unused after about a minute. Needs read access on the path.
// @Tags files
// @Produce json
// @Param filePath query string true "File path the token is for"
// @Param serial query string false "Device serial number the token is for"
// @Success 200 {object} createDownloadTokenResponse "OK"
// @Failure 401 {object} serverutil.Response "Unauthorized"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/download-token [post]
func createDownloadToken(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")
	serial := c.Query("serial")

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	username, ok := ctxutil.Get[string](c, "username")
	if !ok || username == "" {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(serial, filePath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	result, err := deps.DownloadTokens().IssueToken(downloadutil.IssueTokenParams{
		Username: username,
		UserID:   access.Principal().UserID,
		FilePath: filePath,
		Serial:   serial,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(createDownloadTokenResponse{
		Token:     result.Token,
		ExpiresAt: result.ExpiresAt.UTC(),
	})
}

var createDownloadTokenRoute = serverutil.ApiRoute(
	"POST", "/files/download-token", createDownloadToken,
)

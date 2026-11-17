package v0_files

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/zipselectionutil"

	"github.com/gin-gonic/gin"
)

// downloadSelection godoc
// @Summary Download a selection of files as one zip
// @Description Zips the selected files, from any folders on any devices, into one archive streamed back as selection.zip (#4195). Each entry is named after its file, and a name taken twice gets " (1)", " (2)", ... before its extension. A path the caller cannot read, that does not exist, that is a folder, or that is on a device not attached is left out and named in a skipped.txt at the end of the zip; it never fails the download. The archive is built on the fly and cannot be resumed. It is a POST form so a browser can submit it and save the response to disk; a browser authenticates with a token from POST /files/download-selection-token, passing its selection as filePath, and must send the same paths.
// @Tags files
// @Accept x-www-form-urlencoded
// @Produce application/zip
// @Param paths formData string true "JSON array of the selected files, each {\"serial\": \"\", \"filePath\": \"...\"}; 1 to 2000 entries"
// @Param filePath query string false "With downloadToken: the selection the token was issued for"
// @Param downloadToken query string false "Token from POST /files/download-selection-token, for a browser form that cannot send an Authorization header"
// @Success 200 {file} file
// @Failure 400 {object} serverutil.Response "No paths, more than 2000, or not a JSON array"
// @Failure 401 {object} serverutil.Response "Unauthorized, or the paths are not the ones the token was issued for"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Every zip slot is busy; retry after the Retry-After header"
// @Header 503 {integer} Retry-After "seconds to wait before retrying"
// @Security BearerAuth
// @Router /files/download-selection [post]
func downloadSelection(c *gin.Context) *serverutil.Response {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxSelectionBody)
	var paths []zipselectionutil.Path
	if err := json.Unmarshal([]byte(c.PostForm("paths")), &paths); err != nil {
		return serverutil.BadRequest(errors.New("paths must be a JSON array of files"))
	}
	if err := zipselectionutil.Validate(paths); err != nil {
		return serverutil.BadRequest(err)
	}
	// The token was spent on the selection named in filePath; these have to
	// be the paths it was issued for.
	if viaToken, _ := ctxutil.Get[bool](c, "downloadToken"); viaToken && zipselectionutil.SelectionKey(paths) != c.Query("filePath") {
		return serverutil.Unauthorized(errors.New("the download token is for another selection"))
	}
	deps, access, resp := loadCaller(c)
	if resp != nil {
		return resp
	}

	const name = "selection.zip"
	release, ok := acquireZipSlot(c, deps, name)
	if !ok {
		return nil
	}
	defer release()
	// Before the first byte, which commits the headers.
	c.Writer.Header().Set("Content-Disposition", contentDisposition(c, name, `attachment; filename="`+name+`"`))
	c.Writer.Header().Set("Content-Type", "application/zip")
	c.Header("Cache-Control", "no-store")
	if _, err := zipselectionutil.ZipSelection(zipselectionutil.ZipSelectionParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Access:   access,
		Paths:    paths,
		Writer:   c.Writer,
	}); err != nil {
		return zipError(c, name, err)
	}
	return nil
}

var downloadSelectionRoute = serverutil.ApiRoute(
	"POST", "/files/download-selection", downloadSelection,
)

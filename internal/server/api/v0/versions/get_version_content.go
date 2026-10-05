package v0_versions

import (
	"mime"
	"net/http"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getVersionContent godoc
// @Summary Download a version
// @Description Stream one version's content, typed by the file's extension. Needs read access on the file.
// @Tags versions
// @Produce octet-stream
// @Param id path string true "Version id"
// @Param path query string true "Files-relative path of the file"
// @Success 200 {file} binary "The version's content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /versions/{id}/content [get]
func getVersionContent(c *gin.Context) *serverutil.Response {
	p := c.Query("path")
	deps, fsys, refused := prepare(c, p, accessutil.Read)
	if refused != nil {
		return refused
	}
	res, err := deps.FileVersions().Open(fileversionutil.OpenParams{
		Ctx:  c.Request.Context(),
		FS:   fsys,
		Path: p,
		ID:   c.Param("id"),
	})
	if err != nil {
		return versionError(err)
	}
	defer func() { _ = res.Reader.Close() }()
	contentType := mime.TypeByExtension(path.Ext(p))
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	c.DataFromReader(http.StatusOK, res.Version.Size, contentType, res.Reader, map[string]string{
		"Content-Disposition": mime.FormatMediaType("attachment", map[string]string{"filename": path.Base(p)}),
	})
	return nil
}

var getVersionContentRoute = serverutil.ApiRoute(
	"GET", "/versions/:id/content", getVersionContent,
)

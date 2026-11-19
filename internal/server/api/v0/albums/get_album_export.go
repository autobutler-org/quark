package v0_albums

import (
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumexportutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getAlbumExport godoc
// @Summary Summarize a photo export
// @Description Reports what a photo-export job has copied, read from its manifest, and names the photos it could not copy, so a partial export lists its failures (#3501). An export that has not written its manifest yet reports none of either.
// @Tags albums
// @Produce json
// @Param jobId path int true "The export's job ID"
// @Success 200 {object} AlbumExportSummaryJSON
// @Failure 400 {object} serverutil.Response "Bad Request: invalid job id"
// @Failure 404 {object} serverutil.Response "Not Found: no export of the caller's has that id"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /albums/exports/{jobId} [get]
func getAlbumExport(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("jobId"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid job id"))
	}
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	got, err := deps.JobQueue().Get(c.Request.Context(), jobutil.GetParams{ID: id})
	switch {
	case errors.Is(err, jobutil.ErrJobNotFound):
		return serverutil.NotFound(errExportNotFound)
	case err != nil:
		return serverutil.InternalServerError(err)
	case got.Job.Kind != albumexportutil.Kind || !access.CanSeeJob(got.Job):
		return serverutil.NotFound(errExportNotFound)
	}
	serial, relPath := got.Job.Source()
	summary, err := albumexportutil.ReadSummary(albumexportutil.ReadSummaryParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Serial:   serial,
		RelPath:  relPath,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(AlbumExportSummaryJSON{
		JobID:        got.Job.ID,
		Status:       string(got.Job.Status),
		DeviceSerial: serial,
		RelPath:      relPath,
		Copied:       summary.Copied,
		Failures:     summary.Failures,
		MoreFailures: summary.MoreFailures,
	})
}

var getAlbumExportRoute = serverutil.ApiRoute(
	"GET", "/albums/exports/:jobId", getAlbumExport,
)

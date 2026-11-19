package v0_albums

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumexportutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// exportAlbums godoc
// @Summary Export albums, or the photo library, as copied files
// @Description Queues a photo-export job that copies the caller's chosen albums, or their whole photo library, into a new folder inside the folder given: each album becomes a folder of real copies, a photo in several albums is copied into each, and a manifest.csv names every copy's original, capture date and albums (#3501). The library, its folders and the albums are left untouched. The new folder is named after the album, or after the library, and never replaces one already there.
// @Tags albums
// @Accept json
// @Produce json
// @Param body body exportAlbumsRequest true "Albums to export, or library, and the folder to export into"
// @Success 202 {object} AlbumExportJSON
// @Failure 400 {object} serverutil.Response "Bad Request: no album chosen and not the library"
// @Failure 403 {object} serverutil.Response "Forbidden: the caller cannot add files to that folder"
// @Failure 404 {object} serverutil.Response "Not Found: an album is not the caller's, or the folder does not exist"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /albums/exports [post]
func exportAlbums(c *gin.Context) *serverutil.Response {
	var req exportAlbumsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("invalid export request"))
	}
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	result, err := albumexportutil.StartExport(albumexportutil.StartExportParams{
		Ctx:      c.Request.Context(),
		Queries:  deps.Database().Queries,
		Registry: deps.VFSRegistry(),
		Queue:    deps.JobQueue(),
		Access:   access,
		AlbumIDs: req.AlbumIDs,
		Library:  req.Library,
		Serial:   req.DeviceSerial,
		Folder:   req.Folder,
	})
	if err != nil {
		return exportError(err)
	}
	deps.EventBus().Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: result.RelPath, DeviceSerial: result.Serial})
	return serverutil.Accepted().WithContentType(serverutil.ContentTypeJSON).WithData(AlbumExportJSON{
		JobID:        result.JobID,
		DeviceSerial: result.Serial,
		RelPath:      result.RelPath,
	})
}

var exportAlbumsRoute = serverutil.ApiRoute(
	"POST", "/albums/exports", exportAlbums,
)

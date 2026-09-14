package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// moveFile godoc
// @Summary Move or rename a file
// @Description Enqueue a file move operation between paths/devices
// @Tags files
// @Accept json
// @Produce json
// @Param body body moveFileRequest true "Move file request"
// @Success 202 {object} serverutil.Response "Ok"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /files [put]
func moveFile(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	var req moveFileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	if _, err := fileutil.MoveFile(fileutil.MoveFileParams{
		Ctx:             c.Request.Context(),
		Registry:        deps.VFSRegistry(),
		Storage:         deps.StorageService(),
		EventBus:        deps.EventBus(),
		Database:        deps.Database(),
		OldFilePath:     req.OldFilePath,
		NewFilePath:     req.NewFilePath,
		OldDeviceSerial: req.OldDeviceSerial,
		NewDeviceSerial: req.NewDeviceSerial,
	}); err != nil {
		return fileError(err)
	}
	return serverutil.Ok()
}

var moveFileRoute = serverutil.ApiRoute(
	"PUT", "/files", moveFile,
)

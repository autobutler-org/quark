package v0_videos

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// listTranscodeFormats godoc
// @Summary List transcode formats
// @Description Lists the video formats POST /videos/transcode writes, in display order. With relPath, only the ones the video there can be converted to: those whose container holds its codecs, leaving out its own format. Without it, every format the device writes, whatever a given video's codecs allow.
// @Tags videos
// @Produce json
// @Param serial query string false "Device serial"
// @Param relPath query string false "Relative path to the video the formats are for"
// @Success 200 {object} transcodeFormatsResponse
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /videos/transcode/formats [get]
func listTranscodeFormats(c *gin.Context) *serverutil.Response {
	formats := videoutil.Formats()
	if relPath := c.Query("relPath"); relPath != "" {
		deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
		if !ok {
			return serverutil.InternalServerError(nil)
		}
		serial := c.Query("serial")
		access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		if !access.Check(serial, relPath, accessutil.Read).Readable {
			return serverutil.NotFound(errNoAccess)
		}
		filesDir, err := storageutil.GetFilesDir()
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		if deviceDir, ok := deps.StorageService().FindDeviceFilesDirBySerial(serial); ok {
			filesDir = deviceDir
		}
		cleanFilesDir := filepath.Clean(filesDir)
		fullPath := filepath.Join(cleanFilesDir, relPath)
		if !strings.HasPrefix(fullPath, cleanFilesDir+string(filepath.Separator)) {
			return serverutil.BadRequest(fmt.Errorf("invalid relPath"))
		}
		if formats, err = videoutil.Targets(fullPath); err != nil {
			return serverutil.NotFound(fmt.Errorf("video not found or not readable: %s", relPath))
		}
	}
	resp := transcodeFormatsResponse{Formats: make([]transcodeFormatJSON, 0, len(formats))}
	for _, f := range formats {
		resp.Formats = append(resp.Formats, transcodeFormatJSON{Format: string(f), Label: f.Label()})
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(resp)
}

var listTranscodeFormatsRoute = serverutil.ApiRoute(
	"GET", "/videos/transcode/formats", listTranscodeFormats,
)

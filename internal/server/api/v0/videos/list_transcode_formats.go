package v0_videos

import (
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// listTranscodeFormats godoc
// @Summary List transcode formats
// @Description Lists the video formats POST /videos/transcode can write on this device: the ones whose video and audio encoders its ffmpeg build has, in display order.
// @Tags videos
// @Produce json
// @Success 200 {object} transcodeFormatsResponse
// @Failure 501 {object} serverutil.Response "Not Implemented — ffmpeg not available"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /videos/transcode/formats [get]
func listTranscodeFormats(_ *gin.Context) *serverutil.Response {
	if !videoutil.Available() {
		return serverutil.NewResponse().
			WithStatusCode(http.StatusNotImplemented).
			WithContentType(serverutil.ContentTypeJSON).
			WithData(gin.H{"error": "ffmpeg is not installed on this device"})
	}
	formats, err := videoutil.AvailableFormats()
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("list transcode formats: %w", err))
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

package v0_videos

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/autobutler/pkg/util/ctxutil"
	"github.com/autobutler-org/autobutler/pkg/util/deputil"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/autobutler-org/autobutler/pkg/util/storageutil"
	"github.com/autobutler-org/autobutler/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// trimVideoRequest is the POST body for /videos/trim.
type trimVideoRequest struct {
	RelPath string `json:"relPath"`
	Serial  string `json:"serial"`
	StartMs int64  `json:"startMs"`
	EndMs   int64  `json:"endMs"`
}

// trimVideoResponse is returned on success.
type trimVideoResponse struct {
	RelPath string `json:"relPath"`
}

// trimVideo godoc
// @Summary Trim a video clip
// @Description Extracts a sub-clip [startMs, endMs] from the source video using stream copy (fast, lossless). The original file is not modified.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body trimVideoRequest true "Trim request"
// @Success 200 {object} trimVideoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 501 {object} serverutil.Response "Not Implemented — ffmpeg not available"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /videos/trim [post]
func trimVideo(c *gin.Context) *serverutil.Response {
	if !videoutil.Available() {
		return serverutil.NewResponse().
			WithStatusCode(http.StatusNotImplemented).
			WithContentType(serverutil.ContentTypeJSON).
			WithData(gin.H{"error": "ffmpeg is not installed on this device"})
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req trimVideoRequest
	if err := json.NewDecoder(c.Request.Body).Decode(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	if req.RelPath == "" {
		return serverutil.BadRequest(fmt.Errorf("relPath is required"))
	}
	if req.StartMs < 0 {
		return serverutil.BadRequest(fmt.Errorf("startMs must be >= 0"))
	}
	if req.EndMs <= req.StartMs {
		return serverutil.BadRequest(fmt.Errorf("endMs must be greater than startMs"))
	}

	// Resolve cirrus directory.
	filesDir, err := storageutil.GetCirrusDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if req.Serial != "" {
		if devices, err := deps.StorageService().GetManagedDevices(); err == nil {
			for _, d := range devices {
				if d.UsbInfo != nil && d.UsbInfo.GetSerial() == req.Serial {
					filesDir = d.CirrusDir
					break
				}
			}
		}
	}

	cleanFilesDir := filepath.Clean(filesDir)
	fullPath := filepath.Join(cleanFilesDir, req.RelPath)
	if !strings.HasPrefix(fullPath, cleanFilesDir+string(filepath.Separator)) {
		return serverutil.BadRequest(fmt.Errorf("invalid relPath"))
	}

	// Validate against video duration.
	probeCtx, probeCancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer probeCancel()
	info, err := videoutil.Probe(probeCtx, fullPath)
	if err != nil {
		return serverutil.NotFound(fmt.Errorf("video not found or not readable: %s", req.RelPath))
	}
	durationMs := info.Duration.Milliseconds()
	if req.EndMs > durationMs {
		return serverutil.BadRequest(fmt.Errorf(
			"endMs (%d) exceeds video duration (%d ms)", req.EndMs, durationMs,
		))
	}

	// Build output filename: {stem}_trimmed{ext}
	ext := filepath.Ext(filepath.Base(req.RelPath))
	stem := strings.TrimSuffix(filepath.Base(req.RelPath), ext)
	outName := stem + "_trimmed" + ext
	outFull := storageutil.GetNonConflictingPath(filepath.Join(filepath.Dir(fullPath), outName))
	outRel, err := filepath.Rel(cleanFilesDir, outFull)
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("resolve output path: %w", err))
	}

	start := time.Duration(req.StartMs) * time.Millisecond
	end := time.Duration(req.EndMs) * time.Millisecond

	// Stream copy is fast (header rewrite only); 5 minutes is generous headroom.
	trimCtx, trimCancel := context.WithTimeout(c.Request.Context(), 5*time.Minute)
	defer trimCancel()

	if err := videoutil.Trim(trimCtx, fullPath, start, end, outFull); err != nil {
		return serverutil.InternalServerError(fmt.Errorf("trim video: %w", err))
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).
		WithData(trimVideoResponse{RelPath: outRel})
}

var trimVideoRoute = serverutil.ApiRoute(
	"POST", "/videos/trim", trimVideo,
)

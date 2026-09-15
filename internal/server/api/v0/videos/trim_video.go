package v0_videos

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// trimVideo godoc
// @Summary Trim a video clip
// @Description Extracts a sub-clip [startMs, endMs] from the source video using stream copy (fast, lossless). The original file is not modified. Needs read access on the video and write access on its folder; the caller owns the new clip.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body trimVideoRequest true "Trim request"
// @Success 200 {object} trimVideoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
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

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if resp := checkEdit(access, req.Serial, req.RelPath); resp != nil {
		return resp
	}

	// Resolve files directory.
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if deviceDir, ok := deps.StorageService().FindDeviceFilesDirBySerial(req.Serial); ok {
		filesDir = deviceDir
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
	// GetNonConflictingPath picked a name nothing had, so the clip is always a
	// new file and never takes ownership of one that was already there.
	grantOwner(c, deps, access, req.Serial, outRel)

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).
		WithData(trimVideoResponse{RelPath: outRel})
}

var trimVideoRoute = serverutil.ApiRoute(
	"POST", "/videos/trim", trimVideo,
)

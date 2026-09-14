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

// extractFrame godoc
// @Summary Extract a still frame from a video
// @Description Extracts a JPEG frame at the given timestamp and saves it alongside the source video. Needs read access on the video and write access on its folder; the caller owns the new frame.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body extractFrameRequest true "Extract frame request"
// @Success 200 {object} extractFrameResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 501 {object} serverutil.Response "Not Implemented — ffmpeg not available"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /videos/extract-frame [post]
func extractFrame(c *gin.Context) *serverutil.Response {
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

	var req extractFrameRequest
	if err := json.NewDecoder(c.Request.Body).Decode(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	if req.RelPath == "" {
		return serverutil.BadRequest(fmt.Errorf("relPath is required"))
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

	// Build output filename: {stem}_frame_{timestamp}.jpg
	ts := time.Duration(req.TimestampMs) * time.Millisecond
	dir := filepath.Dir(fullPath)
	base := filepath.Base(fullPath)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	outName := stem + "_frame_" + formatFrameTimestamp(ts) + ".jpg"
	outFull := storageutil.GetNonConflictingPath(filepath.Join(dir, outName))
	outRel, err := filepath.Rel(cleanFilesDir, outFull)
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("resolve output path: %w", err))
	}

	ctx := c.Request.Context()
	extractCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	if err := videoutil.ExtractFrame(extractCtx, fullPath, ts, outFull); err != nil {
		return serverutil.InternalServerError(fmt.Errorf("extract frame: %w", err))
	}
	// GetNonConflictingPath picked a name nothing had, so the frame is always a
	// new file and never takes ownership of one that was already there.
	grantOwner(c, deps, access, req.Serial, outRel)

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).
		WithData(extractFrameResponse{RelPath: outRel})
}

var extractFrameRoute = serverutil.ApiRoute(
	"POST", "/videos/extract-frame", extractFrame,
)

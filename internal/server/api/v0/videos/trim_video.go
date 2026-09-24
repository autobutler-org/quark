package v0_videos

import (
	"context"
	"encoding/json"
	"errors"
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
// @Description Copies the sub-clip [startMs, endMs] of the source video into a new file beside it without re-encoding (fast, lossless). The start snaps back to the keyframe at or before startMs, and actualStartMs reports where the clip really begins. The clip keeps the source's format where the device writes it and is an MP4 otherwise. The original file is not modified. An MPEG-TS source cannot be trimmed and is a 422. Needs read access on the video and write access on its folder; the caller owns the new clip.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body trimVideoRequest true "Trim request"
// @Success 200 {object} trimVideoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 422 {object} serverutil.Response "Unprocessable Entity — the video's container can't be trimmed"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /videos/trim [post]
func trimVideo(c *gin.Context) *serverutil.Response {
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

	// Build output filename: {stem}_trimmed{ext}, where ext is the format the
	// clip is written in.
	ext := filepath.Ext(filepath.Base(req.RelPath))
	stem := strings.TrimSuffix(filepath.Base(req.RelPath), ext)
	if format := "." + string(videoutil.TrimFormat(req.RelPath)); !strings.EqualFold(ext, format) {
		ext = format
	}
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

	result, err := videoutil.Trim(trimCtx, videoutil.TrimParams{Source: fullPath, Output: outFull, Start: start, End: end})
	if errors.Is(err, videoutil.ErrCannotTrim) {
		return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).WithError(err)
	}
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("trim video: %w", err))
	}
	// GetNonConflictingPath picked a name nothing had, so the clip is always a
	// new file and never takes ownership of one that was already there.
	grantOwner(c, deps, access, req.Serial, outRel)

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).
		WithData(trimVideoResponse{RelPath: outRel, ActualStartMs: result.Start.Milliseconds()})
}

var trimVideoRoute = serverutil.ApiRoute(
	"POST", "/videos/trim", trimVideo,
)

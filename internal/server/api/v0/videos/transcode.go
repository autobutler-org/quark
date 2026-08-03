package v0_videos

import (
	"encoding/json"
	"fmt"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/autobutler/internal/db"
	"github.com/autobutler-org/autobutler/pkg/util/ctxutil"
	"github.com/autobutler-org/autobutler/pkg/util/deputil"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/autobutler-org/autobutler/pkg/util/storageutil"
	"github.com/autobutler-org/autobutler/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// transcodeRequest is the POST body for /videos/transcode.
type transcodeRequest struct {
	RelPath string `json:"relPath"`
	Serial  string `json:"serial"`
	Preset  string `json:"preset"` // "compatible" | "small" | "web" | raw preset name
}

// transcodeJobResponse is returned on success.
type transcodeJobResponse struct {
	JobID int64 `json:"jobId"`
}

// Friendly preset aliases → videoutil.TranscodePreset.
var presetAliases = map[string]videoutil.TranscodePreset{
	"compatible":                      videoutil.PresetH264720p,
	"small":                           videoutil.PresetH264480p,
	"web":                             videoutil.PresetWebM720p,
	string(videoutil.PresetH264480p):  videoutil.PresetH264480p,
	string(videoutil.PresetH264720p):  videoutil.PresetH264720p,
	string(videoutil.PresetH2641080p): videoutil.PresetH2641080p,
	string(videoutil.PresetWebM720p):  videoutil.PresetWebM720p,
}

// queueTranscode godoc
// @Summary Queue a video transcode job
// @Description Queues a background transcode job and returns the job ID. Poll GET /videos/jobs/:id for status.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body transcodeRequest true "Transcode request"
// @Success 202 {object} transcodeJobResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 501 {object} serverutil.Response "Not Implemented — ffmpeg not available"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /videos/transcode [post]
func queueTranscode(c *gin.Context) *serverutil.Response {
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

	var req transcodeRequest
	if err := json.NewDecoder(c.Request.Body).Decode(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	if req.RelPath == "" {
		return serverutil.BadRequest(fmt.Errorf("relPath is required"))
	}

	preset, ok := presetAliases[req.Preset]
	if !ok {
		preset = videoutil.PresetH264720p // default: compatible 720p
	}

	// Validate the file exists.
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

	paramsJSON, _ := json.Marshal(transcodeParams{Preset: string(preset)})

	jobID, err := deps.Database().Queries.CreateVideoJob(c.Request.Context(), db.CreateVideoJobParams{
		JobType:       "transcode",
		DeviceSerial:  req.Serial,
		InputRelPath:  req.RelPath,
		OutputRelPath: "",
		Params:        string(paramsJSON),
	})
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("create job: %w", err))
	}

	return serverutil.NewResponse().
		WithStatusCode(http.StatusAccepted).
		WithContentType(serverutil.ContentTypeJSON).
		WithData(transcodeJobResponse{JobID: jobID})
}

var queueTranscodeRoute = serverutil.ApiRoute(
	"POST", "/videos/transcode", queueTranscode,
)

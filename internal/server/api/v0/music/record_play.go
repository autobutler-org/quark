package v0_music

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// recordPlay godoc
// @Summary Record a play of a music track
// @Description Adds one play to the caller's count for a library track and stamps it now. The player decides when a play counts and posts once per play. A path that is not a library track, or one the caller cannot read, is 404.
// @Tags music
// @Accept json
// @Param body body recordPlayRequest true "The track's device, empty for the internal drive, and its path"
// @Success 204 "No Content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /music/plays [post]
func recordPlay(c *gin.Context) *serverutil.Response {
	var req recordPlayRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("relPath is required"))
	}
	who, refusal := loadCaller(c)
	if refusal != nil {
		return refusal
	}
	_, err := musicutil.RecordPlay(musicutil.RecordPlayParams{
		Ctx:     c.Request.Context(),
		DB:      who.deps.Database().Db,
		Store:   who.deps.MetadataStore(),
		Access:  who.access,
		Serial:  req.Serial,
		RelPath: req.RelPath,
	})
	if errors.Is(err, musicutil.ErrTrackNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var recordPlayRoute = serverutil.ApiRoute("POST", "/music/plays", recordPlay)

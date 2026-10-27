package v0_music

import (
	"errors"
	"maps"
	"slices"

	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// listHistory godoc
// @Summary List the caller's played music
// @Description Returns the library tracks the caller has played, with their play count and last play, most recent first or most played first. Tracks whose file is gone or no longer readable are left out.
// @Tags music
// @Produce json
// @Param sort query string false "Order; recent when absent" Enums(recent, most)
// @Param limit query int false "How many: 50 when absent, at most 200"
// @Success 200 {object} HistoryResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /music/history [get]
func listHistory(c *gin.Context) *serverutil.Response {
	limit, err := queryInt(c, "limit")
	if err != nil {
		return serverutil.BadRequest(err)
	}
	who, refusal := loadCaller(c)
	if refusal != nil {
		return refusal
	}
	namespaces := vfs.FilesNamespaces(who.deps.VFSRegistry())
	namespaces[""] = nil // the internal drive's history is listed even when it is not registered
	result, err := musicutil.ListHistory(musicutil.ListHistoryParams{
		Ctx:     c.Request.Context(),
		DB:      who.deps.Database().Db,
		Store:   who.deps.MetadataStore(),
		Access:  who.access,
		Serials: slices.Sorted(maps.Keys(namespaces)),
		Sort:    musicutil.HistorySort(c.Query("sort")),
		Limit:   limit,
	})
	if errors.Is(err, musicutil.ErrInvalidHistorySort) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return jsonOk(HistoryResponse{Tracks: result.Tracks})
}

var listHistoryRoute = serverutil.ApiRoute("GET", "/music/history", listHistory)

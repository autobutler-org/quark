package v0_files

import (
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// ContentSearchResult is the JSON shape for a single content search hit.
type ContentSearchResult struct {
	// Serial is the storage device serial number.
	Serial string `json:"serial"`
	// RelPath is the path to the file relative to the device's FilesDir.
	RelPath string `json:"relPath"`
	// Snippet is a highlighted excerpt around the matched terms.
	// Matched terms are enclosed in <b> tags.
	Snippet string `json:"snippet"`
}

// searchContent godoc
// @Summary Search file contents (FTS5)
// @Schemes http https
// @Description Full-text search over indexed file contents using SQLite FTS5.
// @Description Only text-based file formats are indexed (.txt, .md, .csv, .yaml, .json, etc.).
// @Description Binary formats (images, video, PDF) are not indexed.
// @Description Returns up to `limit` results ordered by relevance rank.
// @Tags files
// @Produce json
// @Param q      query string true  "Search query (FTS5 syntax: words, AND/OR/NOT, \"phrases\", prefix*)"
// @Param limit  query int    false "Maximum results to return (default 50, max 200)"
// @Success 200 {array}  ContentSearchResult
// @Failure 400 {object} serverutil.Response "Bad Request — missing query"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /files/search/content [get]
func searchContent(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		return serverutil.BadRequest(nil)
	}

	limit := searchutil.ParseLimit(c.Query("limit"))

	dbConn := deps.Database()
	if dbConn == nil || dbConn.Db == nil {
		return serverutil.InternalServerError(nil)
	}

	access, err := accessutil.LoadRequest(c, dbConn, deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	found, err := searchutil.SearchReadable(searchutil.SearchReadableParams{
		Ctx:    c.Request.Context(),
		DB:     dbConn.Db,
		Query:  q,
		Limit:  limit,
		Access: access,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	results := found.Results

	out := make([]ContentSearchResult, len(results))
	for i, r := range results {
		out[i] = ContentSearchResult{
			Serial:  r.Serial,
			RelPath: r.RelPath,
			Snippet: r.Snippet,
		}
	}
	return serverutil.Ok().WithData(out)
}

var searchContentRoute = serverutil.ApiRoute(
	"GET", "/files/search/content",
	func(c *gin.Context) *serverutil.Response { return searchContent(c) },
)

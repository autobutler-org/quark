// cspell:words thumbversionutil

package v0_photos

import (
	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/thumbversionutil"

	"github.com/gin-gonic/gin"
)

// PaginatedPhotosResponse wraps a page of photos with pagination metadata.
type PaginatedPhotosResponse struct {
	Photos []PhotoListing `json:"photos"`
	Total  int            `json:"total"`
	Offset int            `json:"offset"`
	Limit  int            `json:"limit"`
	// PendingDates counts the photos whose capture date has still not been
	// read, under sort=taken only. They sort by their date added until a later
	// listing reads them, so a client lists again while it is above zero
	// (#3356).
	PendingDates int `json:"pendingDates,omitempty"`
}

// PhotoListing is one photo or video of a listing page: its summary and its
// saved rotation in quarter turns. With the mtime, the rotation is the
// thumbnail version a client puts in the thumbnail URL's v, so the URL
// changes when the photo is rotated (#4217).
type PhotoListing struct {
	photoutil.PhotoSummary
	RotationQuarters int64 `json:"rotationQuarters,omitempty"`
}

// listPhotos godoc
// @Summary List photos
// @Description Finds all photos across all managed devices with pagination support. With includeVideos=true videos are listed beside them; a video carries isVideo and, where its headers parse, durationMs; a Live Photo's companion video is not listed on its own but sets its photo's hasLiveVideo. Videos sort by their date added under sort=taken. Each item carries rotationQuarters when the photo has been rotated, so a client can name the thumbnail version, mtime and rotationQuarters joined by a dot, in the thumbnail URL. Under sort=taken each photo carries its EXIF capture date as takenAt, read on the spot for a photo never read before, and pendingDates counts those left for a later listing. q keeps the photos whose file name contains that text, ignoring case, and total counts those matches.
// @Tags photos
// @Produce json
// @Param offset query int false "Pagination offset (default 0)"
// @Param limit query int false "Page size (default 50, max 200)"
// @Param serial query string false "Device serial to filter by"
// @Param sort query string false "Sort field: added (date added), taken (date taken) or name (default added)"
// @Param order query string false "Sort order: asc or desc (default desc)"
// @Param includeVideos query bool false "List videos beside the photos (default false, for clients that only open images)"
// @Param q query string false "File name substring to keep, ignoring case. Blank lists the whole library"
// @Success 200 {object} PaginatedPhotosResponse
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /photos [get]
func listPhotos(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	offset, limit := photoutil.ParsePagination(c.Query("offset"), c.Query("limit"))
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	// Capture dates are read from the database, and recorded there as the
	// listing reads them; without one, the taken sort falls back to the date
	// added.
	var queries db.Querier
	if database := deps.Database(); database != nil {
		queries = database.Queries
	}

	result, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Serial:   c.Query("serial"),
		Access:   access,
		Sort:     photoutil.ParseSort(c.Query("sort")),
		Order:    photoutil.ParseOrder(c.Query("order")),
		Query:    c.Query("q"),
		// Opt-in, so an app that only opens images never lists a video.
		IncludeVideos: c.Query("includeVideos") == "true",
		Queries:       queries,
		Offset:        offset,
		Limit:         limit,
		Index:         deps.FileIndex(),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	photos := make([]PhotoListing, len(result.Photos))
	for i, photo := range result.Photos {
		photos[i].PhotoSummary = photo
		if queries == nil {
			continue
		}
		rotation, err := thumbversionutil.Rotation(thumbversionutil.RotationParams{
			Ctx:     c.Request.Context(),
			Queries: queries,
			Serial:  photo.Serial,
			RelPath: photo.RelPath,
		})
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		photos[i].RotationQuarters = rotation.Quarters
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(PaginatedPhotosResponse{
		Photos:       photos,
		Total:        result.Total,
		Offset:       result.Offset,
		Limit:        result.Limit,
		PendingDates: result.PendingDates,
	})
}

var listPhotosRoute = serverutil.ApiRoute(
	"GET", "/photos", listPhotos,
)

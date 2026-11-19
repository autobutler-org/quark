package v0_albums

import (
	"github.com/autobutler-org/quark/pkg/util/albumexportutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// AlbumJSON is the JSON representation of a photo album.
type AlbumJSON struct {
	ID        int64       `json:"id"`
	Name      string      `json:"name"`
	ParentID  *int64      `json:"parentId"`
	SmartType *string     `json:"smartType,omitempty"`
	CreatedAt string      `json:"createdAt"`
	UpdatedAt string      `json:"updatedAt"`
	ItemCount int64       `json:"itemCount"`
	Children  []AlbumJSON `json:"children,omitempty"`
}

// AlbumItemJSON is the JSON representation of a photo inside an album.
type AlbumItemJSON struct {
	ID           int64  `json:"id"`
	AlbumID      int64  `json:"albumId"`
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
	AddedAt      string `json:"addedAt"`
	// TakenAt is the photo's EXIF capture date, sent under sort=taken when
	// it is known (#2592).
	TakenAt string `json:"takenAt,omitempty"`
}

type addPhotoRequest struct {
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
}

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listAlbumsRoute,
		getAlbumRoute,
		createAlbumRoute,
		renameAlbumRoute,
		moveAlbumRoute,
		deleteAlbumRoute,
		listAlbumItemsRoute,
		addPhotoToAlbumRoute,
		removePhotoFromAlbumRoute,
		exportAlbumsRoute,
		getAlbumExportRoute,
	}
}

type createAlbumRequest struct {
	Name     string `json:"name" binding:"required"`
	ParentID *int64 `json:"parentId"`
}

type moveAlbumRequest struct {
	ParentID *int64 `json:"parentId"`
}

type renameAlbumRequest struct {
	Name string `json:"name" binding:"required"`
}

// exportAlbumsRequest asks for an export of albums, or of the whole library,
// into a folder.
type exportAlbumsRequest struct {
	// AlbumIDs are the caller's albums to export, each with its sub-albums.
	AlbumIDs []int64 `json:"albumIds"`
	// Library exports every album and every photo in none, and ignores
	// AlbumIDs.
	Library bool `json:"library"`
	// DeviceSerial and Folder are the folder the export folder is made in;
	// "" is the internal drive.
	DeviceSerial string `json:"deviceSerial"`
	Folder       string `json:"folder"`
}

// AlbumExportJSON is a queued export: its job and the folder it fills.
type AlbumExportJSON struct {
	JobID        int64  `json:"jobId"`
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
}

// AlbumExportSummaryJSON is what an export has done, from its manifest.
type AlbumExportSummaryJSON struct {
	JobID int64 `json:"jobId"`
	// Status is the job's: pending, running, completed, failed or canceled.
	// A failed export with Copied above zero is a partial one.
	Status       string `json:"status" enums:"pending,running,completed,failed,canceled"`
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
	// Copied counts the files copied.
	Copied int `json:"copied"`
	// Failures names the photos not copied, at most 500; MoreFailures counts
	// the rest.
	Failures     []albumexportutil.Failure `json:"failures"`
	MoreFailures int                       `json:"moreFailures"`
}

package v0_albums

import (
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

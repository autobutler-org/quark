package v0_photos

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listPhotosRoute,
		getMetadataRoute,
		rotatePhotoRoute,
		copyPhotoRoute,
		listDuplicatesRoute,
		listLocationsRoute,
		getMapTileRoute,
	}
}

// adminRouter holds the photo library index routes.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getIndexStatusRoute,
		pauseIndexRoute,
		resumeIndexRoute,
	}
}

type copyPhotoRequest struct {
	RelPath string `json:"relPath" binding:"required"`
	Serial  string `json:"serial"`
}

type copyPhotoResponse struct {
	RelPath string `json:"relPath"`
}

type rotatePhotoRequest struct {
	RelPath          string `json:"relPath"          binding:"required"`
	Serial           string `json:"serial"`
	RotationQuarters int64  `json:"rotationQuarters"` // 0–3; 0 deletes the record
}

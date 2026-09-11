package v0_trash

import (
	"time"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listTrashRoute,
		listTrashContentsRoute,
		restoreTrashRoute,
		deleteTrashRoute,
		emptyTrashRoute,
	}
}

// listTrashResponse is a device's trash and how long anything stays in it.
type listTrashResponse struct {
	RetentionDays int                     `json:"retentionDays"`
	Items         []storageutil.TrashItem `json:"items"`
}

// listTrashContentsResponse is what a folder in the trash holds, where it
// would be restored to, and when the trashed item it belongs to expires.
type listTrashContentsResponse struct {
	Items        []storageutil.TrashContentsItem `json:"items"`
	OriginalPath string                          `json:"originalPath"`
	ExpiresAt    time.Time                       `json:"expiresAt"`
}

// trashItemsRequest names trashed items, or things inside trashed folders, on
// one device.
type trashItemsRequest struct {
	Serial string                 `json:"serial"`
	Items  []storageutil.TrashRef `json:"items"`
}

// emptyTrashRequest names the device whose trash to empty.
type emptyTrashRequest struct {
	Serial string `json:"serial"`
}

// restoreTrashResponse lists where the restored items went, relative to the
// device's files directory.
type restoreTrashResponse struct {
	RestoredPaths []string `json:"restoredPaths"`
}

// deletedResponse counts the items a delete or empty removed.
type deletedResponse struct {
	Deleted int `json:"deleted"`
}

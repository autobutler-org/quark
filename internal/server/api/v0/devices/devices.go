// Package v0_devices serves /api/v0/devices: the clients that have connected to this Quark. Listing them is open to
// any user; removing a record is admin-only.
package v0_devices

import (
	"time"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// ConnectedDeviceJSON is the API representation of a connected device.
type ConnectedDeviceJSON struct {
	ID           int64     `json:"id"`
	IPAddress    string    `json:"ipAddress"`
	UserAgent    string    `json:"userAgent"`
	FirstSeenAt  time.Time `json:"firstSeenAt"`
	LastSeenAt   time.Time `json:"lastSeenAt"`
	RequestCount int64     `json:"requestCount"`
}

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the route that deletes connected-device records.
// Mount it behind middleware.RequireAdmin.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}

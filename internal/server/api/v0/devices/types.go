package v0_devices

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listDevicesRoute,
	}
}

// adminRouter holds the route that removes connected-device records.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		deleteDeviceRoute,
	}
}

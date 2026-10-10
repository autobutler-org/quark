package v0_hostname

import "github.com/autobutler-org/quark/pkg/util/serverutil"

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getHostnameRoute,
		setHostnameRoute,
	}
}

// hostnameResponse is what the device is called and whether it can be
// renamed.
type hostnameResponse struct {
	// Available is whether this Quark can be renamed.
	Available bool `json:"available"`
	// Reason is why not, when available is false: unsupported_os, not_service
	// or helper_missing.
	Reason string `json:"reason,omitempty"`
	// Hostname is the system hostname.
	Hostname string `json:"hostname"`
	// AdvertisedHostname is the name the device answers to on the network,
	// without the .local suffix. It differs from hostname when another device
	// already had the name, and is absent when Avahi does not say.
	AdvertisedHostname string `json:"advertisedHostname,omitempty"`
}

type setHostnameBody struct {
	// Hostname is 1 to 63 lowercase letters, digits or hyphens, with at least
	// one letter and no hyphen at either end.
	Hostname string `json:"hostname" binding:"required"`
}

package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// SettingsJSON is the JSON representation of application settings.
type SettingsJSON struct {
	AutoUpdate bool `json:"autoUpdate"`
}

// RemoteAccessRequest is the optional body of an enable. An empty body, or an
// empty authKey, means the Quark fetches its own key.
type RemoteAccessRequest struct {
	// AuthKey overrides the provisioned pre-auth key. It is used only when the
	// Quark has no tailnet enrollment to reuse.
	AuthKey string `json:"authKey,omitempty"`
}

type RemoteAccessResponse struct {
	// Enabled is the persisted setting: the user asked for remote access.
	Enabled bool `json:"enabled"`
	// Connected is true only once the node has joined the tailnet.
	Connected bool `json:"connected"`
	// RemoteURL is set only when Connected.
	RemoteURL string `json:"remoteUrl,omitempty"`
	// Error is the last start failure, a diagnostic for the log reader rather
	// than copy for a user.
	Error string `json:"error,omitempty"`
}

// PairDeviceResponse is what a device needs to join the Quark's household
// and reach the Quark (#2359).
type PairDeviceResponse struct {
	// AuthKey is a single-use Headscale pre-auth key in the Quark's household.
	AuthKey string `json:"authKey"`
	// ControlURL is the Headscale server the device registers with.
	ControlURL string `json:"controlUrl"`
	// QuarkAddress is the Quark's URL on the tailnet.
	QuarkAddress string `json:"quarkAddress"`
}

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getSettingsRoute,
		getRemoteAccessRoute,
		pairDeviceRoute,
	}
}

// adminRouter holds the routes that change appliance-wide settings or the
// Quark's network exposure.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		postSettingsRoute,
		enableRemoteAccessRoute,
		disableRemoteAccessRoute,
		updateAccessRequestsRoute,
	}
}

// accessRequestsSetting is whether the sign-in page takes account requests.
// A pointer, so a body that leaves it out is refused rather than read as off.
type accessRequestsSetting struct {
	Enabled *bool `json:"enabled" binding:"required"`
}

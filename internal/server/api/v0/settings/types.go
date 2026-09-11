package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// SettingsJSON is the JSON representation of application settings.
type SettingsJSON struct {
	AutoUpdate bool `json:"autoUpdate"`
}

type RemoteAccessRequest struct {
	AuthKey string `json:"authKey"`
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

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getSettingsRoute,
		postSettingsRoute,
		getRemoteAccessRoute,
	}
}

// adminRouter holds the routes that change the Quark's network exposure.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		enableRemoteAccessRoute,
		disableRemoteAccessRoute,
	}
}

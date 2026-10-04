// Package v0_settings serves /api/v0/settings.
//
// Public, no session: GET /settings/public, the Quark's settings that are safe to show on the sign-in page (its
// theme color).
//
// Any signed-in user: reading the Quark's settings (GET /settings), reading remote access (GET
// /settings/remote-access), pairing a device for remote access (POST /settings/remote-access/devices), listing the
// beta feature flags (GET /settings/features), and reading and replacing the caller's own settings (GET and PUT
// /settings/me), which act only on the session's account.
//
// Admin-only: the routes that change appliance-wide settings, such as turning remote access on and off, account
// requests (PUT /settings/access-requests), a feature flag (PUT /settings/features/:key), and the Quark's theme
// color (PUT /settings/theme-color).
package v0_settings

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the routes that change appliance-wide settings and
// turn remote access on and off. Mount it behind middleware.RequireAdmin: they
// affect every account on the Quark and expose it to the network.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}

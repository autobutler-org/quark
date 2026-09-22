// Package v0_admin serves the admin-only /api/v0/admin routes: creating, approving, denying, promoting, demoting,
// disabling, enabling and deleting users, groups and their members, and repairing the installation.
package v0_admin

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

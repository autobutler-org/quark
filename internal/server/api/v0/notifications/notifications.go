// Package v0_notifications serves /api/v0/notifications, the caller's current notifications. Every signed-in
// account may call it; nothing here is admin-only, though the backup types only ever go to an admin.
package v0_notifications

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

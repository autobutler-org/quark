// Package v0_users serves /api/v0/users, profile pictures: PUT and DELETE
// /users/me/avatar change the caller's own, and GET /users/{id}/avatar serves
// anyone's to any signed-in user. No route here is admin-only.
package v0_users

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the router for /api/v0/users.
func NewRouter() serverutil.Router {
	return &router{}
}

// SetAvatarResponse is the body of a successful PUT /users/me/avatar.
type SetAvatarResponse struct {
	// AvatarUpdatedAt is the new picture's version in Unix milliseconds,
	// the value clients append to the avatar URL as ?v=.
	AvatarUpdatedAt int64 `json:"avatarUpdatedAt"`
}

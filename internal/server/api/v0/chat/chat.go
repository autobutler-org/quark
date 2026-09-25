// Package v0_chat serves /api/v0/chat: the chat channels the caller belongs to, creating, renaming and deleting
// channels, listing and changing a channel's members, and each account's chat keys, where /chat/keys/me holds the
// caller's wrapped identity and /chat/keys/:userId serves any account's public keys. No route is admin-only; admins
// may manage any channel but, like everyone else, list only the channels they are members of. A channel the caller
// may not see is a 404.
package v0_chat

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the chat routes.
func NewRouter() serverutil.Router {
	return &router{}
}

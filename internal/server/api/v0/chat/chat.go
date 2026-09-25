// Package v0_chat serves /api/v0/chat: the chat channels the caller belongs to, creating, renaming and deleting
// channels, listing and changing a channel's members, and each account's chat keys, where /chat/keys/me holds the
// caller's wrapped identity and /chat/keys/:userId serves any account's public keys. /chat/channels/:id/keys serves
// a channel's key versions and the caller's key grants, with /keys/pending and /keys/grants for filling other
// members' grants, /chat/channels/:id/events its signed membership and key events, and /chat/channels/:id/messages
// its encrypted messages, which /chat/messages/:id deletes. No route is admin-only;
// admins may manage any channel but, like everyone else, list only the channels they are members of, and keys,
// events and messages are for members alone. A channel the caller may not see is a 404, and every route is a 404 while an
// admin has the chat beta turned off (PUT /settings/chat).
package v0_chat

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the chat routes.
func NewRouter() serverutil.Router {
	return &router{}
}

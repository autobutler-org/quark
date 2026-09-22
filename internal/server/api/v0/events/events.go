// Package v0_events serves /api/v0/events, the WebSocket that streams event-bus events to open clients, filtered to
// what each user can read, so every client refreshes when the file tree changes.
package v0_events

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

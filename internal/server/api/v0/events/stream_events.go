package v0_events

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// streamEvents godoc
// @Summary Stream real-time file/device events
// @Description Upgrades the connection to WebSocket and pushes JSON events for file system mutations (upload, delete, move, new_folder). Each connection hears only events about paths its user can read; admins hear every event. A connection closes once its account is turned off, deleted, promoted or demoted.
// @Tags events
// @Produce json
// @Success 101 {string} string "Switching Protocols"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Security BearerAuth
// @Router /events [get]
func streamEvents(c *gin.Context) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		c.Status(http.StatusInternalServerError)
		return
	}

	// The filter runs here rather than in the bus: the file index, content
	// indexer and backup sync subscribe to the same bus and must keep hearing
	// everything (#1906). The snapshot is loaded once per connection, and an
	// admin's load makes no query.
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}

	// InsecureSkipVerify disables the websocket library's built-in origin check.
	// The Flutter web app is served from a different origin than the API server,
	// so the default check (Origin == Host) always fails with 403.
	// Auth is already enforced via the requireAuth middleware (?token= / Bearer).
	conn, err := websocket.Accept(c.Writer, c.Request, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
	})
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	// Best-effort: the handler is unwinding, so a failed close has nowhere to go.
	defer func() { _ = conn.CloseNow() }()

	// The subscriber ID only has to be unique within the bus, so mint it per
	// connection rather than from a package-global counter (#1674).
	ch, unsub := deps.EventBus().Subscribe(uuid.NewString())
	defer unsub()

	ctx := conn.CloseRead(c.Request.Context())
	for {
		select {
		case <-ctx.Done():
			return
		case evt, ok := <-ch:
			if !ok {
				return
			}
			// requireAuth checked the account only when the socket opened, so
			// an account turned off, deleted, promoted or demoted since stops
			// hearing events here. The app reconnects and is refused, or is
			// filtered for its new role.
			if (evt.Kind == eventbus.EventAccountChanged || evt.Kind == eventbus.EventAccessChanged) &&
				!stillActive(ctx, deps, access) {
				return
			}
			// Rows changed somewhere, so what this subscriber can read may have
			// too: reload before filtering this event and the ones after it.
			// A failed reload closes the stream rather than filter against a
			// snapshot that may be stale; the app reconnects.
			previous := access
			if evt.Kind == eventbus.EventAccessChanged {
				if access, err = accessutil.LoadRequest(c, deps.Database(), deps.StorageService()); err != nil {
					return
				}
			}
			filtered := accessutil.FilterEvent(accessutil.FilterEventParams{
				Access:   access,
				Previous: previous,
				Event:    evt,
			})
			if !filtered.Deliver {
				continue
			}
			if err := wsjson.Write(ctx, conn, filtered.Event); err != nil {
				return
			}
		}
	}
}

var streamEventsRoute = serverutil.NewRoute(
	"GET", "/events", streamEvents,
)

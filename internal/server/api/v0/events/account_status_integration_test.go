package v0_events_test

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_events "github.com/autobutler-org/quark/internal/server/api/v0/events"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
)

// closedWithin reports whether the server closed conn within wait: a read
// that fails before its own deadline means the stream ended, while one that
// runs into the deadline means the stream is still open and silent.
func closedWithin(conn *websocket.Conn, wait time.Duration) bool {
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	var evt eventbus.Event
	err := wsjson.Read(ctx, conn, &evt)
	return err != nil && ctx.Err() == nil
}

// TestStreamEvents_ClosesForInactiveAccount checks an open stream ends at the
// next account_changed once its account is turned off, and again once it is
// deleted, while a stream whose account is still active hears the event.
func TestStreamEvents_ClosesForInactiveAccount(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	database := dbtest.NewDB(t)
	users := map[string]int64{}
	for _, name := range []string{"bob", "carol"} {
		user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		users[name] = user.ID
	}

	bus := eventbus.New()
	deps := deputil.NewDependencies().WithEventBus(bus).WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: users[c.Query("as")]})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_events.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)

	conns := map[string]*websocket.Conn{}
	for _, name := range []string{"bob", "carol"} {
		conn, _, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events?as="+name), nil)
		if err != nil {
			t.Fatalf("dial as %s: %v", name, err)
		}
		t.Cleanup(func() { _ = conn.CloseNow() })
		conns[name] = conn
	}
	time.Sleep(200 * time.Millisecond)

	if _, err := database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{
		Username: "bob", FromStatus: authutil.StatusActive, ToStatus: authutil.StatusDisabled,
	}); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})

	var evt eventbus.Event
	if err := wsjson.Read(ctx, conns["carol"], &evt); err != nil || evt.Kind != eventbus.EventAccountChanged {
		t.Fatalf("carol read = %+v, %v; want account_changed", evt, err)
	}
	if !closedWithin(conns["bob"], 2*time.Second) {
		t.Error("the disabled account's stream stayed open")
	}

	if err := database.Queries.DeleteUser(ctx, users["carol"]); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	if !closedWithin(conns["carol"], 2*time.Second) {
		t.Error("the deleted account's stream stayed open")
	}
}

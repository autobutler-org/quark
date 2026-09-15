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

// TestStreamEvents_ClosesWhenTheAdminRoleChanges checks an open stream ends
// once its account's admin role no longer matches the one it connected with:
// a demoted admin's stream at the next account_changed, so it stops hearing
// everything, and a promoted account's at the next access_changed, so it
// reconnects unfiltered. A stream whose role is unchanged hears both events.
func TestStreamEvents_ClosesWhenTheAdminRoleChanges(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	database := dbtest.NewDB(t)
	principals := map[string]accessutil.Principal{}
	for _, name := range []string{"boss", "bob", "carol"} {
		user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		principals[name] = accessutil.Principal{UserID: user.ID}
	}
	if err := authutil.PromoteToAdmin(ctx, database.Queries, "boss"); err != nil {
		t.Fatal(err)
	}
	principals["boss"] = accessutil.Principal{UserID: principals["boss"].UserID, IsAdmin: true}

	bus := eventbus.New()
	deps := deputil.NewDependencies().WithEventBus(bus).WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principals[c.Query("as")])
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_events.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)

	conns := map[string]*websocket.Conn{}
	for _, name := range []string{"boss", "bob", "carol"} {
		conn, _, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events?as="+name), nil)
		if err != nil {
			t.Fatalf("dial as %s: %v", name, err)
		}
		t.Cleanup(func() { _ = conn.CloseNow() })
		conns[name] = conn
	}
	time.Sleep(200 * time.Millisecond)
	hears := func(name string, kind eventbus.EventKind) {
		t.Helper()
		var evt eventbus.Event
		if err := wsjson.Read(ctx, conns[name], &evt); err != nil || evt.Kind != kind {
			t.Fatalf("%s read = %+v, %v; want %s", name, evt, err, kind)
		}
	}

	if err := database.Queries.SetUserAdmin(ctx, db.SetUserAdminParams{IsAdmin: 0, Username: "boss"}); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	hears("carol", eventbus.EventAccountChanged)
	hears("bob", eventbus.EventAccountChanged)
	if !closedWithin(conns["boss"], 2*time.Second) {
		t.Error("the demoted admin's stream stayed open")
	}

	if err := authutil.PromoteToAdmin(ctx, database.Queries, "bob"); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	hears("carol", eventbus.EventAccessChanged)
	if !closedWithin(conns["bob"], 2*time.Second) {
		t.Error("the promoted account's stream stayed open")
	}
}

package v0_events_test

import (
	"context"
	"database/sql"
	"net/http/httptest"
	"reflect"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_events "github.com/autobutler-org/quark/internal/server/api/v0/events"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory lives under
// HOME.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// TestStreamEvents_FilteredPerSubscriber connects an admin and two users with
// different access to the same bus. The admin hears every published event 1:1;
// each user hears only what they can read, with moves across the edge of what
// they can read rewritten, and a grant that lands mid-stream takes effect from
// the access_changed that announces it (#1906).
func TestStreamEvents_FilteredPerSubscriber(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if _, err := storageutil.GetFilesDir(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
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
	grant := func(name, rel string) {
		t.Helper()
		if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
			RelPath: rel,
			UserID:  sql.NullInt64{Int64: users[name], Valid: true},
			Level:   accessutil.Read.String(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	grant("bob", "shared")
	grant("carol", "private")

	bus := eventbus.New()
	deps := deputil.NewDependencies().
		WithEventBus(bus).
		WithDatabase(database).
		WithStorageService(storageutil.NewStorageService(systemDevice{}))
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		principal := accessutil.System
		if id, ok := users[c.Query("as")]; ok {
			principal = accessutil.Principal{UserID: id}
		}
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_events.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)

	conns := map[string]*websocket.Conn{}
	for _, name := range []string{"admin", "bob", "carol"} {
		conn, _, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events?as="+name), nil)
		if err != nil {
			t.Fatalf("dial as %s: %v", name, err)
		}
		t.Cleanup(func() { _ = conn.CloseNow() })
		conns[name] = conn
	}
	// Give each handler time to load its access and subscribe.
	time.Sleep(200 * time.Millisecond)

	published := []eventbus.Event{
		{Kind: eventbus.EventUpload, Path: "shared"},
		{Kind: eventbus.EventUpload, Path: "private"},
		{Kind: eventbus.EventMove, Path: "private/x.txt", NewPath: "shared/x.txt"},
		{Kind: eventbus.EventMove, Path: "shared/y.txt", NewPath: "shared/z.txt"},
		{Kind: eventbus.EventDelete, Path: "shared/z.txt"},
		{Kind: eventbus.EventBackupStarted},
	}
	for _, evt := range published {
		bus.Publish(evt)
	}
	// Bob is shared a folder under private; the access_changed that announces
	// it reloads his snapshot, so he hears the upload after it.
	grant("bob", "private/new")
	late := []eventbus.Event{
		{Kind: eventbus.EventAccessChanged, Path: "private/new"},
		{Kind: eventbus.EventUpload, Path: "private/new"},
		{Kind: eventbus.EventAccountChanged},
		{Kind: eventbus.EventTrashChanged},
	}
	for _, evt := range late {
		bus.Publish(evt)
	}
	published = append(published, late...)

	want := map[string][]eventbus.Event{
		"admin": published,
		"bob": {
			{Kind: eventbus.EventUpload, Path: "shared"},
			{Kind: eventbus.EventUpload, Path: "shared"},
			{Kind: eventbus.EventMove, Path: "shared/y.txt", NewPath: "shared/z.txt"},
			{Kind: eventbus.EventDelete, Path: "shared/z.txt"},
			{Kind: eventbus.EventAccessChanged, Path: "private/new"},
			{Kind: eventbus.EventUpload, Path: "private/new"},
			{Kind: eventbus.EventAccountChanged},
			{Kind: eventbus.EventTrashChanged},
		},
		"carol": {
			{Kind: eventbus.EventUpload, Path: "private"},
			{Kind: eventbus.EventDelete, Path: "private/x.txt"},
			{Kind: eventbus.EventAccessChanged, Path: "private/new"},
			{Kind: eventbus.EventUpload, Path: "private/new"},
			{Kind: eventbus.EventAccountChanged},
			{Kind: eventbus.EventTrashChanged},
		},
	}
	for name, conn := range conns {
		var got []eventbus.Event
		for len(got) == 0 || got[len(got)-1].Kind != eventbus.EventTrashChanged {
			var evt eventbus.Event
			if err := wsjson.Read(ctx, conn, &evt); err != nil {
				t.Fatalf("%s: read after %d events %v: %v", name, len(got), got, err)
			}
			got = append(got, evt)
		}
		if !reflect.DeepEqual(got, want[name]) {
			t.Errorf("%s heard\n%v\nwant\n%v", name, got, want[name])
		}
	}

	var rows int
	if err := database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 3 {
		t.Errorf("path_access rows = %d, want the 3 granted: streaming wrote rows", rows)
	}
}

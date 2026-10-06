package v0_events_test

import (
	"context"
	"database/sql"
	"net/http/httptest"
	"reflect"
	"sync"
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

// sharedStream is a server whose one account, bob, was shared "shared".
type sharedStream struct {
	srv      *httptest.Server
	deps     deputil.Dependencies
	bus      *eventbus.Bus
	database *db.DatabaseSqlc
	bob      int64
}

func newSharedStream(ctx context.Context, t *testing.T) sharedStream {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	if _, err := storageutil.GetFilesDir(); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	bob, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "shared",
		UserID:  sql.NullInt64{Int64: bob.ID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}

	bus := eventbus.New()
	deps := deputil.NewDependencies().
		WithEventBus(bus).
		WithDatabase(database).
		WithStorageService(storageutil.NewStorageService(systemDevice{}))
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: bob.ID})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_events.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)
	return sharedStream{srv: srv, deps: deps, bus: bus, database: database, bob: bob.ID}
}

func (s sharedStream) dial(ctx context.Context, t *testing.T) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.Dial(ctx, wsURL(s.srv, "/api/v0/events"), nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.CloseNow() })
	return conn
}

func (s sharedStream) revoke(ctx context.Context, t *testing.T) {
	t.Helper()
	if _, err := s.database.Queries.DeleteUserPathAccess(ctx, db.DeleteUserPathAccessParams{
		UserID: sql.NullInt64{Int64: s.bob, Valid: true}, RelPath: "shared",
	}); err != nil {
		t.Fatal(err)
	}
}

// readUntil reads events until one of kind arrives, and returns them all.
func readUntil(ctx context.Context, t *testing.T, conn *websocket.Conn, kind eventbus.EventKind) []eventbus.Event {
	t.Helper()
	var got []eventbus.Event
	for len(got) == 0 || got[len(got)-1].Kind != kind {
		var evt eventbus.Event
		if err := wsjson.Read(ctx, conn, &evt); err != nil {
			t.Fatalf("read after %v: %v", got, err)
		}
		got = append(got, evt)
	}
	return got
}

// A user whose share is revoked hears nothing more under it from the
// access_changed that announces the revocation on (#2764).
func TestStreamEvents_RevokedShareHearsNothingMore(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	s := newSharedStream(ctx, t)
	conn := s.dial(ctx, t)

	s.bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "shared"})
	if got := readUntil(ctx, t, conn, eventbus.EventUpload); len(got) != 1 {
		t.Fatalf("heard %v before the revocation, want the one upload", got)
	}

	s.revoke(ctx, t)
	for _, evt := range []eventbus.Event{
		{Kind: eventbus.EventAccessChanged, Path: "shared"},
		{Kind: eventbus.EventUpload, Path: "shared"},
		{Kind: eventbus.EventUpload, Path: "shared/secret.txt"},
		{Kind: eventbus.EventMove, Path: "shared/a.txt", NewPath: "shared/b.txt"},
		{Kind: eventbus.EventTrashChanged},
	} {
		s.bus.Publish(evt)
	}
	want := []eventbus.Event{
		{Kind: eventbus.EventAccessChanged, Path: "shared"},
		{Kind: eventbus.EventTrashChanged},
	}
	if got := readUntil(ctx, t, conn, eventbus.EventTrashChanged); !reflect.DeepEqual(got, want) {
		t.Fatalf("heard %v after the revocation, want %v", got, want)
	}
}

// A socket that fell behind and lost the access_changed hears a resync in its
// place, and the resync reloads its access the same way: what it can no
// longer read stays filtered (#2764).
func TestStreamEvents_ResyncReloadsAccess(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	s := newSharedStream(ctx, t)
	conn := s.dial(ctx, t)

	s.revoke(ctx, t)
	for _, evt := range []eventbus.Event{
		{Kind: eventbus.EventResync, Data: eventbus.Resync{Dropped: 1}},
		{Kind: eventbus.EventUpload, Path: "shared"},
		{Kind: eventbus.EventTrashChanged},
	} {
		s.bus.Publish(evt)
	}
	got := readUntil(ctx, t, conn, eventbus.EventTrashChanged)
	if len(got) != 2 || got[0].Kind != eventbus.EventResync {
		t.Fatalf("heard %v after the revocation, want the resync and trash_changed", got)
	}
}

// Two hundred sockets of one account hearing one access change go to the
// database once between them, rather than once each (#2764).
func TestStreamEvents_OneRefillPerChange(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	s := newSharedStream(ctx, t)
	conns := make([]*websocket.Conn, 200)
	for i := range conns {
		conns[i] = s.dial(ctx, t)
	}

	s.bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "shared"})
	s.bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "shared"})
	var wg sync.WaitGroup
	for _, conn := range conns {
		wg.Go(func() {
			var evt eventbus.Event
			for evt.Kind != eventbus.EventUpload {
				if err := wsjson.Read(ctx, conn, &evt); err != nil {
					t.Errorf("read: %v", err)
					return
				}
			}
		})
	}
	wg.Wait()
	if got := s.deps.AccessCache().Refills(); got != 1 {
		t.Fatalf("Refills() = %d for 200 sockets and one change, want 1", got)
	}
}

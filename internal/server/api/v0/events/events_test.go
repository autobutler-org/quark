package v0_events_test

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	v0_events "github.com/autobutler-org/quark/internal/server/api/v0/events"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
)

func newEventsServer(t *testing.T, bus *eventbus.Bus) *httptest.Server {
	t.Helper()
	deps := deputil.NewDependencies().WithEventBus(bus)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_events.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)
	return srv
}

func wsURL(srv *httptest.Server, path string) string {
	return "ws" + strings.TrimPrefix(srv.URL, "http") + path
}

// TestStreamEvents_ConnectsSuccessfully verifies that a WebSocket client can
// upgrade the /events connection without error.
func TestStreamEvents_ConnectsSuccessfully(t *testing.T) {
	bus := eventbus.New()
	srv := newEventsServer(t, bus)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	conn, resp, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events"), &websocket.DialOptions{})
	if err != nil {
		t.Fatalf("Dial: %v (status: %v)", err, resp)
	}
	defer conn.CloseNow()

	// Successful upgrade means 101.
	if resp.StatusCode != 101 {
		t.Errorf("expected 101 Switching Protocols, got %d", resp.StatusCode)
	}
}

// TestStreamEvents_ReceivesPublishedEvent verifies that an event published to
// the bus is delivered to a connected WebSocket client.
func TestStreamEvents_ReceivesPublishedEvent(t *testing.T) {
	bus := eventbus.New()
	srv := newEventsServer(t, bus)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	conn, _, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events"), &websocket.DialOptions{})
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	defer conn.CloseNow()

	// Give the server goroutine time to register the subscriber before publishing.
	time.Sleep(20 * time.Millisecond)

	// Publish a test event.
	go bus.Publish(eventbus.Event{
		Kind: eventbus.EventUpload,
		Path: "photos/test.jpg",
	})

	// Read the event back.
	var evt eventbus.Event
	if err := wsjson.Read(ctx, conn, &evt); err != nil {
		t.Fatalf("Read: %v", err)
	}
	if evt.Kind != eventbus.EventUpload {
		t.Errorf("Kind = %q; want %q", evt.Kind, eventbus.EventUpload)
	}
	if evt.Path != "photos/test.jpg" {
		t.Errorf("Path = %q; want 'photos/test.jpg'", evt.Path)
	}
}

// TestStreamEvents_MultipleEventTypes verifies delete and upload events are
// both delivered correctly.
func TestStreamEvents_MultipleEventTypes(t *testing.T) {
	bus := eventbus.New()
	srv := newEventsServer(t, bus)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	conn, _, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events"), &websocket.DialOptions{})
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	defer conn.CloseNow()

	time.Sleep(20 * time.Millisecond)

	events := []eventbus.Event{
		{Kind: eventbus.EventDelete, Path: "old.txt"},
		{Kind: eventbus.EventNewFolder, Path: "newdir/"},
	}
	go func() {
		for _, e := range events {
			bus.Publish(e)
		}
	}()

	for _, want := range events {
		var got eventbus.Event
		if err := wsjson.Read(ctx, conn, &got); err != nil {
			t.Fatalf("Read: %v", err)
		}
		if got.Kind != want.Kind {
			t.Errorf("Kind = %q; want %q", got.Kind, want.Kind)
		}
	}
}

// TestStreamEvents_ClientDisconnectUnsubscribes verifies that when the client
// disconnects, the subscription is cleaned up (no goroutine/channel leak).
// We verify this indirectly by confirming the server handles close gracefully.
func TestStreamEvents_ClientDisconnectUnsubscribes(t *testing.T) {
	bus := eventbus.New()
	srv := newEventsServer(t, bus)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	conn, _, err := websocket.Dial(ctx, wsURL(srv, "/api/v0/events"), &websocket.DialOptions{})
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}

	// Close cleanly — server should unsubscribe without panicking.
	if err := conn.Close(websocket.StatusNormalClosure, "done"); err != nil {
		t.Logf("Close: %v (may be benign if server closed first)", err)
	}

	// Allow cleanup goroutine to run.
	time.Sleep(50 * time.Millisecond)

	// Publishing after client disconnect should not panic.
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "after-close.txt"})
}

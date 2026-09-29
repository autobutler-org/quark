package v0_calendar

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"
)

// newCalendarEngine serves the calendar router to a signed-in member, "member",
// who is not an admin, and returns the bus the handlers publish to.
func newCalendarEngine(t *testing.T) (*gin.Engine, <-chan eventbus.Event) {
	t.Helper()
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	t.Cleanup(unsubscribe)
	database := dbtest.NewDB(t)
	member, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{Username: "member", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	deps := deputil.NewDependencies().WithDatabase(database).WithEventBus(bus)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: member.ID})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), NewRouter())
	return engine, events
}

func do(engine *gin.Engine, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewReader([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

func decode[T any](t *testing.T, w *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	return v
}

// heard reports whether the bus carried a calendar change for id.
func heard(events <-chan eventbus.Event, id int64) bool {
	select {
	case e := <-events:
		return e.Kind == eventbus.EventCalendarChanged && e.Data == id
	default:
		return false
	}
}

const vet = `{"title":"Vet","location":"Riverside","start":"2026-09-29T16:00:00-07:00","end":"2026-09-29T16:45:00-07:00",
"timeZone":"America/Los_Angeles","repeat":"weekly","reminderMinutes":30,"colorIndex":2}`

func TestEventRoundTrip(t *testing.T) {
	engine, events := newCalendarEngine(t)

	w := do(engine, http.MethodPost, "/api/v0/calendar/events", vet)
	if w.Code != http.StatusCreated {
		t.Fatalf("create = %d %s, want 201", w.Code, w.Body.String())
	}
	created := decode[EventJSON](t, w)
	if created.Start != "2026-09-29T23:00:00Z" || created.End != "2026-09-29T23:45:00Z" {
		t.Errorf("times = %s..%s, want them in UTC", created.Start, created.End)
	}
	if !created.Mine || created.Owner != "member" {
		t.Errorf("owner = %q mine = %v, want the caller's own event", created.Owner, created.Mine)
	}
	if created.Repeat != "weekly" || created.ReminderMinutes == nil || *created.ReminderMinutes != 30 || created.ColorIndex != 2 {
		t.Errorf("created = %+v, want the request's fields", created)
	}
	if !heard(events, created.ID) {
		t.Error("create published no calendar change")
	}

	w = do(engine, http.MethodGet, "/api/v0/calendar/events?from=2026-10-05T00:00:00Z&to=2026-10-12T00:00:00Z", "")
	if w.Code != http.StatusOK {
		t.Fatalf("list = %d %s, want 200", w.Code, w.Body.String())
	}
	if list := decode[EventListJSON](t, w); len(list.Events) != 1 || list.Events[0].ID != created.ID {
		t.Errorf("a later week lists %+v, want the weekly series", list.Events)
	}

	path := fmt.Sprintf("/api/v0/calendar/events/%d", created.ID)
	w = do(engine, http.MethodPut, path, `{"title":"Vet visit","start":"2026-09-30T16:00:00Z","end":"2026-09-30T17:00:00Z"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("update = %d %s, want 200", w.Code, w.Body.String())
	}
	updated := decode[EventJSON](t, w)
	if updated.Title != "Vet visit" || updated.Repeat != "none" || updated.ReminderMinutes != nil {
		t.Errorf("updated = %+v, want every field replaced", updated)
	}
	if !heard(events, created.ID) {
		t.Error("update published no calendar change")
	}

	if w = do(engine, http.MethodGet, path, ""); w.Code != http.StatusOK || decode[EventJSON](t, w).Title != "Vet visit" {
		t.Errorf("get = %d %s, want the updated event", w.Code, w.Body.String())
	}

	if w = do(engine, http.MethodDelete, path, ""); w.Code != http.StatusNoContent {
		t.Fatalf("delete = %d %s, want 204", w.Code, w.Body.String())
	}
	if !heard(events, created.ID) {
		t.Error("delete published no calendar change")
	}
	for _, method := range []string{http.MethodGet, http.MethodDelete} {
		if w = do(engine, method, path, ""); w.Code != http.StatusNotFound {
			t.Errorf("%s after delete = %d, want 404", method, w.Code)
		}
	}
}

func TestEventRequestErrors(t *testing.T) {
	engine, events := newCalendarEngine(t)
	tests := []struct {
		name, method, path, body string
		want                     int
	}{
		{"list without a range", http.MethodGet, "/api/v0/calendar/events", "", http.StatusBadRequest},
		{"list with a bad from", http.MethodGet, "/api/v0/calendar/events?from=monday&to=2026-10-01T00:00:00Z", "", http.StatusBadRequest},
		{"list reversed", http.MethodGet, "/api/v0/calendar/events?from=2026-10-01T00:00:00Z&to=2026-09-01T00:00:00Z", "", http.StatusBadRequest},
		{"create without times", http.MethodPost, "/api/v0/calendar/events", `{"title":"x"}`, http.StatusBadRequest},
		{"create with a bad time", http.MethodPost, "/api/v0/calendar/events", `{"title":"x","start":"noon","end":"2026-09-29T13:00:00Z"}`, http.StatusBadRequest},
		{"create without a title", http.MethodPost, "/api/v0/calendar/events", `{"start":"2026-09-29T12:00:00Z","end":"2026-09-29T13:00:00Z"}`, http.StatusBadRequest},
		{"create backwards", http.MethodPost, "/api/v0/calendar/events", `{"title":"x","start":"2026-09-29T13:00:00Z","end":"2026-09-29T12:00:00Z"}`, http.StatusBadRequest},
		{"get a non-number", http.MethodGet, "/api/v0/calendar/events/abc", "", http.StatusBadRequest},
		{"get a missing event", http.MethodGet, "/api/v0/calendar/events/99", "", http.StatusNotFound},
		{"update a missing event", http.MethodPut, "/api/v0/calendar/events/99", `{"title":"x","start":"2026-09-29T12:00:00Z","end":"2026-09-29T13:00:00Z"}`, http.StatusNotFound},
		{"delete a non-number", http.MethodDelete, "/api/v0/calendar/events/abc", "", http.StatusBadRequest},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if w := do(engine, tt.method, tt.path, tt.body); w.Code != tt.want {
				t.Errorf("%s %s = %d %s, want %d", tt.method, tt.path, w.Code, w.Body.String(), tt.want)
			}
		})
	}
	select {
	case e := <-events:
		t.Errorf("a failed request published %+v", e)
	default:
	}
}

func TestEventOwnerFields(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	maya, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "maya", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	sam, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "sam", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	engineAs := func(id int64) *gin.Engine {
		deps := deputil.NewDependencies().WithDatabase(database)
		engine := gin.New()
		engine.Use(func(c *gin.Context) {
			c = ctxutil.With(c, "deps", deps)
			c = ctxutil.With(c, "principal", accessutil.Principal{UserID: id})
			c.Next()
		})
		serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), NewRouter())
		return engine
	}

	if w := do(engineAs(maya.ID), http.MethodPost, "/api/v0/calendar/events", vet); w.Code != http.StatusCreated {
		t.Fatalf("create = %d %s", w.Code, w.Body.String())
	}
	list := "/api/v0/calendar/events?from=2026-09-29T00:00:00Z&to=2026-09-30T12:00:00Z"
	for _, tt := range []struct {
		as   int64
		mine bool
	}{{maya.ID, true}, {sam.ID, false}} {
		events := decode[EventListJSON](t, do(engineAs(tt.as), http.MethodGet, list, "")).Events
		if len(events) != 1 || events[0].Owner != "maya" || events[0].Mine != tt.mine {
			t.Errorf("as %d: events = %+v, want maya's event with mine=%v", tt.as, events, tt.mine)
		}
	}
}

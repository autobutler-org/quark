package v0_calendar

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
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
	const timed = `"title":"x","start":"2026-09-29T12:00:00Z","end":"2026-09-29T13:00:00Z"`
	const allDay = `"title":"x","start":"2026-09-29T00:00:00Z","end":"2026-09-30T00:00:00Z","allDay":true`
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
		// Out-of-range colors and reminders are a 400 from the app's rules,
		// never a 500 from the schema's CHECKs (#2536).
		{"create a negative color", http.MethodPost, "/api/v0/calendar/events", `{` + timed + `,"colorIndex":-1}`, http.StatusBadRequest},
		{"create a color past the last", http.MethodPost, "/api/v0/calendar/events", `{` + timed + `,"colorIndex":6}`, http.StatusBadRequest},
		{"create a timed reminder after the start", http.MethodPost, "/api/v0/calendar/events", `{` + timed + `,"reminderMinutes":-1}`, http.StatusBadRequest},
		{"create a reminder past a week", http.MethodPost, "/api/v0/calendar/events", `{` + timed + `,"reminderMinutes":10081}`, http.StatusBadRequest},
		{"create an all-day reminder past its day", http.MethodPost, "/api/v0/calendar/events", `{` + allDay + `,"reminderMinutes":-1440}`, http.StatusBadRequest},
		{"update to a color past the last", http.MethodPut, "/api/v0/calendar/events/99", `{` + timed + `,"colorIndex":99}`, http.StatusBadRequest},
		{"update to a reminder past a week", http.MethodPut, "/api/v0/calendar/events/99", `{` + timed + `,"reminderMinutes":999999}`, http.StatusBadRequest},
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

// TestEventBindErrors checks a body that cannot be read says why, rather than
// always blaming missing times (#2537).
func TestEventBindErrors(t *testing.T) {
	engine, _ := newCalendarEngine(t)
	const times = `"title":"x","start":"2026-09-29T12:00:00Z","end":"2026-09-29T13:00:00Z"`
	tests := []struct{ name, body, want string }{
		{"a string color", `{` + times + `,"colorIndex":"2"}`, "colorIndex must be a whole number"},
		{"a fractional color", `{` + times + `,"colorIndex":2.5}`, "colorIndex must be a whole number"},
		{"a boolean color", `{` + times + `,"colorIndex":true}`, "colorIndex must be a whole number"},
		{"a fractional reminder", `{` + times + `,"reminderMinutes":30.7}`, "reminderMinutes must be a whole number"},
		{"a string all-day flag", `{` + times + `,"allDay":"true"}`, "allDay must be true or false"},
		{"a numeric title", `{"title":7,"start":"2026-09-29T12:00:00Z","end":"2026-09-29T13:00:00Z"}`, "title must be a string"},
		{"not JSON", `{"title":`, "the body must be a JSON event"},
		{"no end", `{"title":"x","start":"2026-09-29T12:00:00Z"}`, "start and end are required"},
	}
	for _, tt := range tests {
		for _, method := range []string{http.MethodPost, http.MethodPut} {
			t.Run(method+" "+tt.name, func(t *testing.T) {
				path := "/api/v0/calendar/events"
				if method == http.MethodPut {
					path += "/1"
				}
				w := do(engine, method, path, tt.body)
				if w.Code != http.StatusBadRequest {
					t.Fatalf("%s = %d %s, want 400", method, w.Code, w.Body.String())
				}
				if got := decode[map[string]any](t, w)["error"]; got != tt.want {
					t.Errorf("error = %q, want %q", got, tt.want)
				}
			})
		}
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

// TestEventRepeatUntil checks a series can end on a date, is not listed after
// it, and a client that never sends the field still gets one that repeats
// forever (#2524, #2535).
func TestEventRepeatUntil(t *testing.T) {
	engine, _ := newCalendarEngine(t)
	const walk = `"title":"Walk","start":"2026-10-01T02:00:00Z","end":"2026-10-01T02:30:00Z","repeat":"daily"`

	w := do(engine, http.MethodPost, "/api/v0/calendar/events", `{`+walk+`,"repeatUntil":"2026-10-31T00:00:00Z"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("create = %d %s, want 201", w.Code, w.Body.String())
	}
	ending := decode[EventJSON](t, w)
	if ending.RepeatUntil == nil || *ending.RepeatUntil != "2026-10-31T00:00:00Z" {
		t.Errorf("repeatUntil = %v, want 2026-10-31T00:00:00Z", ending.RepeatUntil)
	}

	w = do(engine, http.MethodPost, "/api/v0/calendar/events", `{`+walk+`}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("create without an end = %d %s, want 201", w.Code, w.Body.String())
	}
	forever := decode[EventJSON](t, w)
	if forever.RepeatUntil != nil {
		t.Errorf("repeatUntil = %v, want null when the client sends none", *forever.RepeatUntil)
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"repeatUntil":null`)) {
		t.Errorf("body %s, want repeatUntil sent as null", w.Body.String())
	}

	ids := func(from, to string) map[int64]bool {
		t.Helper()
		w := do(engine, http.MethodGet, "/api/v0/calendar/events?from="+from+"&to="+to, "")
		if w.Code != http.StatusOK {
			t.Fatalf("list = %d %s, want 200", w.Code, w.Body.String())
		}
		got := map[int64]bool{}
		for _, e := range decode[EventListJSON](t, w).Events {
			got[e.ID] = true
		}
		return got
	}
	if got := ids("2026-10-12T00:00:00Z", "2026-10-19T00:00:00Z"); !got[ending.ID] || !got[forever.ID] {
		t.Errorf("a week before the end lists %v, want both series", got)
	}
	if got := ids("2099-01-05T00:00:00Z", "2099-01-12T00:00:00Z"); got[ending.ID] || !got[forever.ID] {
		t.Errorf("a week in 2099 lists %v, want only the series with no end", got)
	}

	for name, body := range map[string]string{
		"a malformed end":     `{` + walk + `,"repeatUntil":"halloween"}`,
		"an end with a time":  `{` + walk + `,"repeatUntil":"2026-10-31T09:00:00Z"}`,
		"an end before start": `{` + walk + `,"repeatUntil":"2026-09-01T00:00:00Z"}`,
	} {
		w := do(engine, http.MethodPost, "/api/v0/calendar/events", body)
		if w.Code != http.StatusBadRequest {
			t.Errorf("%s = %d %s, want 400", name, w.Code, w.Body.String())
			continue
		}
		if msg, _ := decode[map[string]any](t, w)["error"].(string); !strings.Contains(msg, "repeat") {
			t.Errorf("%s: error = %q, want it to name the repeat's end", name, msg)
		}
	}

	path := fmt.Sprintf("/api/v0/calendar/events/%d", ending.ID)
	if w = do(engine, http.MethodPut, path, `{`+walk+`,"repeatUntil":null}`); w.Code != http.StatusOK || decode[EventJSON](t, w).RepeatUntil != nil {
		t.Errorf("update to no end = %d %s, want 200 and no end", w.Code, w.Body.String())
	}
}

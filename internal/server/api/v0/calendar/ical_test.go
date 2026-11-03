package v0_calendar

import (
	"net/http"
	"strings"
	"testing"
)

const smallICal = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:a@example.com\r\n" +
	"DTSTART:20261012T150000Z\r\nDTEND:20261012T160000Z\r\nSUMMARY:Dentist\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

func TestICalExport(t *testing.T) {
	engine, _ := newCalendarEngine(t)
	if w := do(engine, http.MethodPost, "/api/v0/calendar/events", vet); w.Code != http.StatusCreated {
		t.Fatalf("create = %d %s, want 201", w.Code, w.Body.String())
	}
	w := do(engine, http.MethodGet, "/api/v0/calendar/ical", "")
	if w.Code != http.StatusOK || w.Header().Get("Content-Type") != "text/calendar; charset=utf-8" {
		t.Fatalf("export = %d %q, want 200 text/calendar", w.Code, w.Header().Get("Content-Type"))
	}
	if !strings.Contains(w.Body.String(), "\r\nSUMMARY:Vet\r\n") {
		t.Errorf("export lacks the event's SUMMARY:\n%s", w.Body.String())
	}
}

func TestICalImport(t *testing.T) {
	engine, events := newCalendarEngine(t)
	w := do(engine, http.MethodPost, "/api/v0/calendar/ical", smallICal)
	if got := decode[ImportICalJSON](t, w); w.Code != http.StatusOK || got != (ImportICalJSON{Imported: 1}) {
		t.Fatalf("import = %d %s, want 200 with one imported", w.Code, w.Body.String())
	}
	if !heard(events, 0) {
		t.Error("import published no calendar change")
	}
	w = do(engine, http.MethodGet, "/api/v0/calendar/events?from=2026-10-12T00:00:00Z&to=2026-10-13T00:00:00Z", "")
	if list := decode[EventListJSON](t, w); len(list.Events) != 1 || list.Events[0].Title != "Dentist" || !list.Events[0].Mine {
		t.Errorf("listed %+v, want the caller's imported event", list.Events)
	}

	for _, tc := range []struct {
		name string
		body string
		want int
	}{
		{"not iCalendar", "hello", http.StatusBadRequest},
		{"too large", "BEGIN:VCALENDAR\n" + strings.Repeat("x", maxICalBytes), http.StatusRequestEntityTooLarge},
	} {
		if w := do(engine, http.MethodPost, "/api/v0/calendar/ical", tc.body); w.Code != tc.want {
			t.Errorf("%s: import = %d %s, want %d", tc.name, w.Code, w.Body.String(), tc.want)
		}
	}
}

func TestICalURL(t *testing.T) {
	engine, _ := newCalendarEngine(t)
	w := do(engine, http.MethodGet, "/api/v0/calendar/ical/url", "")
	if got := decode[ICalURLJSON](t, w); w.Code != http.StatusOK || got.URL != "http://example.com/api/v0/calendar/ical?token=tok" {
		t.Errorf("url = %d %s, want the feed link carrying the session token", w.Code, w.Body.String())
	}
}

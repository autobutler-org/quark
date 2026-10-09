package calendarutil_test

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
)

func at(s string) time.Time {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		panic(err)
	}
	return t
}

func minutes(m int) *int { return &m }

func timed(title, start, end string) calendarutil.EventInput {
	return calendarutil.EventInput{Title: title, Start: at(start), End: at(end)}
}

func create(t *testing.T, q *db.Queries, input calendarutil.EventInput) calendarutil.Event {
	t.Helper()
	result, err := calendarutil.CreateEvent(context.Background(), calendarutil.CreateEventParams{Queries: q, Input: input})
	if err != nil {
		t.Fatalf("CreateEvent(%q): %v", input.Title, err)
	}
	return result.Event
}

func TestCreateAndGetEvent(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	input := calendarutil.EventInput{
		Title:           "  Vet  ",
		Notes:           "Bring the card.",
		Location:        "Riverside",
		Start:           at("2026-09-29T16:00:00-07:00"),
		End:             at("2026-09-29T16:45:00-07:00"),
		TimeZone:        "America/Los_Angeles",
		Repeat:          calendarutil.RepeatWeekly,
		ReminderMinutes: minutes(30),
		ColorIndex:      2,
	}
	created := create(t, q, input)

	got, err := calendarutil.GetEvent(ctx, calendarutil.GetEventParams{Queries: q, ID: created.ID})
	if err != nil {
		t.Fatalf("GetEvent: %v", err)
	}
	e := got.Event
	if e.Title != "Vet" {
		t.Errorf("title = %q, want it trimmed", e.Title)
	}
	if !e.Start.Equal(input.Start) || e.Start.Location() != time.UTC {
		t.Errorf("start = %v, want %v in UTC", e.Start, input.Start)
	}
	if !e.End.Equal(input.End) {
		t.Errorf("end = %v, want %v", e.End, input.End)
	}
	if e.Repeat != calendarutil.RepeatWeekly || e.ReminderMinutes == nil || *e.ReminderMinutes != 30 ||
		e.ColorIndex != 2 || e.TimeZone != "America/Los_Angeles" || e.Notes != input.Notes || e.Location != input.Location {
		t.Errorf("stored event = %+v, want the input's fields", e)
	}
	if e.CalendarID == 0 {
		t.Error("event has no calendar, want the default one")
	}
}

func TestCreateEventDefaults(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	e := create(t, q, timed("Call", "2026-09-29T12:00:00Z", "2026-09-29T12:30:00Z"))
	if e.Repeat != calendarutil.RepeatNone {
		t.Errorf("repeat = %q, want none", e.Repeat)
	}
	if e.ReminderMinutes != nil {
		t.Errorf("reminder = %d, want none", *e.ReminderMinutes)
	}
}

func TestCreateEventRules(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ok := timed("Call", "2026-09-29T12:00:00Z", "2026-09-29T13:00:00Z")
	allDay := calendarutil.EventInput{Title: "Trip", Start: at("2026-09-26T00:00:00Z"), End: at("2026-09-28T00:00:00Z"), AllDay: true}

	with := func(base calendarutil.EventInput, change func(*calendarutil.EventInput)) calendarutil.EventInput {
		change(&base)
		return base
	}
	tests := []struct {
		name  string
		input calendarutil.EventInput
		valid bool
	}{
		{"timed", ok, true},
		{"all day across two dates", allDay, true},
		{"blank title", with(ok, func(e *calendarutil.EventInput) { e.Title = "   " }), false},
		{"long title", with(ok, func(e *calendarutil.EventInput) { e.Title = strings.Repeat("a", calendarutil.MaxTitleLength+1) }), false},
		{"long location", with(ok, func(e *calendarutil.EventInput) { e.Location = strings.Repeat("a", calendarutil.MaxLocationLength+1) }), false},
		{"long notes", with(ok, func(e *calendarutil.EventInput) { e.Notes = strings.Repeat("a", calendarutil.MaxNotesLength+1) }), false},
		{"long time zone", with(ok, func(e *calendarutil.EventInput) { e.TimeZone = strings.Repeat("a", calendarutil.MaxTimeZoneLength+1) }), false},
		{"IANA time zone", with(ok, func(e *calendarutil.EventInput) { e.TimeZone = "Europe/Berlin" }), true},
		{"UTC time zone", with(ok, func(e *calendarutil.EventInput) { e.TimeZone = "UTC" }), true},
		{"unknown time zone", with(ok, func(e *calendarutil.EventInput) { e.TimeZone = "Not/AZone" }), false},
		{"server-local time zone", with(ok, func(e *calendarutil.EventInput) { e.TimeZone = "Local" }), false},
		{"offset for a time zone", with(ok, func(e *calendarutil.EventInput) { e.TimeZone = "+02:00" }), false},
		{"no start", with(ok, func(e *calendarutil.EventInput) { e.Start = time.Time{} }), false},
		{"ends when it starts", with(ok, func(e *calendarutil.EventInput) { e.End = e.Start }), false},
		{"ends before it starts", with(ok, func(e *calendarutil.EventInput) { e.End = e.Start.Add(-time.Minute) }), false},
		{"unknown repeat", with(ok, func(e *calendarutil.EventInput) { e.Repeat = "yearly" }), false},
		{"color out of range", with(ok, func(e *calendarutil.EventInput) { e.ColorIndex = calendarutil.ColorCount }), false},
		{"negative color", with(ok, func(e *calendarutil.EventInput) { e.ColorIndex = -1 }), false},
		{"all day off midnight", with(allDay, func(e *calendarutil.EventInput) { e.Start = e.Start.Add(time.Hour) }), false},
		{"daily longer than a day", with(ok, func(e *calendarutil.EventInput) {
			e.Repeat = calendarutil.RepeatDaily
			e.End = e.Start.Add(25 * time.Hour)
		}), false},
		{"weekly all day weekend", with(allDay, func(e *calendarutil.EventInput) { e.Repeat = calendarutil.RepeatWeekly }), true},
		{"reminder a week before", with(ok, func(e *calendarutil.EventInput) { e.ReminderMinutes = minutes(calendarutil.MaxReminderMinutes) }), true},
		{"reminder past a week", with(ok, func(e *calendarutil.EventInput) { e.ReminderMinutes = minutes(calendarutil.MaxReminderMinutes + 1) }), false},
		{"timed reminder after the start", with(ok, func(e *calendarutil.EventInput) { e.ReminderMinutes = minutes(-1) }), false},
		{"all day 9 AM on the day", with(allDay, func(e *calendarutil.EventInput) { e.ReminderMinutes = minutes(-540) }), true},
		{"all day 9 AM the day before", with(allDay, func(e *calendarutil.EventInput) { e.ReminderMinutes = minutes(900) }), true},
		{"all day reminder past its day", with(allDay, func(e *calendarutil.EventInput) { e.ReminderMinutes = minutes(-24 * 60) }), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := calendarutil.CreateEvent(context.Background(), calendarutil.CreateEventParams{Queries: q, Input: tt.input})
			if tt.valid && err != nil {
				t.Fatalf("CreateEvent = %v, want it stored", err)
			}
			if !tt.valid && !errors.Is(err, calendarutil.ErrInvalidEvent) {
				t.Fatalf("CreateEvent = %v, want ErrInvalidEvent", err)
			}
		})
	}
}

func TestListEvents(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	before := create(t, q, timed("Before", "2026-09-01T10:00:00Z", "2026-09-01T11:00:00Z"))
	overlapsStart := create(t, q, timed("Overlaps start", "2026-09-27T23:00:00Z", "2026-09-28T01:00:00Z"))
	inside := create(t, q, timed("Inside", "2026-09-29T09:00:00Z", "2026-09-29T10:00:00Z"))
	weekly := create(t, q, calendarutil.EventInput{Title: "Trash night", Start: at("2026-08-03T19:00:00Z"), End: at("2026-08-03T19:15:00Z"), Repeat: calendarutil.RepeatWeekly})
	allDayEdge := create(t, q, calendarutil.EventInput{Title: "Rent", Start: at("2026-10-05T00:00:00Z"), End: at("2026-10-06T00:00:00Z"), AllDay: true})
	after := create(t, q, timed("After", "2026-10-20T10:00:00Z", "2026-10-20T11:00:00Z"))
	laterSeries := create(t, q, calendarutil.EventInput{Title: "Later series", Start: at("2026-11-02T10:00:00Z"), End: at("2026-11-02T11:00:00Z"), Repeat: calendarutil.RepeatDaily})

	// The week of Sep 28, as seen from UTC-7: the Oct 5 all-day event starts at
	// its midnight UTC, inside the padded range, and the app decides.
	result, err := calendarutil.ListEvents(context.Background(), calendarutil.ListEventsParams{
		Queries: q, From: at("2026-09-28T07:00:00Z"), To: at("2026-10-05T07:00:00Z"),
	})
	if err != nil {
		t.Fatalf("ListEvents: %v", err)
	}
	got := map[int64]bool{}
	for _, e := range result.Events {
		got[e.ID] = true
	}
	for _, want := range []calendarutil.Event{overlapsStart, inside, weekly, allDayEdge} {
		if !got[want.ID] {
			t.Errorf("%q missing from the week", want.Title)
		}
	}
	for _, unwanted := range []calendarutil.Event{before, after, laterSeries} {
		if got[unwanted.ID] {
			t.Errorf("%q listed, want it left out", unwanted.Title)
		}
	}
	for i := 1; i < len(result.Events); i++ {
		if result.Events[i].Start.Before(result.Events[i-1].Start) {
			t.Fatalf("events not in start order: %v", result.Events)
		}
	}
}

// TestListEventsSkipsSeriesOutsideRange checks a repeating series is listed
// only when one of its occurrences can fall in the range, however long ago it
// began (#2535).
func TestListEventsSkipsSeriesOutsideRange(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	series := func(title, start, end string, repeat calendarutil.Repeat) calendarutil.Event {
		return create(t, q, calendarutil.EventInput{Title: title, Start: at(start), End: at(end), Repeat: repeat})
	}
	daily := series("Daily walk", "2020-01-01T07:00:00Z", "2020-01-01T07:30:00Z", calendarutil.RepeatDaily)
	wednesdays := series("Wednesday choir", "2025-01-01T18:00:00Z", "2025-01-01T19:00:00Z", calendarutil.RepeatWeekly)
	mondays := series("Monday trash", "2026-08-03T19:00:00Z", "2026-08-03T19:15:00Z", calendarutil.RepeatWeekly)
	twentieth := series("Rent on the 20th", "2024-01-20T10:00:00Z", "2024-01-20T11:00:00Z", calendarutil.RepeatMonthly)
	// The 1st at 5 AM in UTC+10 is the 31st in UTC: September has no 31st,
	// but its viewer's October 1st still has the occurrence.
	firstLocal := series("Bills on the 1st", "2026-01-31T19:00:00Z", "2026-01-31T20:00:00Z", calendarutil.RepeatMonthly)
	sunday := series("Sunday brunch", "2026-01-04T11:00:00Z", "2026-01-04T12:00:00Z", calendarutil.RepeatWeekly)

	list := func(from, to string) map[int64]bool {
		t.Helper()
		result, err := calendarutil.ListEvents(context.Background(), calendarutil.ListEventsParams{Queries: q, From: at(from), To: at(to)})
		if err != nil {
			t.Fatalf("ListEvents: %v", err)
		}
		got := map[int64]bool{}
		for _, e := range result.Events {
			got[e.ID] = true
		}
		return got
	}
	check := func(view string, got map[int64]bool, want, unwanted []calendarutil.Event) {
		t.Helper()
		for _, e := range want {
			if !got[e.ID] {
				t.Errorf("%s: %q missing", view, e.Title)
			}
		}
		for _, e := range unwanted {
			if got[e.ID] {
				t.Errorf("%s: %q listed, but no occurrence falls in it", view, e.Title)
			}
		}
	}

	// Wednesday Oct 7 2026, as seen from UTC-7.
	check("a Wednesday", list("2026-10-07T07:00:00Z", "2026-10-08T07:00:00Z"),
		[]calendarutil.Event{daily, wednesdays}, []calendarutil.Event{mondays, twentieth, firstLocal, sunday})
	// Thursday Oct 1 2026, as seen from UTC+10.
	check("the 1st", list("2026-09-30T14:00:00Z", "2026-10-01T14:00:00Z"),
		[]calendarutil.Event{daily, firstLocal}, []calendarutil.Event{mondays, twentieth, sunday})
	// A week far in the future still holds every weekly series.
	check("a week in 2099", list("2099-01-05T00:00:00Z", "2099-01-12T00:00:00Z"),
		[]calendarutil.Event{daily, wednesdays, mondays, sunday}, []calendarutil.Event{twentieth, firstLocal})
}

func TestListEventsRange(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	from := at("2026-09-01T00:00:00Z")
	for name, to := range map[string]time.Time{
		"empty":    from,
		"reversed": from.Add(-time.Hour),
		"too long": from.Add(calendarutil.MaxListRange + time.Hour),
	} {
		_, err := calendarutil.ListEvents(context.Background(), calendarutil.ListEventsParams{Queries: q, From: from, To: to})
		if !errors.Is(err, calendarutil.ErrInvalidEvent) {
			t.Errorf("%s range: ListEvents = %v, want ErrInvalidEvent", name, err)
		}
	}
}

func TestUpdateEvent(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	e := create(t, q, timed("Call", "2026-09-29T12:00:00Z", "2026-09-29T12:30:00Z"))

	change := timed("Longer call", "2026-09-29T12:00:00Z", "2026-09-29T13:00:00Z")
	change.Repeat = calendarutil.RepeatMonthly
	updated, err := calendarutil.UpdateEvent(ctx, calendarutil.UpdateEventParams{Queries: q, ID: e.ID, Input: change})
	if err != nil {
		t.Fatalf("UpdateEvent: %v", err)
	}
	if updated.Event.Title != "Longer call" || !updated.Event.End.Equal(change.End) || updated.Event.Repeat != calendarutil.RepeatMonthly {
		t.Errorf("updated = %+v, want the new fields", updated.Event)
	}

	change.Title = ""
	if _, err := calendarutil.UpdateEvent(ctx, calendarutil.UpdateEventParams{Queries: q, ID: e.ID, Input: change}); !errors.Is(err, calendarutil.ErrInvalidEvent) {
		t.Errorf("UpdateEvent without a title = %v, want ErrInvalidEvent", err)
	}

	change.Title = "Gone"
	if _, err := calendarutil.UpdateEvent(ctx, calendarutil.UpdateEventParams{Queries: q, ID: e.ID + 100, Input: change}); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("UpdateEvent of a missing event = %v, want sql.ErrNoRows", err)
	}
}

func TestDeleteEvent(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	e := create(t, q, timed("Call", "2026-09-29T12:00:00Z", "2026-09-29T12:30:00Z"))

	if _, err := calendarutil.DeleteEvent(ctx, calendarutil.DeleteEventParams{Queries: q, ID: e.ID}); err != nil {
		t.Fatalf("DeleteEvent: %v", err)
	}
	if _, err := calendarutil.GetEvent(ctx, calendarutil.GetEventParams{Queries: q, ID: e.ID}); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("GetEvent after delete = %v, want sql.ErrNoRows", err)
	}
	if _, err := calendarutil.DeleteEvent(ctx, calendarutil.DeleteEventParams{Queries: q, ID: e.ID}); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("second DeleteEvent = %v, want sql.ErrNoRows", err)
	}
}

func TestEventOwner(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()
	user, err := q.CreateUser(ctx, db.CreateUserParams{Username: "maya", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	created, err := calendarutil.CreateEvent(ctx, calendarutil.CreateEventParams{
		Queries:   q,
		Input:     timed("Piano", "2026-09-17T16:00:00Z", "2026-09-17T17:00:00Z"),
		CreatedBy: user.ID,
	})
	if err != nil {
		t.Fatalf("CreateEvent: %v", err)
	}
	if created.Event.OwnerID != user.ID || created.Event.OwnerName != "maya" {
		t.Errorf("owner = %d %q, want maya", created.Event.OwnerID, created.Event.OwnerName)
	}

	// Someone else's edit leaves the owner alone.
	updated, err := calendarutil.UpdateEvent(ctx, calendarutil.UpdateEventParams{
		Queries: q, ID: created.Event.ID, Input: timed("Piano lesson", "2026-09-17T16:00:00Z", "2026-09-17T17:00:00Z"),
	})
	if err != nil {
		t.Fatalf("UpdateEvent: %v", err)
	}
	if updated.Event.OwnerName != "maya" || updated.Event.Title != "Piano lesson" {
		t.Errorf("updated = %+v, want the title changed and maya still the owner", updated.Event)
	}

	listed, err := calendarutil.ListEvents(ctx, calendarutil.ListEventsParams{
		Queries: q, From: at("2026-09-17T00:00:00Z"), To: at("2026-09-18T00:00:00Z"),
	})
	if err != nil || len(listed.Events) != 1 || listed.Events[0].OwnerName != "maya" {
		t.Fatalf("ListEvents = %+v, %v; want maya's event", listed.Events, err)
	}

	// Deleting the account keeps the event and forgets its owner.
	if err := q.DeleteUser(ctx, user.ID); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	orphan, err := calendarutil.GetEvent(ctx, calendarutil.GetEventParams{Queries: q, ID: created.Event.ID})
	if err != nil {
		t.Fatalf("GetEvent after the owner was deleted: %v", err)
	}
	if orphan.Event.OwnerID != 0 || orphan.Event.OwnerName != "" {
		t.Errorf("owner after delete = %d %q, want none", orphan.Event.OwnerID, orphan.Event.OwnerName)
	}
}

func dayPtr(s string) *time.Time {
	t := at(s)
	return &t
}

func TestRepeatUntil(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	ctx := context.Background()

	// A daily 7 PM walk in UTC-7, through Saturday Oct 31 2026.
	walk := timed("Walk", "2026-10-01T02:00:00Z", "2026-10-01T02:30:00Z")
	walk.Repeat = calendarutil.RepeatDaily
	walk.RepeatUntil = dayPtr("2026-10-31T00:00:00Z")
	e := create(t, q, walk)
	if e.RepeatUntil == nil || !e.RepeatUntil.Equal(*walk.RepeatUntil) {
		t.Fatalf("repeat until = %v, want %v", e.RepeatUntil, walk.RepeatUntil)
	}

	// Its first walk is Sep 30 at home, though Oct 1 in UTC: a series that
	// ends that same day is one walk, not an error.
	once := walk
	once.RepeatUntil = dayPtr("2026-09-30T00:00:00Z")
	create(t, q, once)

	forever := timed("Forever", "2026-10-01T02:00:00Z", "2026-10-01T02:30:00Z")
	forever.Repeat = calendarutil.RepeatDaily
	endless := create(t, q, forever)
	if endless.RepeatUntil != nil {
		t.Errorf("repeat until = %v, want nil when none is given", endless.RepeatUntil)
	}

	// A one-off event has nothing to end: the date is dropped, not refused.
	oneOff := timed("Dentist", "2026-10-01T16:00:00Z", "2026-10-01T17:00:00Z")
	oneOff.RepeatUntil = dayPtr("2026-12-31T00:00:00Z")
	if got := create(t, q, oneOff); got.RepeatUntil != nil {
		t.Errorf("one-off repeat until = %v, want nil", got.RepeatUntil)
	}

	list := func(from, to string) map[int64]bool {
		t.Helper()
		result, err := calendarutil.ListEvents(ctx, calendarutil.ListEventsParams{Queries: q, From: at(from), To: at(to)})
		if err != nil {
			t.Fatalf("ListEvents: %v", err)
		}
		got := map[int64]bool{}
		for _, e := range result.Events {
			got[e.ID] = true
		}
		return got
	}
	for view, w := range map[string]struct {
		from, to string
		want     bool
	}{
		"its last day, Oct 31":  {"2026-10-31T07:00:00Z", "2026-11-01T07:00:00Z", true},
		"the week after it":     {"2026-11-09T07:00:00Z", "2026-11-16T07:00:00Z", false},
		"a week in 2099":        {"2099-01-05T00:00:00Z", "2099-01-12T00:00:00Z", false},
		"a month it repeats in": {"2026-10-01T07:00:00Z", "2026-11-01T07:00:00Z", true},
	} {
		got := list(w.from, w.to)
		if got[e.ID] != w.want {
			t.Errorf("%s: walk listed = %v, want %v", view, got[e.ID], w.want)
		}
		if !got[endless.ID] {
			t.Errorf("%s: a series with no end is missing", view)
		}
	}

	// Taking the end away makes it repeat forever again.
	walk.RepeatUntil = nil
	updated, err := calendarutil.UpdateEvent(ctx, calendarutil.UpdateEventParams{Queries: q, ID: e.ID, Input: walk})
	if err != nil || updated.Event.RepeatUntil != nil {
		t.Fatalf("UpdateEvent without an end = %+v, %v; want no end", updated.Event, err)
	}
	if !list("2099-01-05T00:00:00Z", "2099-01-12T00:00:00Z")[e.ID] {
		t.Error("a series whose end was removed is missing from 2099")
	}
}

func TestRepeatUntilRules(t *testing.T) {
	q := dbtest.NewDB(t).Queries
	for name, w := range map[string]struct {
		allDay      bool
		start, end  string
		until, rule string
	}{
		"a time of day":           {false, "2026-10-01T16:00:00Z", "2026-10-01T17:00:00Z", "2026-10-31T09:00:00Z", "a date"},
		"before a timed start":    {false, "2026-10-01T16:00:00Z", "2026-10-01T17:00:00Z", "2026-09-29T00:00:00Z", "on or after"},
		"before an all-day start": {true, "2026-10-01T00:00:00Z", "2026-10-02T00:00:00Z", "2026-09-30T00:00:00Z", "on or after"},
	} {
		input := timed("Series", w.start, w.end)
		input.AllDay = w.allDay
		input.Repeat = calendarutil.RepeatWeekly
		input.RepeatUntil = dayPtr(w.until)
		_, err := calendarutil.CreateEvent(context.Background(), calendarutil.CreateEventParams{Queries: q, Input: input})
		if !errors.Is(err, calendarutil.ErrInvalidEvent) || !strings.Contains(err.Error(), w.rule) {
			t.Errorf("%s: CreateEvent = %v, want ErrInvalidEvent naming %q", name, err, w.rule)
		}
	}
	// An all-day series may end on its first day.
	input := calendarutil.EventInput{Title: "Once", Start: at("2026-10-01T00:00:00Z"), End: at("2026-10-02T00:00:00Z"),
		AllDay: true, Repeat: calendarutil.RepeatWeekly, RepeatUntil: dayPtr("2026-10-01T00:00:00Z")}
	create(t, q, input)
}

package calendarutil_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
)

const newYork = "America/New_York"

// expand returns the starts and reminder times of e's occurrences starting in
// [from, to), as RFC 3339 in UTC; a missing reminder is "".
func expand(t *testing.T, e calendarutil.Event, from, to string) (starts, reminders []string) {
	t.Helper()
	result, err := calendarutil.ExpandEvent(calendarutil.ExpandEventParams{Event: e, From: at(from), To: at(to)})
	if err != nil {
		t.Fatalf("ExpandEvent: %v", err)
	}
	for _, o := range result.Occurrences {
		starts = append(starts, o.Start.UTC().Format(time.RFC3339))
		reminder := ""
		if o.ReminderAt != nil {
			reminder = o.ReminderAt.UTC().Format(time.RFC3339)
		}
		reminders = append(reminders, reminder)
		if want := o.Start.Add(e.End.Sub(e.Start)); !e.AllDay && !o.End.Equal(want) {
			t.Errorf("occurrence at %v ends %v, want %v", o.Start, o.End, want)
		}
	}
	return starts, reminders
}

func equal(t *testing.T, what string, got, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("%s = %v, want %v", what, got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%s = %v, want %v", what, got, want)
		}
	}
}

func TestExpandEventKeepsLocalTimeAcrossSpringForward(t *testing.T) {
	// 9 AM every Sunday in New York, whose clocks go forward on Mar 8 2026.
	e := calendarutil.Event{
		Start: at("2026-03-01T14:00:00Z"), End: at("2026-03-01T15:00:00Z"),
		TimeZone: newYork, Repeat: calendarutil.RepeatWeekly, ReminderMinutes: minutes(30),
	}
	starts, reminders := expand(t, e, "2026-03-01T00:00:00Z", "2026-03-16T00:00:00Z")
	equal(t, "starts", starts, []string{"2026-03-01T14:00:00Z", "2026-03-08T13:00:00Z", "2026-03-15T13:00:00Z"})
	equal(t, "reminders", reminders, []string{"2026-03-01T13:30:00Z", "2026-03-08T12:30:00Z", "2026-03-15T12:30:00Z"})
}

func TestExpandEventKeepsLocalTimeAcrossFallBack(t *testing.T) {
	// 9 AM every day in New York, whose clocks go back on Nov 1 2026. The
	// series began in the summer: the range is reached without walking it.
	e := calendarutil.Event{
		Start: at("2026-06-01T13:00:00Z"), End: at("2026-06-01T13:30:00Z"),
		TimeZone: newYork, Repeat: calendarutil.RepeatDaily,
	}
	starts, reminders := expand(t, e, "2026-10-31T00:00:00Z", "2026-11-02T23:00:00Z")
	equal(t, "starts", starts, []string{"2026-10-31T13:00:00Z", "2026-11-01T14:00:00Z", "2026-11-02T14:00:00Z"})
	equal(t, "reminders", reminders, []string{"", "", ""})
}

func TestExpandEventMonthlySkipsShortMonths(t *testing.T) {
	// The 31st at 9 AM in New York: no February, and March is on summer time.
	e := calendarutil.Event{
		Start: at("2026-01-31T14:00:00Z"), End: at("2026-01-31T15:00:00Z"),
		TimeZone: newYork, Repeat: calendarutil.RepeatMonthly,
	}
	starts, _ := expand(t, e, "2026-01-01T00:00:00Z", "2026-06-01T00:00:00Z")
	equal(t, "starts", starts, []string{"2026-01-31T14:00:00Z", "2026-03-31T13:00:00Z", "2026-05-31T13:00:00Z"})
}

func TestExpandEventAllDayReminderKeepsItsTimeOfDay(t *testing.T) {
	// An all-day event every day, reminded at 9 AM on the day, in New York:
	// midnight there, and 9 AM even on the 23-hour day.
	e := calendarutil.Event{
		Start: at("2026-03-07T00:00:00Z"), End: at("2026-03-08T00:00:00Z"), AllDay: true,
		TimeZone: newYork, Repeat: calendarutil.RepeatDaily, ReminderMinutes: minutes(-540),
	}
	starts, reminders := expand(t, e, "2026-03-07T00:00:00Z", "2026-03-10T00:00:00Z")
	equal(t, "starts", starts, []string{"2026-03-07T05:00:00Z", "2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z"})
	equal(t, "reminders", reminders, []string{"2026-03-07T14:00:00Z", "2026-03-08T13:00:00Z", "2026-03-09T13:00:00Z"})

	// The day before at 9 AM is 900 minutes back from midnight.
	e.ReminderMinutes = minutes(900)
	_, reminders = expand(t, e, "2026-03-09T00:00:00Z", "2026-03-10T00:00:00Z")
	equal(t, "reminders", reminders, []string{"2026-03-08T13:00:00Z"})
}

func TestExpandEventRepeatUntilIsALocalDate(t *testing.T) {
	// 7 PM daily in Los Angeles from Sep 30, which is Oct 1 in UTC, through
	// Oct 2 there.
	e := calendarutil.Event{
		Start: at("2026-10-01T02:00:00Z"), End: at("2026-10-01T02:30:00Z"),
		TimeZone: "America/Los_Angeles", Repeat: calendarutil.RepeatDaily,
		RepeatUntil: dayPtr("2026-10-02T00:00:00Z"),
	}
	starts, _ := expand(t, e, "2026-09-01T00:00:00Z", "2026-11-01T00:00:00Z")
	equal(t, "starts", starts, []string{"2026-10-01T02:00:00Z", "2026-10-02T02:00:00Z", "2026-10-03T02:00:00Z"})
}

func TestExpandEventWithoutAZone(t *testing.T) {
	// No zone, or one the database no longer knows, is expanded in UTC.
	for _, zone := range []string{"", "Mars/Olympus_Mons"} {
		e := calendarutil.Event{
			Start: at("2026-03-07T14:00:00Z"), End: at("2026-03-07T15:00:00Z"),
			TimeZone: zone, Repeat: calendarutil.RepeatDaily,
		}
		starts, _ := expand(t, e, "2026-03-08T00:00:00Z", "2026-03-10T00:00:00Z")
		equal(t, "starts in "+zone, starts, []string{"2026-03-08T14:00:00Z", "2026-03-09T14:00:00Z"})
	}

	// A one-off event is its own only occurrence, inside the range or not.
	once := calendarutil.Event{Start: at("2026-03-07T14:00:00Z"), End: at("2026-03-07T15:00:00Z"), Repeat: calendarutil.RepeatNone}
	starts, _ := expand(t, once, "2026-03-07T00:00:00Z", "2026-03-08T00:00:00Z")
	equal(t, "one-off", starts, []string{"2026-03-07T14:00:00Z"})
	starts, _ = expand(t, once, "2026-03-08T00:00:00Z", "2026-03-09T00:00:00Z")
	equal(t, "one-off out of range", starts, nil)
}

func TestExpandEventRange(t *testing.T) {
	e := calendarutil.Event{Start: at("2026-03-07T14:00:00Z"), End: at("2026-03-07T15:00:00Z")}
	for name, to := range map[string]string{"empty": "2026-03-07T00:00:00Z", "too wide": "2028-03-07T00:00:00Z"} {
		_, err := calendarutil.ExpandEvent(calendarutil.ExpandEventParams{Event: e, From: at("2026-03-07T00:00:00Z"), To: at(to)})
		if !errors.Is(err, calendarutil.ErrInvalidEvent) {
			t.Errorf("%s range: err = %v, want ErrInvalidEvent", name, err)
		}
	}
}

func TestListReminders(t *testing.T) {
	q := dbtest.NewDB(t).Queries

	// 9 AM every Sunday in New York, reminded half an hour before.
	weekly := timed("Brunch", "2026-03-01T14:00:00Z", "2026-03-01T15:00:00Z")
	weekly.TimeZone, weekly.Repeat, weekly.ReminderMinutes = newYork, calendarutil.RepeatWeekly, minutes(30)
	brunch := create(t, q, weekly)

	// An all-day event on Mar 8, reminded at 9 AM the day before.
	allDay := calendarutil.EventInput{
		Title: "Birthday", Start: at("2026-03-08T00:00:00Z"), End: at("2026-03-09T00:00:00Z"),
		AllDay: true, TimeZone: newYork, ReminderMinutes: minutes(900),
	}
	birthday := create(t, q, allDay)

	// An event with a week's notice, the furthest a reminder reaches.
	early := timed("Trip", "2026-03-15T12:00:00Z", "2026-03-15T13:00:00Z")
	early.ReminderMinutes = minutes(calendarutil.MaxReminderMinutes)
	trip := create(t, q, early)

	// No reminder, so never listed.
	create(t, q, timed("Quiet", "2026-03-08T12:15:00Z", "2026-03-08T13:00:00Z"))

	list := func(from, to string) []calendarutil.Reminder {
		t.Helper()
		result, err := calendarutil.ListReminders(context.Background(), calendarutil.ListRemindersParams{
			Queries: q, From: at(from), To: at(to),
		})
		if err != nil {
			t.Fatalf("ListReminders: %v", err)
		}
		return result.Reminders
	}

	// Mar 7 and 8 in UTC: the birthday's, then the trip's and the brunch's
	// second, which summer time moved an hour earlier.
	got := list("2026-03-07T00:00:00Z", "2026-03-09T00:00:00Z")
	want := []struct {
		id int64
		at string
	}{
		{birthday.ID, "2026-03-07T14:00:00Z"},
		{trip.ID, "2026-03-08T12:00:00Z"},
		{brunch.ID, "2026-03-08T12:30:00Z"},
	}
	if len(got) != len(want) {
		t.Fatalf("reminders = %+v, want %d", got, len(want))
	}
	for i, w := range want {
		if got[i].Event.ID != w.id || !got[i].Occurrence.ReminderAt.Equal(at(w.at)) {
			t.Errorf("reminder %d = event %d at %v, want event %d at %s",
				i, got[i].Event.ID, got[i].Occurrence.ReminderAt, w.id, w.at)
		}
	}

	// The range ends before its end: a reminder at 12:30 is not in [12:00, 12:30).
	if got := list("2026-03-08T12:00:00Z", "2026-03-08T12:30:00Z"); len(got) != 1 || got[0].Event.ID != trip.ID {
		t.Errorf("reminders = %+v, want only the trip's", got)
	}

	if _, err := calendarutil.ListReminders(context.Background(), calendarutil.ListRemindersParams{
		Queries: q, From: at("2026-03-08T00:00:00Z"), To: at("2026-03-08T00:00:00Z"),
	}); !errors.Is(err, calendarutil.ErrInvalidEvent) {
		t.Errorf("empty range: err = %v, want ErrInvalidEvent", err)
	}
}

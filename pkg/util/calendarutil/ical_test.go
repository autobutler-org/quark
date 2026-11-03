package calendarutil_test

import (
	"bytes"
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
)

func importICal(t *testing.T, database *db.DatabaseSqlc, text string) calendarutil.ImportICalResult {
	t.Helper()
	result, err := calendarutil.ImportICal(context.Background(), calendarutil.ImportICalParams{Database: database, Reader: strings.NewReader(text)})
	if err != nil {
		t.Fatalf("ImportICal: %v", err)
	}
	return result
}

// byTitle lists every event in October and November 2026 by title.
func byTitle(t *testing.T, q db.Querier) map[string]calendarutil.Event {
	t.Helper()
	list, err := calendarutil.ListEvents(context.Background(), calendarutil.ListEventsParams{
		Queries: q, From: at("2026-10-01T00:00:00Z"), To: at("2026-12-01T00:00:00Z"),
	})
	if err != nil {
		t.Fatalf("ListEvents: %v", err)
	}
	events := map[string]calendarutil.Event{}
	for _, e := range list.Events {
		events[e.Title] = e
	}
	return events
}

func TestICalRoundTrip(t *testing.T) {
	source := dbtest.NewDB(t)
	until := at("2026-12-29T00:00:00Z")
	notes := "Bring wine, cheese\nand bread; " + strings.Repeat("é", 60)
	originals := []calendarutil.Event{
		create(t, source.Queries, calendarutil.EventInput{
			Title: "Standup", Start: at("2026-10-06T09:00:00-07:00"), End: at("2026-10-06T10:00:00-07:00"),
			TimeZone: "America/Los_Angeles", Repeat: calendarutil.RepeatWeekly, RepeatUntil: &until,
			ExcludedStarts: []time.Time{at("2026-10-13T16:00:00Z")},
		}),
		create(t, source.Queries, calendarutil.EventInput{
			Title: "Trip", Start: at("2026-10-10T00:00:00Z"), End: at("2026-10-12T00:00:00Z"), AllDay: true,
		}),
		create(t, source.Queries, calendarutil.EventInput{
			Title: "Dinner", Notes: notes, Location: "Home", Start: at("2026-10-20T18:00:00Z"), End: at("2026-10-20T19:00:00Z"),
		}),
	}

	var out bytes.Buffer
	exported, err := calendarutil.ExportICal(context.Background(), calendarutil.ExportICalParams{Queries: source.Queries, Writer: &out})
	if err != nil || exported.Events != 3 {
		t.Fatalf("ExportICal = %+v, %v; want 3 events", exported, err)
	}
	text := out.String()
	for _, want := range []string{
		"BEGIN:VCALENDAR\r\n",
		"DTSTART;TZID=America/Los_Angeles:20261006T090000\r\n",
		"RRULE:FREQ=WEEKLY;UNTIL=20261230T075959Z\r\n",
		"EXDATE;TZID=America/Los_Angeles:20261013T090000\r\n",
		"DTSTART;VALUE=DATE:20261010\r\n",
		"DTEND;VALUE=DATE:20261012\r\n",
		"DTSTART:20261020T180000Z\r\n",
		"DESCRIPTION:Bring wine\\, cheese\\nand bread\\; ",
		"\r\n ",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("export lacks %q:\n%s", want, text)
		}
	}
	for _, line := range strings.Split(strings.TrimSuffix(text, "\r\n"), "\r\n") {
		if len(line) > 75 || strings.Contains(line, "\n") {
			t.Errorf("line %q is longer than 75 octets or not CRLF-ended", line)
		}
	}

	target := dbtest.NewDB(t)
	if got := importICal(t, target, text); got != (calendarutil.ImportICalResult{Imported: 3}) {
		t.Fatalf("import = %+v, want 3 imported", got)
	}
	imported := byTitle(t, target.Queries)
	for _, want := range originals {
		got, ok := imported[want.Title]
		if !ok {
			t.Errorf("%s was not imported", want.Title)
			continue
		}
		if !got.Start.Equal(want.Start) || !got.End.Equal(want.End) || got.AllDay != want.AllDay ||
			got.TimeZone != want.TimeZone || got.Repeat != want.Repeat || got.Notes != want.Notes ||
			got.Location != want.Location || !reflect.DeepEqual(got.RepeatUntil, want.RepeatUntil) ||
			!reflect.DeepEqual(got.ExcludedStarts, want.ExcludedStarts) {
			t.Errorf("imported %+v\nwant     %+v", got, want)
		}
	}

	expand := func(e calendarutil.Event) []calendarutil.Occurrence {
		result, err := calendarutil.ExpandEvent(calendarutil.ExpandEventParams{Event: e, From: at("2026-10-15T00:00:00Z"), To: at("2026-11-15T00:00:00Z")})
		if err != nil {
			t.Fatalf("ExpandEvent: %v", err)
		}
		return result.Occurrences
	}
	if got, want := expand(imported["Standup"]), expand(originals[0]); !reflect.DeepEqual(got, want) || len(want) != 4 {
		t.Errorf("imported occurrences = %v, want %v", got, want)
	}

	if got := importICal(t, target, text); got != (calendarutil.ImportICalResult{Skipped: 3}) {
		t.Errorf("second import = %+v, want every event skipped", got)
	}
}

// googleExport is shaped like Google Calendar's export: a calendar zone, a
// VTIMEZONE, folded text, an alarm, and a moved occurrence.
const googleExport = `BEGIN:VCALENDAR
PRODID:-//Google Inc//Google Calendar 70.9054//EN
VERSION:2.0
CALSCALE:GREGORIAN
METHOD:PUBLISH
X-WR-CALNAME:Family
X-WR-TIMEZONE:America/New_York
BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:DAYLIGHT
TZOFFSETFROM:-0500
TZOFFSETTO:-0400
DTSTART:19700308T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
DTSTART;TZID=America/New_York:20261006T183000
DTEND;TZID=America/New_York:20261006T193000
RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=TU;COUNT=4
DTSTAMP:20261001T120000Z
UID:piano@google.com
DESCRIPTION:Bring the music book\, and the metronome. This line is long eno
 ugh to be folded.
LOCATION:Music school
STATUS:CONFIRMED
SUMMARY:Piano
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:This is an event reminder
TRIGGER:-P0DT0H30M0S
END:VALARM
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=America/New_York:20261014T190000
DTEND;TZID=America/New_York:20261014T200000
DTSTAMP:20261001T120000Z
UID:piano@google.com
RECURRENCE-ID;TZID=America/New_York:20261013T183000
SUMMARY:Piano (moved)
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261015
DTEND;VALUE=DATE:20261016
RRULE:FREQ=YEARLY
UID:birthday@google.com
SUMMARY:Birthday
END:VEVENT
BEGIN:VEVENT
DTSTART:20261016T150000Z
DTEND:20261016T160000Z
RRULE:FREQ=WEEKLY;INTERVAL=2
UID:fortnightly@google.com
SUMMARY:Fortnightly
END:VEVENT
BEGIN:VEVENT
DTSTART:20261017T150000Z
DTEND:20261017T160000Z
UID:cancelled@google.com
STATUS:CANCELLED
SUMMARY:Cancelled
END:VEVENT
BEGIN:VEVENT
DTSTART:20261008T120000
DTEND:20261008T130000
UID:floating@google.com
SUMMARY:Lunch
END:VEVENT
BEGIN:VEVENT
DTSTART:20261009T140000Z
DURATION:PT1H30M
UID:duration@google.com
SUMMARY:Workshop
END:VEVENT
END:VCALENDAR
`

func TestImportGoogleExport(t *testing.T) {
	database := dbtest.NewDB(t)
	if got := importICal(t, database, googleExport); got != (calendarutil.ImportICalResult{Imported: 4, Skipped: 3}) {
		t.Fatalf("import = %+v, want 4 imported and the yearly, fortnightly and cancelled ones skipped", got)
	}
	events := byTitle(t, database.Queries)

	piano := events["Piano"]
	if piano.Repeat != calendarutil.RepeatWeekly || piano.TimeZone != "America/New_York" ||
		!piano.Start.Equal(at("2026-10-06T22:30:00Z")) || !piano.End.Equal(at("2026-10-06T23:30:00Z")) {
		t.Errorf("piano = %+v, want a weekly series at 6:30 PM New York time", piano)
	}
	if piano.RepeatUntil == nil || !piano.RepeatUntil.Equal(at("2026-10-27T00:00:00Z")) {
		t.Errorf("piano repeats until %v, want the fourth Tuesday, October 27", piano.RepeatUntil)
	}
	if !reflect.DeepEqual(piano.ExcludedStarts, []time.Time{at("2026-10-13T22:30:00Z")}) {
		t.Errorf("piano skips %v, want the moved occurrence", piano.ExcludedStarts)
	}
	if want := "Bring the music book, and the metronome. This line is long enough to be folded."; piano.Notes != want {
		t.Errorf("piano notes = %q, want %q", piano.Notes, want)
	}

	moved := events["Piano (moved)"]
	if moved.Repeat != calendarutil.RepeatNone || !moved.Start.Equal(at("2026-10-14T23:00:00Z")) {
		t.Errorf("moved = %+v, want a one-off on Wednesday at 7 PM New York time", moved)
	}
	if lunch := events["Lunch"]; !lunch.Start.Equal(at("2026-10-08T16:00:00Z")) || lunch.TimeZone != "America/New_York" {
		t.Errorf("lunch = %+v, want the floating noon read in New York", lunch)
	}
	if workshop := events["Workshop"]; !workshop.End.Equal(at("2026-10-09T15:30:00Z")) {
		t.Errorf("workshop ends %v, want 90 minutes after it starts", workshop.End)
	}
}

func TestImportICalRejectsOtherText(t *testing.T) {
	_, err := calendarutil.ImportICal(context.Background(), calendarutil.ImportICalParams{
		Database: dbtest.NewDB(t), Reader: strings.NewReader("BEGIN:VCARD\nFN:Ada\nEND:VCARD\n"),
	})
	if !errors.Is(err, calendarutil.ErrInvalidICal) {
		t.Errorf("err = %v, want ErrInvalidICal", err)
	}
}

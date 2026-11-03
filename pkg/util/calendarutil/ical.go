package calendarutil

import (
	"bufio"
	"context"
	"database/sql"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
)

// The iCalendar date and date-time forms (RFC 5545 §3.3.4, §3.3.5).
const (
	icalDate  = "20060102"
	icalLocal = "20060102T150405"
	icalUTC   = "20060102T150405Z"
)

// maxICalCount is the largest COUNT read as an end date; a longer series is
// read as repeating forever rather than stepped occurrence by occurrence.
const maxICalCount = 10000

// icalProperty is one content line's parameters, names upper-cased, and its
// raw value.
type icalProperty struct {
	params map[string]string
	value  string
}

// icalEvent is one VEVENT read as an event. ok is false for one skipped.
type icalEvent struct {
	uid          string
	recurrenceID *time.Time
	input        EventInput
	ok           bool
}

// icalText escapes a TEXT value (RFC 5545 §3.3.11).
var icalText = strings.NewReplacer(`\`, `\\`, ";", `\;`, ",", `\,`, "\r\n", `\n`, "\n", `\n`)

// icalUntext undoes icalText.
var icalUntext = strings.NewReplacer(`\\`, `\`, `\n`, "\n", `\N`, "\n", `\,`, ",", `\;`, ";")

// writeICal writes the calendar named name, holding rows, to out.
func writeICal(out io.Writer, name string, rows []db.ListCalendarEventsRow) error {
	w := bufio.NewWriter(out)
	for _, line := range []string{
		"BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Quark//Calendar//EN", "CALSCALE:GREGORIAN",
		"METHOD:PUBLISH", "X-WR-CALNAME:" + icalText.Replace(name),
	} {
		writeICalLine(w, line)
	}
	for _, row := range rows {
		event, err := fromRow(row.CalendarEvent, row.OwnerName)
		if err != nil {
			return err
		}
		for _, line := range eventICalLines(event) {
			writeICalLine(w, line)
		}
	}
	writeICalLine(w, "END:VCALENDAR")
	// bufio keeps the first write error, so Flush reports it.
	return w.Flush()
}

// writeICalLine writes line ending in CRLF, folded at 75 octets without
// splitting a UTF-8 sequence; each continuation begins with a space. A write
// error is left to w, which keeps it for writeICal's Flush.
func writeICalLine(w *bufio.Writer, line string) {
	for limit := 75; len(line) > limit; limit = 74 {
		n := limit
		for !utf8.RuneStart(line[n]) {
			n--
		}
		_, _ = w.WriteString(line[:n] + "\r\n ")
		line = line[n:]
	}
	_, _ = w.WriteString(line + "\r\n")
}

// eventICalLines is e as a VEVENT.
func eventICalLines(e Event) []string {
	lines := []string{
		"BEGIN:VEVENT",
		fmt.Sprintf("UID:quark-event-%d@quark", e.ID),
		"DTSTAMP:" + e.UpdatedAt.UTC().Format(icalUTC),
		"CREATED:" + e.CreatedAt.UTC().Format(icalUTC),
		"LAST-MODIFIED:" + e.UpdatedAt.UTC().Format(icalUTC),
		icalTime("DTSTART", e, e.Start),
		icalTime("DTEND", e, e.End),
		"SUMMARY:" + icalText.Replace(e.Title),
	}
	if e.Notes != "" {
		lines = append(lines, "DESCRIPTION:"+icalText.Replace(e.Notes))
	}
	if e.Location != "" {
		lines = append(lines, "LOCATION:"+icalText.Replace(e.Location))
	}
	if e.Repeat != RepeatNone {
		rule := "RRULE:FREQ=" + strings.ToUpper(string(e.Repeat))
		if u := e.RepeatUntil; u != nil && e.AllDay {
			rule += ";UNTIL=" + u.Format(icalDate)
		} else if u != nil {
			// With a TZID on DTSTART, UNTIL must be UTC: the end of the
			// last date in the event's zone.
			rule += ";UNTIL=" + time.Date(u.Year(), u.Month(), u.Day(), 23, 59, 59, 0, eventZone(e.TimeZone)).UTC().Format(icalUTC)
		}
		lines = append(lines, rule)
	}
	for _, start := range e.ExcludedStarts {
		lines = append(lines, icalTime("EXDATE", e, start))
	}
	return append(lines, "END:VEVENT")
}

// icalTime is the property name for t in e's form: a date for an all-day
// event, wall-clock time with a TZID for a timed one in a known zone, else
// UTC. No VTIMEZONE is written: Apple Calendar, Google Calendar and
// Thunderbird resolve an IANA TZID themselves.
func icalTime(name string, e Event, t time.Time) string {
	switch {
	case e.AllDay:
		return name + ";VALUE=DATE:" + t.UTC().Format(icalDate)
	case e.TimeZone != "" && isIANAZone(e.TimeZone):
		return name + ";TZID=" + e.TimeZone + ":" + t.In(eventZone(e.TimeZone)).Format(icalLocal)
	default:
		return name + ":" + t.UTC().Format(icalUTC)
	}
}

// parseICal reads the VEVENTs of the iCalendar on r. Components nested in a
// VEVENT, a VALARM say, and everything outside one but X-WR-TIMEZONE are
// ignored.
func parseICal(r io.Reader) ([]icalEvent, error) {
	var stack []string
	var raws []map[string][]icalProperty
	calendarZone := ""
	seen := false
	handle := func(line string) {
		name, prop, ok := parseContentLine(line)
		switch {
		case !ok:
		case name == "BEGIN":
			component := strings.ToUpper(prop.value)
			stack = append(stack, component)
			seen = seen || component == "VCALENDAR"
			if component == "VEVENT" && len(stack) == 2 {
				raws = append(raws, map[string][]icalProperty{})
			}
		case name == "END":
			stack = stack[:max(len(stack)-1, 0)]
		case len(stack) == 2 && stack[1] == "VEVENT":
			raws[len(raws)-1][name] = append(raws[len(raws)-1][name], prop)
		case len(stack) == 1 && name == "X-WR-TIMEZONE":
			calendarZone = prop.value
		}
	}

	br := bufio.NewReader(r)
	var current strings.Builder
	for {
		line, err := br.ReadString('\n')
		line = strings.TrimRight(line, "\r\n")
		if line != "" && (line[0] == ' ' || line[0] == '\t') {
			current.WriteString(line[1:])
		} else {
			handle(current.String())
			current.Reset()
			current.WriteString(line)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("read iCalendar: %w", err)
		}
	}
	handle(current.String())
	if !seen {
		return nil, ErrInvalidICal
	}

	if !isIANAZone(calendarZone) {
		calendarZone = ""
	}
	events := make([]icalEvent, len(raws))
	masters := map[string]int{}
	for i, raw := range raws {
		events[i] = toICalEvent(raw, calendarZone)
		if events[i].recurrenceID == nil && events[i].uid != "" {
			masters[events[i].uid] = i
		}
	}
	// A modified occurrence replaces its start in the series.
	for _, e := range events {
		if i, ok := masters[e.uid]; ok && e.recurrenceID != nil {
			events[i].input.ExcludedStarts = append(events[i].input.ExcludedStarts, *e.recurrenceID)
		}
	}
	return events, nil
}

// parseContentLine splits NAME;PARAM=VALUE...:VALUE, where a parameter value
// may be double-quoted.
func parseContentLine(line string) (string, icalProperty, bool) {
	var fields []string
	quoted, from := false, 0
	for i := 0; i < len(line); i++ {
		switch c := line[i]; {
		case c == '"':
			quoted = !quoted
		case quoted:
		case c == ';':
			fields = append(fields, line[from:i])
			from = i + 1
		case c == ':':
			fields = append(fields, line[from:i])
			prop := icalProperty{params: map[string]string{}, value: line[i+1:]}
			for _, field := range fields[1:] {
				key, value, _ := strings.Cut(field, "=")
				prop.params[strings.ToUpper(key)] = strings.Trim(value, `"`)
			}
			return strings.ToUpper(fields[0]), prop, true
		}
	}
	return "", icalProperty{}, false
}

// toICalEvent reads one VEVENT's properties. calendarZone is X-WR-TIMEZONE,
// or empty, and places a floating time.
func toICalEvent(props map[string][]icalProperty, calendarZone string) icalEvent {
	first := func(name string) (icalProperty, bool) {
		if p := props[name]; len(p) > 0 {
			return p[0], true
		}
		return icalProperty{}, false
	}
	text := func(name string, limit int) string {
		p, _ := first(name)
		return truncateRunes(icalUntext.Replace(p.value), limit)
	}
	fallback := eventZone(calendarZone)
	uid, _ := first("UID")
	event := icalEvent{uid: uid.value}
	if p, ok := first("RECURRENCE-ID"); ok {
		if t, _, err := parseICalTime(p, fallback); err == nil {
			event.recurrenceID = &t
		}
	}
	dtstart, hasStart := first("DTSTART")
	status, _ := first("STATUS")
	if !hasStart || strings.EqualFold(status.value, "CANCELLED") {
		return event
	}
	start, allDay, err := parseICalTime(dtstart, fallback)
	if err != nil {
		return event
	}
	zoneName := calendarZone
	if tz := dtstart.params["TZID"]; tz != "" && isIANAZone(tz) {
		zoneName = tz
	}

	// An all-day event lasts a day unless it says otherwise; a timed one
	// with no length ends as it starts, which validate refuses.
	end := start
	if allDay {
		end = start.AddDate(0, 0, 1)
	}
	if p, ok := first("DTEND"); ok {
		if t, _, err := parseICalTime(p, fallback); err == nil {
			end = t
		}
	} else if p, ok := first("DURATION"); ok {
		if d, ok := parseICalDuration(p.value); ok {
			end = start.Add(d)
		}
	}

	input := EventInput{
		Title:    text("SUMMARY", MaxTitleLength),
		Notes:    text("DESCRIPTION", MaxNotesLength),
		Location: text("LOCATION", MaxLocationLength),
		Start:    start,
		End:      end,
		AllDay:   allDay,
		TimeZone: zoneName,
		Repeat:   RepeatNone,
	}
	if p, ok := first("RRULE"); ok && event.recurrenceID == nil {
		zone := eventZone(zoneName)
		firstStart := start.In(zone)
		if allDay {
			firstStart = time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, zone)
		}
		repeat, until, ok := parseRRule(p.value, firstStart)
		if !ok {
			return event
		}
		input.Repeat, input.RepeatUntil = repeat, until
	}
	for _, p := range props["EXDATE"] {
		for _, value := range strings.Split(p.value, ",") {
			if t, _, err := parseICalTime(icalProperty{params: p.params, value: value}, fallback); err == nil {
				input.ExcludedStarts = append(input.ExcludedStarts, t)
			}
		}
	}
	event.input, event.ok = input, true
	return event
}

// parseICalTime reads a DATE or DATE-TIME value. A date is its midnight UTC
// and true; a time ending in Z is UTC; one with a TZID the zone database
// knows is in that zone; anything else is in fallback.
func parseICalTime(p icalProperty, fallback *time.Location) (time.Time, bool, error) {
	value := strings.TrimSpace(p.value)
	if strings.EqualFold(p.params["VALUE"], "DATE") || len(value) == len(icalDate) {
		t, err := time.Parse(icalDate, value)
		return t, true, err
	}
	if strings.HasSuffix(value, "Z") {
		t, err := time.Parse(icalUTC, value)
		return t, false, err
	}
	zone := fallback
	if tz := p.params["TZID"]; tz != "" && isIANAZone(tz) {
		zone = eventZone(tz)
	}
	t, err := time.ParseInLocation(icalLocal, value, zone)
	return t.UTC(), false, err
}

// parseICalDuration reads a positive DURATION: P[n]W, P[n]D and T[n]H[n]M[n]S.
func parseICalDuration(value string) (time.Duration, bool) {
	rest, ok := strings.CutPrefix(strings.TrimPrefix(strings.ToUpper(value), "+"), "P")
	if !ok || rest == "" {
		return 0, false
	}
	var d time.Duration
	n, digits, inTime := 0, false, false
	for i := 0; i < len(rest); i++ {
		c := rest[i]
		var unit time.Duration
		switch {
		case c >= '0' && c <= '9':
			n, digits = n*10+int(c-'0'), true
			continue
		case c == 'T':
			inTime = true
			continue
		case !inTime && c == 'W':
			unit = 7 * 24 * time.Hour
		case !inTime && c == 'D':
			unit = 24 * time.Hour
		case inTime && c == 'H':
			unit = time.Hour
		case inTime && c == 'M':
			unit = time.Minute
		case inTime && c == 'S':
			unit = time.Second
		default:
			return 0, false
		}
		if !digits {
			return 0, false
		}
		d += time.Duration(n) * unit
		n, digits = 0, false
	}
	return d, !digits && d > 0
}

// parseRRule maps an RRULE onto a preset, and its UNTIL or COUNT onto the
// last date, for the series whose first occurrence starts at first, in the
// event's zone. A rule the presets cannot express is false.
func parseRRule(rule string, first time.Time) (Repeat, *time.Time, bool) {
	parts := map[string]string{}
	for _, part := range strings.Split(strings.ToUpper(rule), ";") {
		key, value, _ := strings.Cut(part, "=")
		parts[key] = value
	}
	repeat := map[string]Repeat{"DAILY": RepeatDaily, "WEEKLY": RepeatWeekly, "MONTHLY": RepeatMonthly}[parts["FREQ"]]
	if repeat == "" {
		return "", nil, false
	}
	weekday := strings.ToUpper(first.Weekday().String()[:2])
	for key, value := range parts {
		switch {
		case key == "FREQ", key == "WKST", key == "UNTIL", key == "COUNT":
		case key == "INTERVAL" && value == "1":
		case key == "BYDAY" && repeat == RepeatWeekly && value == weekday:
		case key == "BYMONTHDAY" && repeat == RepeatMonthly && value == strconv.Itoa(first.Day()):
		default:
			return "", nil, false
		}
	}
	zone := first.Location()
	if value, ok := parts["UNTIL"]; ok {
		t, isDate, err := parseICalTime(icalProperty{value: value}, zone)
		if err != nil {
			return "", nil, false
		}
		if !isDate {
			t = calendarDate(t, zone)
		}
		return repeat, &t, true
	}
	if value, ok := parts["COUNT"]; ok {
		count, err := strconv.Atoi(value)
		if err != nil || count < 1 {
			return "", nil, false
		}
		if count > maxICalCount {
			return repeat, nil, true
		}
		// COUNT counts occurrences that exist: a monthly series skips a
		// month without its day.
		for k := 0; ; k++ {
			if start, exists := occurrenceStart(repeat, first, k); exists {
				if count--; count == 0 {
					last := calendarDate(start, zone)
					return repeat, &last, true
				}
			}
		}
	}
	return repeat, nil, true
}

// truncateRunes cuts s to at most limit runes.
func truncateRunes(s string, limit int) string {
	if runes := []rune(s); len(runes) > limit {
		return string(runes[:limit])
	}
	return s
}

// storeICalEvents stores the parsed events on the default calendar, skipping
// the ones parseICal or validate refused and any matching an existing event.
func storeICalEvents(ctx context.Context, q db.Querier, events []icalEvent, createdBy int64) (ImportICalResult, error) {
	var result ImportICalResult
	calendar, err := q.GetDefaultCalendar(ctx)
	if err != nil {
		return result, err
	}
	rows, err := q.ListCalendarEvents(ctx, calendar.ID)
	if err != nil {
		return result, err
	}
	type key struct {
		title, start, end string
		allDay            int64
	}
	existing := make(map[key]bool, len(rows))
	for _, row := range rows {
		existing[key{row.CalendarEvent.Title, row.CalendarEvent.StartsAt, row.CalendarEvent.EndsAt, row.CalendarEvent.AllDay}] = true
	}
	for _, event := range events {
		input, err := validate(event.input)
		if !event.ok || err != nil {
			result.Skipped++
			continue
		}
		insert := createParams(calendar.ID, input)
		if existing[key{insert.Title, insert.StartsAt, insert.EndsAt, insert.AllDay}] {
			result.Skipped++
			continue
		}
		if createdBy != 0 {
			insert.CreatedBy = sql.NullInt64{Int64: createdBy, Valid: true}
		}
		if _, err := q.CreateCalendarEvent(ctx, insert); err != nil {
			return result, err
		}
		// A file that repeats an event stores it once too.
		existing[key{insert.Title, insert.StartsAt, insert.EndsAt, insert.AllDay}] = true
		result.Imported++
	}
	return result, nil
}

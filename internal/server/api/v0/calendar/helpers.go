package v0_calendar

import (
	"database/sql"
	"encoding/json"
	"errors"
	"reflect"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/calendarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
)

// errEventNotFound is what a caller hears about an event that does not exist.
var errEventNotFound = errors.New("event not found")

// errBadID answers an id that is not a number.
var errBadID = errors.New("event id must be a number")

// eventID reads the :id path parameter.
func eventID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	return id, err == nil
}

// parseInstant reads an RFC 3339 time from a request, naming the field when it
// cannot.
func parseInstant(field, value string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return time.Time{}, errors.New(field + " must be an RFC 3339 time")
	}
	return t, nil
}

// bindError says why an event body could not be read (#2537): a field of the
// wrong JSON type is named with the type it needs, a missing start or end is
// reported as such, and anything else is a malformed body.
func bindError(err error) error {
	var typeErr *json.UnmarshalTypeError
	var missing validator.ValidationErrors
	switch {
	case errors.As(err, &typeErr) && typeErr.Field != "":
		return errors.New(typeErr.Field + " must be " + jsonKind(typeErr.Type))
	case errors.As(err, &missing):
		return errors.New("start and end are required")
	default:
		return errors.New("the body must be a JSON event")
	}
}

// jsonKind names, for a client, the JSON value a Go field of type t takes.
func jsonKind(t reflect.Type) string {
	switch t.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return "a whole number"
	case reflect.Bool:
		return "true or false"
	case reflect.String:
		return "a string"
	default:
		return "a " + t.Kind().String()
	}
}

// toInput converts a request body into the service's input.
func toInput(req eventRequest) (calendarutil.EventInput, error) {
	start, err := parseInstant("start", req.Start)
	if err != nil {
		return calendarutil.EventInput{}, err
	}
	end, err := parseInstant("end", req.End)
	if err != nil {
		return calendarutil.EventInput{}, err
	}
	return calendarutil.EventInput{
		Title:           req.Title,
		Notes:           req.Notes,
		Location:        req.Location,
		Start:           start,
		End:             end,
		AllDay:          req.AllDay,
		TimeZone:        req.TimeZone,
		Repeat:          calendarutil.Repeat(req.Repeat),
		ReminderMinutes: req.ReminderMinutes,
		ColorIndex:      req.ColorIndex,
	}, nil
}

// callerID is the signed-in account's id, or 0 when the request carries none.
func callerID(c *gin.Context) int64 {
	principal, _ := ctxutil.Get[accessutil.Principal](c, "principal")
	return principal.UserID
}

// toEventJSON converts a stored event for a response to account caller.
func toEventJSON(e calendarutil.Event, caller int64) EventJSON {
	return EventJSON{
		ID:              e.ID,
		CalendarID:      e.CalendarID,
		Title:           e.Title,
		Notes:           e.Notes,
		Location:        e.Location,
		Start:           e.Start.UTC().Format(time.RFC3339),
		End:             e.End.UTC().Format(time.RFC3339),
		AllDay:          e.AllDay,
		TimeZone:        e.TimeZone,
		Repeat:          string(e.Repeat),
		ReminderMinutes: e.ReminderMinutes,
		ColorIndex:      e.ColorIndex,
		Owner:           e.OwnerName,
		Mine:            e.OwnerID != 0 && e.OwnerID == caller,
		CreatedAt:       e.CreatedAt.UTC().Format(time.RFC3339),
		UpdatedAt:       e.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

// eventError maps a calendarutil error onto its status: 400 for a broken rule,
// 404 for a missing event, and 500 for anything else.
func eventError(err error) *serverutil.Response {
	switch {
	case errors.Is(err, calendarutil.ErrInvalidEvent):
		return serverutil.BadRequest(err)
	case errors.Is(err, sql.ErrNoRows):
		return serverutil.NotFound(errEventNotFound)
	default:
		return serverutil.InternalServerError(err)
	}
}

// publishChanged tells every open client that event id changed, so each
// fetches the range it shows again.
func publishChanged(deps deputil.Dependencies, id int64) {
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventCalendarChanged, Data: id})
	}
}

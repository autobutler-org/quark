-- name: GetDefaultCalendar :one
SELECT
    *
FROM
    calendars
WHERE
    is_default = 1
LIMIT
    1;

-- name: CreateCalendarEvent :one
INSERT INTO
    calendar_events (
        calendar_id,
        title,
        notes,
        location,
        starts_at,
        ends_at,
        all_day,
        time_zone,
        repeat,
        reminder_minutes,
        color_index
    )
VALUES
    (
        sqlc.arg(calendar_id),
        sqlc.arg(title),
        sqlc.arg(notes),
        sqlc.arg(location),
        sqlc.arg(starts_at),
        sqlc.arg(ends_at),
        sqlc.arg(all_day),
        sqlc.arg(time_zone),
        sqlc.arg(repeat),
        sqlc.arg(reminder_minutes),
        sqlc.arg(color_index)
    )
RETURNING *;

-- name: GetCalendarEvent :one
SELECT
    *
FROM
    calendar_events
WHERE
    id = sqlc.arg(id)
LIMIT
    1;

-- A one-off event is listed when it overlaps [range_start, range_end). A
-- repeating event is listed when its series starts before range_end, since any
-- of its occurrences may fall in the range; the app expands them.
-- name: ListCalendarEventsInRange :many
SELECT
    *
FROM
    calendar_events
WHERE
    calendar_id = sqlc.arg(calendar_id)
    AND starts_at < sqlc.arg(range_end)
    AND (
        repeat != 'none'
        OR ends_at > sqlc.arg(range_start)
    )
ORDER BY
    starts_at,
    id;

-- name: UpdateCalendarEvent :one
UPDATE calendar_events
SET
    title = sqlc.arg(title),
    notes = sqlc.arg(notes),
    location = sqlc.arg(location),
    starts_at = sqlc.arg(starts_at),
    ends_at = sqlc.arg(ends_at),
    all_day = sqlc.arg(all_day),
    time_zone = sqlc.arg(time_zone),
    repeat = sqlc.arg(repeat),
    reminder_minutes = sqlc.arg(reminder_minutes),
    color_index = sqlc.arg(color_index),
    updated_at = datetime('now')
WHERE
    id = sqlc.arg(id)
RETURNING *;

-- name: DeleteCalendarEvent :execrows
DELETE FROM calendar_events
WHERE
    id = sqlc.arg(id);

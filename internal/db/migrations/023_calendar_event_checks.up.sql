-- An event's color and reminder are bounded in the schema as well as by
-- calendarutil (#2536), so a write that skips the app cannot store one the
-- app would refuse. color_index picks one of six colors. reminder_minutes
-- counts back from the start, at most a week; a timed event's cannot fall
-- after its start, and an all-day event's can fall on its own day, so as late
-- as one minute before the next midnight. Both must be whole numbers.
--
-- SQLite cannot add a CHECK to an existing table, so the table is rebuilt.
-- Rows already out of range are clamped to the nearest value the app allows
-- rather than refused: refusing would fail the migration and leave every
-- such device's database dirty. A fraction is truncated first, and since min
-- and max of NULL are NULL, no reminder stays no reminder.
CREATE TABLE calendar_events_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    calendar_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    location TEXT NOT NULL DEFAULT '',
    starts_at TEXT NOT NULL,
    ends_at TEXT NOT NULL,
    all_day INTEGER NOT NULL DEFAULT 0 CHECK (all_day IN (0, 1)),
    time_zone TEXT NOT NULL DEFAULT '',
    repeat TEXT NOT NULL DEFAULT 'none' CHECK (repeat IN ('none', 'daily', 'weekly', 'monthly')),
    reminder_minutes INTEGER,
    color_index INTEGER NOT NULL DEFAULT 0 CHECK (color_index IN (0, 1, 2, 3, 4, 5)),
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at DATETIME NOT NULL DEFAULT (datetime('now')),
    created_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (calendar_id) REFERENCES calendars (id) ON DELETE CASCADE,
    CHECK (
        reminder_minutes IS NULL
        OR (
            typeof(reminder_minutes) = 'integer'
            AND reminder_minutes BETWEEN CASE all_day
                WHEN 1 THEN -1439
                ELSE 0
            END AND 10080
        )
    )
);

INSERT INTO
    calendar_events_new (
        id,
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
        color_index,
        created_at,
        updated_at,
        created_by
    )
SELECT
    id,
    calendar_id,
    title,
    notes,
    location,
    starts_at,
    ends_at,
    all_day,
    time_zone,
    repeat,
    max(
        CASE all_day
            WHEN 1 THEN -1439
            ELSE 0
        END,
        min(10080, CAST(reminder_minutes AS INTEGER))
    ),
    max(0, min(5, CAST(color_index AS INTEGER))),
    created_at,
    updated_at,
    created_by
FROM
    calendar_events;

DROP TABLE calendar_events;

ALTER TABLE calendar_events_new
RENAME TO calendar_events;

CREATE INDEX idx_calendar_events_start ON calendar_events (calendar_id, starts_at);

CREATE INDEX idx_calendar_events_created_by ON calendar_events (created_by);

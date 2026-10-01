-- The household calendar (#1144). One default calendar, Personal, holds every
-- event, and every signed-in account reads and writes it: there is no owner
-- column until calendar ownership is decided.
--
-- Times are stored as UTC text. A timed event's starts_at and ends_at are
-- instants. An all-day event's are dates at midnight UTC that stand for the
-- calendar date itself, wherever it is read: 2026-09-29T00:00:00Z is "the 29th"
-- in every time zone. ends_at is exclusive, so a one-day all-day event ends at
-- the next midnight.
--
-- A repeating event is one row: repeat names the preset, and the app expands
-- occurrences from starts_at in the viewer's local time. reminder_minutes
-- counts back from the start; NULL is no reminder. For an all-day event it
-- counts back from midnight, so it can be negative: -540 is 9 AM on the day.
CREATE TABLE calendars (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
    created_at DATETIME NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX idx_calendars_default ON calendars (is_default)
WHERE
    is_default = 1;

INSERT INTO
    calendars (name, is_default)
VALUES
    ('Personal', 1);

CREATE TABLE calendar_events (
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
    color_index INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at DATETIME NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (calendar_id) REFERENCES calendars (id) ON DELETE CASCADE
);

CREATE INDEX idx_calendar_events_start ON calendar_events (calendar_id, starts_at);

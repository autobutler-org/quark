-- SQLite cannot DROP COLUMN a column carrying a foreign key, and nothing
-- references calendar_events, so the table is rebuilt as 021 made it, keeping
-- every row.
CREATE TABLE calendar_events_old (
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

INSERT INTO
    calendar_events_old (
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
        updated_at
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
    reminder_minutes,
    color_index,
    created_at,
    updated_at
FROM
    calendar_events;

DROP TABLE calendar_events;

ALTER TABLE calendar_events_old
RENAME TO calendar_events;

CREATE INDEX idx_calendar_events_start ON calendar_events (calendar_id, starts_at);

-- SQLite cannot drop a CHECK, so the table is rebuilt as 022 left it, keeping
-- every row and both indexes.
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
    created_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
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
    reminder_minutes,
    color_index,
    created_at,
    updated_at,
    created_by
FROM
    calendar_events;

DROP TABLE calendar_events;

ALTER TABLE calendar_events_old
RENAME TO calendar_events;

CREATE INDEX idx_calendar_events_start ON calendar_events (calendar_id, starts_at);

CREATE INDEX idx_calendar_events_created_by ON calendar_events (created_by);

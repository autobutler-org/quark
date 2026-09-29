-- A calendar event records the account that created it (#2544), so the
-- calendar can be narrowed to one person's events. It is a filter, not
-- privacy: every account still sees and edits every event.
--
-- Events created before this have no owner, nor do the events of a deleted
-- account. SQLite only lets ADD COLUMN add a foreign key whose default is
-- NULL, so the column stays nullable.
ALTER TABLE calendar_events
ADD COLUMN created_by INTEGER REFERENCES users (id) ON DELETE SET NULL;

CREATE INDEX idx_calendar_events_created_by ON calendar_events (created_by);

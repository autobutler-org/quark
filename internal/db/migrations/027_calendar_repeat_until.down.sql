-- Every series repeats forever again: the end dates are dropped.
ALTER TABLE calendar_events
DROP COLUMN repeat_until;

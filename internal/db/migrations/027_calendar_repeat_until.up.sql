-- A repeating event can end (#2524). repeat_until is the last date an
-- occurrence may start on, inclusive, stored like an all-day date: midnight
-- UTC standing for that calendar date wherever it is read. NULL repeats
-- forever, which is every series from before this. A one-off event has
-- nothing to end, so it never carries one.
--
-- The CHECK belongs to the column, so 027's down can still DROP COLUMN it;
-- 025's CHECKs stay where they are.
ALTER TABLE calendar_events
ADD COLUMN repeat_until TEXT CHECK (
    repeat_until IS NULL
    OR (
        repeat != 'none'
        AND repeat_until GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T00:00:00Z'
    )
);

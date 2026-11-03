-- SQLite's 044 makes its column defaults stamp milliseconds (#3170); a
-- TIMESTAMPTZ default here already keeps microseconds, so no column changes.
--
-- strftime('%Y-%m-%d %H:%M:%f', 'now'): the database's clock, named after the
-- SQLite call the shared queries use to stamp a row (rule 16 in
-- sql/queries/AGENTS.md). Used by every query in sql/queries that sets a
-- timestamp column to the current time. Only that format and the base 'now'
-- are supported; anything else raises rather than returning a time formatted
-- some other way.
CREATE FUNCTION strftime (format TEXT, base TEXT) RETURNS TIMESTAMPTZ
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF format <> '%Y-%m-%d %H:%M:%f' OR base <> 'now' THEN
        RAISE EXCEPTION 'strftime(): only (''%%Y-%%m-%%d %%H:%%M:%%f'', ''now'') is supported, got (%, %)', format, base;
    END IF;
    RETURN CURRENT_TIMESTAMP;
END;
$$;

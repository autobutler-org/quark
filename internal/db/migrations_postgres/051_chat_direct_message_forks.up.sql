-- Adding someone to a direct message opens a new one with the bigger set
-- (#2423), and the new one says so in a line at its start. forked marks a
-- direct message opened that way: 1 when its opener started it from a direct
-- message they were in, whose people it all keeps. Which one it came from
-- isn't kept.
ALTER TABLE chat_channels ADD COLUMN forked BIGINT NOT NULL DEFAULT 0;

-- The PostgreSQL half of 053_chat_anonymous_channels: anonymous channels and
-- the per-channel pseudonyms their members are shown under (#2949).
ALTER TABLE chat_channels ADD COLUMN anonymous BIGINT NOT NULL DEFAULT 0;

CREATE TABLE chat_channel_pseudonyms (
    channel_id   BIGINT NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    pseudonym_id BIGINT NOT NULL CHECK (pseudonym_id < 0),
    alias        TEXT NOT NULL,
    PRIMARY KEY (channel_id, user_id),
    UNIQUE (channel_id, pseudonym_id)
);

-- SQLite's UNIQUE (channel_id, alias COLLATE NOCASE).
CREATE UNIQUE INDEX idx_chat_channel_pseudonyms_alias ON chat_channel_pseudonyms (channel_id, LOWER(alias));

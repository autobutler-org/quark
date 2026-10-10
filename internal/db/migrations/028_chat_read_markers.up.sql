-- Chat read markers (#2424): how far each account has read in each channel.
-- The Quark counts what is unread from message ids alone, never from content,
-- which it can't open. A marker goes with its account and with its channel.
CREATE TABLE chat_read_markers (
    user_id              INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    channel_id           INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    last_read_message_id INTEGER NOT NULL,
    PRIMARY KEY (user_id, channel_id)
);

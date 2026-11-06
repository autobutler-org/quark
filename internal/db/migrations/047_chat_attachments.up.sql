-- attach_files (128) joins the Member preset. Every row that can already
-- send (send_messages is 2) gains it and keeps matching its preset.
UPDATE chat_channel_members SET permissions = permissions | 128 WHERE permissions & 2 = 2;

-- Ciphertext for a chat attachment (#2425). The name, media type and key
-- stay inside the message. message_id is null until a later change binds
-- the file to a message. id is 64 hex characters, chosen by the client.
CREATE TABLE chat_attachments (
    id TEXT PRIMARY KEY,
    channel_id INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    message_id INTEGER REFERENCES chat_messages (id) ON DELETE CASCADE,
    uploader_id INTEGER NOT NULL REFERENCES users (id),
    byte_size INTEGER NOT NULL,
    created_at DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now'))
);

CREATE INDEX idx_chat_attachments_channel ON chat_attachments (channel_id);
CREATE INDEX idx_chat_attachments_message ON chat_attachments (message_id);

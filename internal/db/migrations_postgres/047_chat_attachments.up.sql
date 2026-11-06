-- Chat attachments (#2425), the PostgreSQL half of 047_chat_attachments.
-- Column order, nullability and types follow internal/db/AGENTS.md so sqlc
-- generates the same Go types as the SQLite table. BYTEA is not used: the
-- ciphertext lives on disk, and this row only names it.

-- attach_files (128) joins the Member preset. Every row that can already
-- send (send_messages is 2) gains it and keeps matching its preset.
UPDATE chat_channel_members SET permissions = permissions | 128 WHERE permissions & 2 = 2;

CREATE TABLE chat_attachments (
    id TEXT PRIMARY KEY,
    channel_id BIGINT NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    message_id BIGINT REFERENCES chat_messages (id) ON DELETE CASCADE,
    uploader_id BIGINT NOT NULL REFERENCES users (id),
    byte_size BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_chat_attachments_channel ON chat_attachments (channel_id);
CREATE INDEX idx_chat_attachments_message ON chat_attachments (message_id);

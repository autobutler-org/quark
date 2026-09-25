-- Chat messages (#2418). The body is encrypted on the client under the
-- channel's key (017) before it is sent, so everything here but who sent what
-- when is ciphertext. ciphertext is nonce || XChaCha20-Poly1305 output; it is
-- NULL once the message is deleted, which keeps the row as a tombstone so ids
-- stay contiguous for paging.
--
-- The foreign key to chat_channel_keys makes an unknown key version
-- impossible, and deleting a channel takes its messages with it.
CREATE TABLE chat_messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id  INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    author_id   INTEGER REFERENCES users (id) ON DELETE SET NULL,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB,
    created_at  DATETIME NOT NULL DEFAULT (datetime('now')),
    edited_at   DATETIME,
    deleted_at  DATETIME,
    FOREIGN KEY (channel_id, key_version) REFERENCES chat_channel_keys (channel_id, version) ON DELETE CASCADE,
    CHECK ((ciphertext IS NULL) = (deleted_at IS NOT NULL))
);

CREATE INDEX idx_chat_messages_channel ON chat_messages (channel_id, id);

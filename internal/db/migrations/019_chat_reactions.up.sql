-- Chat reactions (#2426). Like a message, a reaction is encrypted on the
-- client under the channel's key, so the Quark knows who reacted to which
-- message and when, never with what. ciphertext is nonce ||
-- XChaCha20-Poly1305 output under the channel key of key_version.
--
-- A reaction goes with its message, and with the account that made it.
CREATE TABLE chat_reactions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id  INTEGER NOT NULL REFERENCES chat_messages (id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_chat_reactions_message ON chat_reactions (message_id, user_id);

-- A deleted message's reactions go with its ciphertext, in the statement that
-- tombstones it.
CREATE TRIGGER chat_reactions_tombstone
AFTER UPDATE OF deleted_at ON chat_messages
WHEN NEW.deleted_at IS NOT NULL
BEGIN
    DELETE FROM chat_reactions WHERE message_id = NEW.id;
END;

-- manage_reactions (64) removes other people's reactions. It joins the
-- Moderator and Owner presets, so every row holding delete_messages (8),
-- which already removes a whole message and its reactions, gains it and keeps
-- matching its preset.
UPDATE chat_channel_members SET permissions = permissions | 64 WHERE permissions & 8 = 8;

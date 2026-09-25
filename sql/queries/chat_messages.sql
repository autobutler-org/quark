-- Chat messages (#2418). The Quark stores ciphertext and never opens it.

-- name: CreateChatMessage :one
INSERT INTO chat_messages (channel_id, author_id, key_version, ciphertext)
VALUES (?, ?, ?, ?)
RETURNING *;

-- ListChatMessagesBefore pages a channel backward from an id, newest first.
-- name: ListChatMessagesBefore :many
SELECT * FROM chat_messages WHERE channel_id = ? AND id < ? ORDER BY id DESC LIMIT ?;

-- ListChatMessagesAfter pages a channel forward from an id, oldest first.
-- name: ListChatMessagesAfter :many
SELECT * FROM chat_messages WHERE channel_id = ? AND id > ? ORDER BY id LIMIT ?;

-- name: GetChatMessage :one
SELECT * FROM chat_messages WHERE id = ?;

-- TombstoneChatMessage wipes a message's ciphertext and marks it deleted,
-- keeping the first deletion time when it is deleted twice.
-- name: TombstoneChatMessage :one
UPDATE chat_messages
SET ciphertext = NULL, deleted_at = COALESCE(deleted_at, datetime('now'))
WHERE id = ?
RETURNING *;

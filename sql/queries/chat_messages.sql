-- Chat messages (#2418). The Quark stores ciphertext and never opens it.

-- CreateChatMessage stores a message. nonce is the ciphertext's first 24
-- bytes, unique per channel and key version (#2487). client_message_id, when
-- the client sent one, is unique per channel and author (#3531). root_id is set
-- on a side conversation's reply (#4345).
-- name: CreateChatMessage :one
INSERT INTO chat_messages (channel_id, author_id, key_version, ciphertext, nonce, client_message_id, root_id)
VALUES (sqlc.arg(channel_id), sqlc.arg(author_id), sqlc.arg(key_version), sqlc.arg(ciphertext), sqlc.arg(nonce), sqlc.arg(client_message_id), sqlc.arg(root_id))
RETURNING *;

-- GetChatMessageByClientID finds the message an author already sent to a
-- channel under a client message id.
-- name: GetChatMessageByClientID :one
SELECT * FROM chat_messages WHERE channel_id = sqlc.arg(channel_id) AND author_id = sqlc.arg(author_id) AND client_message_id = sqlc.arg(client_message_id);

-- GetChatMessageByNonce finds the message a post's nonce already names.
-- name: GetChatMessageByNonce :one
SELECT * FROM chat_messages WHERE channel_id = sqlc.arg(channel_id) AND key_version = sqlc.arg(key_version) AND nonce = sqlc.arg(nonce);

-- ListChatMessagesBefore pages a channel backward from an id, newest first.
-- A side conversation's replies are left out (#4345).
-- name: ListChatMessagesBefore :many
SELECT * FROM chat_messages WHERE channel_id = sqlc.arg(channel_id) AND root_id IS NULL AND id < sqlc.arg(id) ORDER BY id DESC LIMIT CAST(sqlc.arg('limit') AS BIGINT);

-- ListChatMessagesAfter pages a channel forward from an id, oldest first.
-- A side conversation's replies are left out (#4345).
-- name: ListChatMessagesAfter :many
SELECT * FROM chat_messages WHERE channel_id = sqlc.arg(channel_id) AND root_id IS NULL AND id > sqlc.arg(id) ORDER BY id LIMIT CAST(sqlc.arg('limit') AS BIGINT);

-- ListChatRepliesBefore pages a side conversation backward from an id,
-- newest first (#4345).
-- name: ListChatRepliesBefore :many
SELECT * FROM chat_messages WHERE root_id = sqlc.arg(root_id) AND id < sqlc.arg(id) ORDER BY id DESC LIMIT CAST(sqlc.arg('limit') AS BIGINT);

-- ListChatRepliesAfter pages a side conversation forward from an id, oldest
-- first (#4345).
-- name: ListChatRepliesAfter :many
SELECT * FROM chat_messages WHERE root_id = sqlc.arg(root_id) AND id > sqlc.arg(id) ORDER BY id LIMIT CAST(sqlc.arg('limit') AS BIGINT);

-- name: GetChatMessage :one
SELECT * FROM chat_messages WHERE id = sqlc.arg(id);

-- TombstoneChatMessage wipes a message's ciphertext and marks it deleted,
-- keeping the first deletion time when it is deleted twice.
-- name: TombstoneChatMessage :one
UPDATE chat_messages
SET ciphertext = NULL, deleted_at = COALESCE(deleted_at, strftime('%Y-%m-%d %H:%M:%f', 'now'))
WHERE id = sqlc.arg(id)
RETURNING *;

-- EditChatMessage replaces a live message's ciphertext with its author's new
-- one and stamps edited_at (#2426). nonce follows the new ciphertext, so the
-- unique index keeps refusing a replay of what the message says now. A
-- deleted message matches nothing.
-- name: EditChatMessage :one
UPDATE chat_messages
SET ciphertext = sqlc.arg(ciphertext), key_version = sqlc.arg(key_version), nonce = sqlc.arg(nonce),
    edited_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE id = sqlc.arg(id) AND deleted_at IS NULL
RETURNING *;

-- Chat reactions (#2426). The Quark stores ciphertext and never opens it.

-- CreateChatReaction stores a reaction on a message that isn't deleted, and
-- returns no row when it is, so a reaction can't slip in after the tombstone.
-- name: CreateChatReaction :one
INSERT INTO chat_reactions (message_id, user_id, key_version, ciphertext)
SELECT id, sqlc.arg(user_id), sqlc.arg(key_version), sqlc.arg(ciphertext)
FROM chat_messages
WHERE chat_messages.id = sqlc.arg(message_id) AND deleted_at IS NULL
RETURNING *;

-- name: GetChatReaction :one
SELECT * FROM chat_reactions WHERE id = ?;

-- name: DeleteChatReaction :exec
DELETE FROM chat_reactions WHERE id = ?;

-- CountUserChatReactions is how many reactions one account has on a message.
-- name: CountUserChatReactions :one
SELECT COUNT(*) FROM chat_reactions WHERE message_id = ? AND user_id = ?;

-- ListChatReactionsBetween is the reactions on a channel's messages whose ids
-- fall in [first_id, last_id], one page of ListChatMessages*.
-- name: ListChatReactionsBetween :many
SELECT chat_reactions.*
FROM chat_reactions
JOIN chat_messages ON chat_messages.id = chat_reactions.message_id
WHERE chat_messages.channel_id = sqlc.arg(channel_id)
  AND chat_reactions.message_id >= sqlc.arg(first_id)
  AND chat_reactions.message_id <= sqlc.arg(last_id)
ORDER BY chat_reactions.id;

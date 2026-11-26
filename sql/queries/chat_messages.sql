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

-- ListChatBranchSummariesBetween counts the live replies of each channel
-- message whose id falls in [first_id, last_id], one page of
-- ListChatMessages*, with when the newest of them arrived (#4346), sorted by root. A message
-- with no live reply has no row. It reads the (root_id, id) index. For
-- user_id it also counts the live replies after that account's marker in the
-- branch that someone else wrote, and says whether the account is involved:
-- it wrote the root or has a live reply there (#4349).
-- name: ListChatBranchSummariesBetween :many
SELECT
    summary.root_id,
    summary.reply_count,
    newest.created_at AS last_reply_at,
    summary.unread_count,
    CAST(COALESCE(root.author_id, 0) = CAST(sqlc.arg(user_id) AS BIGINT) OR summary.mine > 0 AS BOOLEAN) AS involved
FROM (
    SELECT
        CAST(reply.root_id AS BIGINT) AS root_id,
        COUNT(*) AS reply_count,
        MAX(reply.id) AS newest_id,
        COUNT(CASE WHEN reply.id > COALESCE(marker.last_read_message_id, 0)
            AND COALESCE(reply.author_id, 0) <> sqlc.arg(user_id) THEN 1 END) AS unread_count,
        COUNT(CASE WHEN reply.author_id = sqlc.arg(user_id) THEN 1 END) AS mine
    FROM chat_messages AS reply
    LEFT JOIN chat_branch_read_markers AS marker ON marker.root_id = reply.root_id
        AND marker.user_id = sqlc.arg(user_id)
    WHERE reply.channel_id = sqlc.arg(channel_id)
      AND reply.root_id >= CAST(sqlc.arg(first_id) AS BIGINT)
      AND reply.root_id <= CAST(sqlc.arg(last_id) AS BIGINT)
      AND reply.deleted_at IS NULL
    GROUP BY reply.root_id
) AS summary
JOIN chat_messages AS newest ON newest.id = summary.newest_id
JOIN chat_messages AS root ON root.id = summary.root_id
ORDER BY summary.root_id;

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

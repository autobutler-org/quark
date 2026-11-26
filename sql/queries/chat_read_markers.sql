-- Chat read markers (#2424): how far each account has read in each channel.

-- SetChatReadMarker moves an account's marker in a channel forward, never
-- backward: it changes no row when the marker is already at or past the id.
-- name: SetChatReadMarker :execrows
INSERT INTO chat_read_markers (user_id, channel_id, last_read_message_id)
VALUES (sqlc.arg(user_id), sqlc.arg(channel_id), sqlc.arg(last_read_message_id))
ON CONFLICT (user_id, channel_id) DO UPDATE
SET last_read_message_id = excluded.last_read_message_id
WHERE excluded.last_read_message_id > chat_read_markers.last_read_message_id;

-- name: GetChatReadMarker :one
SELECT last_read_message_id FROM chat_read_markers WHERE user_id = sqlc.arg(user_id) AND channel_id = sqlc.arg(channel_id);

-- CountChatUnreadForUser counts, per channel, the messages after an account's
-- marker that someone else wrote and that are not deleted. A side
-- conversation's replies are not counted (#4345). A channel with
-- none has no row. It counts every channel, whatever the account may read
-- there; chatutil keeps only the counts of channels it reads.
-- ponytail: a channel never opened counts its whole history on every list.
-- Cap the count or cache it if a long channel ever makes the list slow.
-- name: CountChatUnreadForUser :many
SELECT
    chat_messages.channel_id,
    COUNT(*) AS unread
FROM
    chat_messages
    LEFT JOIN chat_read_markers ON chat_read_markers.channel_id = chat_messages.channel_id
    AND chat_read_markers.user_id = sqlc.arg(user_id)
WHERE
    chat_messages.id > COALESCE(chat_read_markers.last_read_message_id, 0)
    AND chat_messages.deleted_at IS NULL
    AND chat_messages.root_id IS NULL
    AND COALESCE(chat_messages.author_id, 0) <> sqlc.arg(user_id)
GROUP BY
    chat_messages.channel_id;

-- SetChatBranchReadMarker moves an account's marker in a side conversation
-- (#4349), named by its root, forward, never backward, as SetChatReadMarker
-- does for a channel.
-- name: SetChatBranchReadMarker :execrows
INSERT INTO chat_branch_read_markers (user_id, root_id, last_read_message_id)
VALUES (sqlc.arg(user_id), sqlc.arg(root_id), sqlc.arg(last_read_message_id))
ON CONFLICT (user_id, root_id) DO UPDATE
SET last_read_message_id = excluded.last_read_message_id
WHERE excluded.last_read_message_id > chat_branch_read_markers.last_read_message_id;

-- name: GetChatBranchReadMarker :one
SELECT last_read_message_id FROM chat_branch_read_markers WHERE user_id = sqlc.arg(user_id) AND root_id = sqlc.arg(root_id);

-- CountChatBranchUnreadForUser counts, per channel, the side-conversation
-- replies after an account's marker in their branch that someone else wrote
-- and that are not deleted (#4349), split by whether the account is involved
-- in the branch: it wrote the root or has a live reply there. A channel with
-- none has no row. Like CountChatUnreadForUser it counts every channel, and
-- chatutil keeps only the ones the account reads.
-- ponytail: it reads every live reply on every list. Keep a per-branch count
-- if a busy Quark ever makes the list slow.
-- name: CountChatBranchUnreadForUser :many
SELECT
    branch.channel_id,
    CAST(SUM(CASE WHEN COALESCE(root.author_id, 0) = CAST(sqlc.arg(user_id) AS BIGINT) OR branch.mine > 0 THEN branch.unread ELSE 0 END) AS BIGINT) AS involved_unread,
    CAST(SUM(CASE WHEN COALESCE(root.author_id, 0) = CAST(sqlc.arg(user_id) AS BIGINT) OR branch.mine > 0 THEN 0 ELSE branch.unread END) AS BIGINT) AS other_unread
FROM (
    SELECT
        reply.channel_id,
        reply.root_id,
        COUNT(CASE WHEN reply.id > COALESCE(marker.last_read_message_id, 0)
            AND COALESCE(reply.author_id, 0) <> sqlc.arg(user_id) THEN 1 END) AS unread,
        COUNT(CASE WHEN reply.author_id = sqlc.arg(user_id) THEN 1 END) AS mine
    FROM
        chat_messages AS reply
        LEFT JOIN chat_branch_read_markers AS marker ON marker.root_id = reply.root_id
        AND marker.user_id = sqlc.arg(user_id)
    WHERE
        reply.root_id IS NOT NULL
        AND reply.deleted_at IS NULL
    GROUP BY
        reply.channel_id, reply.root_id
) AS branch
JOIN chat_messages AS root ON root.id = branch.root_id
WHERE
    branch.unread > 0
GROUP BY
    branch.channel_id;

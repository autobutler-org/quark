-- Chat read markers (#2424): how far each account has read in each channel.

-- SetChatReadMarker moves an account's marker in a channel forward, never
-- backward: it changes no row when the marker is already at or past the id.
-- name: SetChatReadMarker :execrows
INSERT INTO chat_read_markers (user_id, channel_id, last_read_message_id)
VALUES (?, ?, ?)
ON CONFLICT (user_id, channel_id) DO UPDATE
SET last_read_message_id = excluded.last_read_message_id
WHERE excluded.last_read_message_id > chat_read_markers.last_read_message_id;

-- name: GetChatReadMarker :one
SELECT last_read_message_id FROM chat_read_markers WHERE user_id = ? AND channel_id = ?;

-- CountChatUnreadForUser counts, per channel, the messages after an account's
-- marker that someone else wrote and that are not deleted. A channel with
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
    AND COALESCE(chat_messages.author_id, 0) <> sqlc.arg(user_id)
GROUP BY
    chat_messages.channel_id;

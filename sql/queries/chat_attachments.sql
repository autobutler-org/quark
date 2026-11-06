-- Chat attachments (#2425). The ciphertext is a file in the data directory.
-- These rows name it. message_id stays null until a later change binds the
-- file to a message.

-- CreateChatAttachment stores one. created_at is the database clock, at
-- millisecond resolution (rule 3). The caller has already checked id.
-- name: CreateChatAttachment :one
INSERT INTO chat_attachments (id, channel_id, uploader_id, byte_size, created_at)
VALUES (
    sqlc.arg(id),
    sqlc.arg(channel_id),
    sqlc.arg(uploader_id),
    sqlc.arg(byte_size),
    strftime('%Y-%m-%d %H:%M:%f', 'now')
)
RETURNING *;

-- name: GetChatAttachment :one
SELECT * FROM chat_attachments WHERE id = sqlc.arg(id);

-- ListChatAttachmentIDsByChannel is every attachment in one channel, so
-- deleting the channel can remove the files after the rows are gone.
-- name: ListChatAttachmentIDsByChannel :many
SELECT id FROM chat_attachments WHERE channel_id = sqlc.arg(channel_id) ORDER BY id;

-- ListUnboundChatAttachmentsBefore lists attachments no message claims that
-- were stored before created_at, so a sweep can remove their files and then
-- delete the rows. The cutoff is passed from Go.
-- name: ListUnboundChatAttachmentsBefore :many
SELECT id, channel_id
FROM chat_attachments
WHERE message_id IS NULL AND created_at < sqlc.arg(created_at)
ORDER BY id;

-- DeleteUnboundChatAttachmentsBefore drops those rows. The cutoff is the
-- same value the list used, passed from Go; this does not call datetime().
-- name: DeleteUnboundChatAttachmentsBefore :exec
DELETE FROM chat_attachments
WHERE message_id IS NULL AND created_at < sqlc.arg(created_at);

-- name: DeleteChatAttachment :exec
DELETE FROM chat_attachments WHERE id = sqlc.arg(id);

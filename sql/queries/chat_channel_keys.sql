-- Channel keys, key grants and channel events (#2417). The Quark stores sealed
-- keys and signatures it can't open or make; clients do the crypto.

-- name: ListChatChannelIDs :many
SELECT id FROM chat_channels ORDER BY id;

-- name: ListChatChannelKeys :many
SELECT * FROM chat_channel_keys WHERE channel_id = ? ORDER BY version;

-- name: CreateChatChannelKey :one
INSERT INTO chat_channel_keys (channel_id, version, created_by) VALUES (?, ?, ?) RETURNING *;

-- ListChatKeyGrantsForUser is one account's grants on a channel, every version.
-- name: ListChatKeyGrantsForUser :many
SELECT * FROM chat_key_grants WHERE channel_id = ? AND user_id = ? ORDER BY version;

-- ListChatKeyGrantRecipients is who holds which version of a channel's key. A
-- NULL user_id is a grant to an account since deleted.
-- name: ListChatKeyGrantRecipients :many
SELECT version, user_id FROM chat_key_grants WHERE channel_id = ? ORDER BY version, user_id;

-- InsertChatKeyGrant stores a grant unless the account already has one for
-- that version: the first grant wins.
-- name: InsertChatKeyGrant :exec
INSERT INTO chat_key_grants (
    channel_id, version, user_id, sealed_key, granted_by, granter_sign_key, signature
) VALUES (
    ?, ?, ?, ?, ?, ?, ?
) ON CONFLICT (channel_id, version, user_id) DO NOTHING;

-- name: GetChatKeyGrant :one
SELECT * FROM chat_key_grants WHERE channel_id = ? AND version = ? AND user_id = ?;

-- DeleteUserChatKeyGrants drops every grant sealed to an account, for when its
-- X25519 key changes and they can no longer be opened.
-- name: DeleteUserChatKeyGrants :exec
DELETE FROM chat_key_grants WHERE user_id = ?;

-- ListActiveUserChatPublicKeys is every active account's published keys.
-- name: ListActiveUserChatPublicKeys :many
SELECT
    user_chat_keys.user_id,
    user_chat_keys.box_public_key,
    user_chat_keys.sign_public_key
FROM
    user_chat_keys
    JOIN users ON users.id = user_chat_keys.user_id
WHERE
    users.status = 'active';

-- name: CreateChatChannelEvent :one
INSERT INTO chat_channel_events (channel_id, kind, actor_id, payload) VALUES (?, ?, ?, ?) RETURNING *;

-- ListChatChannelEvents pages a channel's events oldest first, after an id.
-- name: ListChatChannelEvents :many
SELECT * FROM chat_channel_events WHERE channel_id = ? AND id > ? ORDER BY id LIMIT ?;

-- name: GetChatChannelEvent :one
SELECT * FROM chat_channel_events WHERE id = ? AND channel_id = ?;

-- SignChatChannelEvent attaches the actor's signature to an event, once.
-- name: SignChatChannelEvent :execrows
UPDATE chat_channel_events
SET
    signature = ?,
    signer_sign_key = ?
WHERE
    id = ?
    AND channel_id = ?
    AND actor_id = ?
    AND signature IS NULL;

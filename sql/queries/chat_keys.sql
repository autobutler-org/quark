-- GetUserChatKeys returns an account's whole chat identity row, wrapped
-- private seeds included. Only the account itself may be served it (#2416).
-- name: GetUserChatKeys :one
SELECT
    *
FROM
    user_chat_keys
WHERE
    user_id = ?;

-- GetUserChatPublicKeys returns only the public half of an active account's
-- chat identity, which any signed-in account may read.
-- name: GetUserChatPublicKeys :one
SELECT
    user_chat_keys.user_id,
    user_chat_keys.box_public_key,
    user_chat_keys.sign_public_key
FROM
    user_chat_keys
    JOIN users ON users.id = user_chat_keys.user_id
WHERE
    user_chat_keys.user_id = ?
    AND users.status = 'active';

-- UpsertUserChatKeys creates or replaces an account's chat identity row.
-- created_at survives a replace, so it dates the account's first key.
-- name: UpsertUserChatKeys :one
INSERT INTO user_chat_keys (
    user_id,
    box_public_key,
    sign_public_key,
    wrapped_by_password,
    salt_pw,
    wrapped_by_phrase,
    salt_rp,
    kdf_params
) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?
)
ON CONFLICT (user_id) DO UPDATE SET
    box_public_key = excluded.box_public_key,
    sign_public_key = excluded.sign_public_key,
    wrapped_by_password = excluded.wrapped_by_password,
    salt_pw = excluded.salt_pw,
    wrapped_by_phrase = excluded.wrapped_by_phrase,
    salt_rp = excluded.salt_rp,
    kdf_params = excluded.kdf_params,
    updated_at = datetime('now')
RETURNING
    *;

-- DeleteUserChatKeys removes an account's chat identity. The foreign key
-- cascades too, but deletion says so rather than relying on the pragma.
-- name: DeleteUserChatKeys :exec
DELETE FROM user_chat_keys
WHERE
    user_id = ?;

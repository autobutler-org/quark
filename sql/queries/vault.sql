-- The per-account vault (#3458). Every query below takes the account's
-- user_id, so no call can reach another account's rows.

-- GetVaultKey returns an account's wrapped vault key. Only the account itself
-- may be served it.
-- name: GetVaultKey :one
SELECT
    *
FROM
    vault_keys
WHERE
    user_id = sqlc.arg(user_id);

-- CreateVaultKey stores an account's first vault key. A second create is a
-- unique violation rather than a replace, so a client can never overwrite the
-- key its items are encrypted under by setting the vault up again.
-- name: CreateVaultKey :one
INSERT INTO vault_keys (
    user_id,
    wrapped_by_password,
    salt_pw,
    wrapped_by_phrase,
    salt_rp,
    kdf_params
) VALUES (
    sqlc.arg(user_id), sqlc.arg(wrapped_by_password), sqlc.arg(salt_pw), sqlc.arg(wrapped_by_phrase), sqlc.arg(salt_rp), sqlc.arg(kdf_params)
)
RETURNING
    *;

-- UpdateVaultKey replaces the wraps of an account's existing vault key, for a
-- password change, a recovery or a new recovery phrase. The key inside them
-- is the same, so the items stay as they are. No row updated means the
-- account has no vault.
-- name: UpdateVaultKey :execrows
UPDATE vault_keys
SET
    wrapped_by_password = sqlc.arg(wrapped_by_password),
    salt_pw = sqlc.arg(salt_pw),
    wrapped_by_phrase = sqlc.arg(wrapped_by_phrase),
    salt_rp = sqlc.arg(salt_rp),
    kdf_params = sqlc.arg(kdf_params),
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE
    user_id = sqlc.arg(user_id);

-- DeleteVaultKey removes an account's vault key, which leaves its items
-- unreadable; DeleteVaultItems goes with it.
-- name: DeleteVaultKey :exec
DELETE FROM vault_keys
WHERE
    user_id = sqlc.arg(user_id);

-- ListVaultItems returns every item of an account, oldest first.
-- name: ListVaultItems :many
SELECT
    *
FROM
    vault_items
WHERE
    user_id = sqlc.arg(user_id)
ORDER BY
    id;

-- GetVaultItem returns one of an account's items. Another account's id finds
-- nothing.
-- name: GetVaultItem :one
SELECT
    *
FROM
    vault_items
WHERE
    id = sqlc.arg(id)
    AND user_id = sqlc.arg(user_id);

-- name: CreateVaultItem :one
INSERT INTO vault_items (
    user_id,
    ciphertext,
    nonce,
    format_version
) VALUES (
    sqlc.arg(user_id), sqlc.arg(ciphertext), sqlc.arg(nonce), sqlc.arg(format_version)
)
RETURNING
    *;

-- UpdateVaultItem replaces one of an account's items. Another account's id
-- updates nothing and returns no row.
-- name: UpdateVaultItem :one
UPDATE vault_items
SET
    ciphertext = sqlc.arg(ciphertext),
    nonce = sqlc.arg(nonce),
    format_version = sqlc.arg(format_version),
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE
    id = sqlc.arg(id)
    AND user_id = sqlc.arg(user_id)
RETURNING
    *;

-- DeleteVaultItem removes one of an account's items. Another account's id
-- deletes nothing.
-- name: DeleteVaultItem :execrows
DELETE FROM vault_items
WHERE
    id = sqlc.arg(id)
    AND user_id = sqlc.arg(user_id);

-- DeleteVaultItems removes every item of an account.
-- name: DeleteVaultItems :exec
DELETE FROM vault_items
WHERE
    user_id = sqlc.arg(user_id);

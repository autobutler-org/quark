-- name: CreateVaultConfig :exec
INSERT INTO vault_config (
    id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
    verification_blob, verification_nonce, auto_lock_seconds
) VALUES (1, ?, ?, ?, ?, ?, ?, ?);

-- name: GetVaultConfig :one
SELECT * FROM vault_config WHERE id = 1;

-- name: CreateVaultFolder :one
INSERT INTO vault_folders (name, parent_id, sort_order)
VALUES (?, ?, ?)
RETURNING *;

-- name: ListVaultFolders :many
SELECT * FROM vault_folders ORDER BY sort_order, name;

-- name: GetVaultFolder :one
SELECT * FROM vault_folders WHERE id = ?;

-- name: UpdateVaultFolder :exec
UPDATE vault_folders
SET name = ?, parent_id = ?, sort_order = ?
WHERE id = ?;

-- name: DeleteVaultFolder :exec
DELETE FROM vault_folders WHERE id = ?;

-- name: CreateVaultEntry :one
INSERT INTO vault_entries (name, url_host, folder_id, ciphertext, nonce)
VALUES (?, ?, ?, ?, ?)
RETURNING *;

-- name: GetVaultEntry :one
SELECT * FROM vault_entries WHERE id = ?;

-- name: ListVaultEntries :many
SELECT id, name, url_host, folder_id, created_at, updated_at
FROM vault_entries
ORDER BY name;

-- name: UpdateVaultEntry :exec
UPDATE vault_entries
SET name = ?, url_host = ?, folder_id = ?, ciphertext = ?, nonce = ?,
    updated_at = datetime('now')
WHERE id = ?;

-- name: DeleteVaultEntry :exec
DELETE FROM vault_entries WHERE id = ?;

-- name: ListVaultEntriesWithoutHost :many
SELECT id, ciphertext, nonce FROM vault_entries WHERE url_host = '';

-- name: UpdateVaultEntryHost :exec
UPDATE vault_entries SET url_host = ? WHERE id = ?;

-- name: ListAllVaultEntriesForReEncrypt :many
SELECT id, ciphertext, nonce FROM vault_entries;

-- name: UpdateVaultEntryCiphertext :exec
UPDATE vault_entries
SET ciphertext = ?, nonce = ?, updated_at = datetime('now')
WHERE id = ?;

-- name: UpdateVaultConfigPassword :exec
UPDATE vault_config
SET salt = ?, verification_blob = ?, verification_nonce = ?
WHERE id = 1;

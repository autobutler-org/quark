-- name: SetUserAdmin :exec
UPDATE users SET is_admin = sqlc.arg(is_admin) WHERE username = sqlc.arg(username);

-- A disabled admin cannot sign in, so only active admins count (#1908).
-- name: CountActiveAdmins :one
SELECT COUNT(*) FROM users WHERE is_admin = 1 AND status = 'active';

-- CountOtherActiveAdmins counts the active admins other than one account, so a
-- change to that account can tell whether it would leave the Quark with none.
-- name: CountOtherActiveAdmins :one
SELECT COUNT(*) FROM users WHERE is_admin = 1 AND status = 'active' AND id != sqlc.arg(id);

-- LockActiveAdmins changes nothing: it is a no-op UPDATE run for the row locks
-- it takes, as the first statement of a transaction that may take away an
-- active admin (#3171). PostgreSQL makes a second such transaction wait here
-- until the first commits, so its count of the admins sees what the first did;
-- without the lock two of them at READ COMMITTED each count the other's admin
-- as still there. On SQLite it takes the write lock before the transaction has
-- read anything, so a second one waits under busy_timeout, where a
-- transaction that read first fails as soon as it tries to write.
-- name: LockActiveAdmins :exec
UPDATE users SET is_admin = is_admin WHERE is_admin = 1 AND status = 'active';

-- GetOldestActiveAdmin is the longest-standing active admin other than one
-- account: the heir of an account that deletes itself (#1909).
-- name: GetOldestActiveAdmin :one
SELECT * FROM users
WHERE is_admin = 1 AND status = 'active' AND id != sqlc.arg(id)
ORDER BY created_at, id
LIMIT 1;

-- CountOtherAccounts counts the active and disabled accounts other than one.
-- Pending requests are not accounts yet, so they do not count.
-- name: CountOtherAccounts :one
SELECT COUNT(*) FROM users WHERE id != sqlc.arg(id) AND status != 'pending';

-- DeletePendingUsers drops every account request, when the last admin deletes
-- themselves and the Quark returns to setup.
-- name: DeletePendingUsers :exec
DELETE FROM users WHERE status = 'pending';

-- name: IsUserAdmin :one
SELECT is_admin FROM users WHERE username = sqlc.arg(username);

-- name: ListUsers :many
SELECT id, username, is_admin, status, created_at, recovery_key_hash != '' AS has_recovery_key, recovery_phrase_words FROM users ORDER BY created_at ASC;

-- Only an active account can be promoted; anything else matches no row.
-- name: PromoteToAdmin :one
UPDATE users SET is_admin = 1 WHERE username = sqlc.arg(username) AND status = 'active' RETURNING id, username, is_admin, created_at;

-- name: DemoteFromAdmin :one
UPDATE users SET is_admin = 0 WHERE username = sqlc.arg(username) RETURNING id, username, is_admin, created_at;

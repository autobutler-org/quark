-- name: SetUserAdmin :exec
UPDATE users SET is_admin = ? WHERE username = ?;

-- A disabled admin cannot sign in, so only active admins count (#1908).
-- name: CountActiveAdmins :one
SELECT COUNT(*) FROM users WHERE is_admin = 1 AND status = 'active';

-- CountOtherActiveAdmins counts the active admins other than one account, so a
-- change to that account can tell whether it would leave the Quark with none.
-- name: CountOtherActiveAdmins :one
SELECT COUNT(*) FROM users WHERE is_admin = 1 AND status = 'active' AND id != ?;

-- GetOldestActiveAdmin is the longest-standing active admin other than one
-- account: the heir of an account that deletes itself (#1909).
-- name: GetOldestActiveAdmin :one
SELECT * FROM users
WHERE is_admin = 1 AND status = 'active' AND id != ?
ORDER BY created_at, id
LIMIT 1;

-- CountOtherAccounts counts the active and disabled accounts other than one.
-- Pending requests are not accounts yet, so they do not count.
-- name: CountOtherAccounts :one
SELECT COUNT(*) FROM users WHERE id != ? AND status != 'pending';

-- DeletePendingUsers drops every account request, when the last admin deletes
-- themselves and the Quark returns to setup.
-- name: DeletePendingUsers :exec
DELETE FROM users WHERE status = 'pending';

-- name: IsUserAdmin :one
SELECT is_admin FROM users WHERE username = ?;

-- name: ListUsers :many
SELECT id, username, is_admin, status, created_at FROM users ORDER BY created_at ASC;

-- Only an active account can be promoted; anything else matches no row.
-- name: PromoteToAdmin :one
UPDATE users SET is_admin = 1 WHERE username = ? AND status = 'active' RETURNING id, username, is_admin, created_at;

-- name: DemoteFromAdmin :one
UPDATE users SET is_admin = 0 WHERE username = ? RETURNING id, username, is_admin, created_at;

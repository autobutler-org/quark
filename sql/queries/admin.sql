-- name: SetUserAdmin :exec
UPDATE users SET is_admin = ? WHERE username = ?;

-- A disabled admin cannot sign in, so only active admins count (#1908).
-- name: CountActiveAdmins :one
SELECT COUNT(*) FROM users WHERE is_admin = 1 AND status = 'active';

-- name: IsUserAdmin :one
SELECT is_admin FROM users WHERE username = ?;

-- name: ListUsers :many
SELECT id, username, is_admin, status, created_at FROM users ORDER BY created_at ASC;

-- Only an active account can be promoted; anything else matches no row.
-- name: PromoteToAdmin :one
UPDATE users SET is_admin = 1 WHERE username = ? AND status = 'active' RETURNING id, username, is_admin, created_at;

-- name: DemoteFromAdmin :one
UPDATE users SET is_admin = 0 WHERE username = ? RETURNING id, username, is_admin, created_at;

-- name: CreateUser :one
INSERT INTO users (username, password_hash, recovery_phrase_hash)
VALUES (?, ?, ?)
RETURNING *;

-- name: GetUserByUsername :one
SELECT * FROM users WHERE username = ? LIMIT 1;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = ? LIMIT 1;

-- name: CountUsers :one
SELECT COUNT(*) FROM users;

-- name: UpdateUserPassword :exec
UPDATE users
SET password_hash = ?
WHERE id = ?;

-- name: CreateSession :one
INSERT INTO sessions (token, user_id, expires_at, last_used_at)
VALUES (?, ?, ?, ?)
RETURNING *;

-- name: GetSession :one
SELECT s.*, u.username
FROM sessions s
JOIN users u ON s.user_id = u.id
WHERE s.token = ? AND s.expires_at > datetime('now')
LIMIT 1;

-- Slides a session's expiry forward on use (#1647). The new expiry is computed
-- in Go so the cap against created_at stays testable; this only writes it.
-- name: RenewSession :exec
UPDATE sessions
SET expires_at = ?, last_used_at = ?
WHERE token = ?;

-- name: DeleteSession :exec
DELETE FROM sessions WHERE token = ?;

-- name: DeleteExpiredSessions :exec
DELETE FROM sessions WHERE expires_at <= datetime('now');

-- name: DeleteUserSessions :exec
DELETE FROM sessions WHERE user_id = ?;

-- name: ListActiveSessionsForUser :many
SELECT token, user_id, expires_at, created_at
FROM sessions
WHERE user_id = ? AND expires_at > datetime('now')
ORDER BY created_at DESC;

-- Deletes one user. sessions.user_id is ON DELETE CASCADE (001_auth) and
-- connections set _foreign_keys=on, so the user's sessions go with the row.
-- name: DeleteUser :exec
DELETE FROM users WHERE id = ?;

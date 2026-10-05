-- name: CreateUser :one
INSERT INTO users (username, password_hash, recovery_phrase_hash, auth_key_hash, auth_salt, recovery_key_hash)
VALUES (?, ?, ?, ?, ?, ?)
RETURNING *;

-- CreatePendingUser records an account request from the sign-in page (#1908).
-- It cannot sign in until an admin approves it.
-- name: CreatePendingUser :one
INSERT INTO users (username, password_hash, recovery_phrase_hash, auth_key_hash, auth_salt, recovery_key_hash, status)
VALUES (?, ?, ?, ?, ?, ?, 'pending')
RETURNING *;

-- DeletePendingUser denies an account request. Only a pending row matches, so
-- a request that was already approved is left alone.
-- name: DeletePendingUser :execrows
DELETE FROM users WHERE username = ? AND status = 'pending';

-- name: GetUserByUsername :one
SELECT * FROM users WHERE username = ? LIMIT 1;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = ? LIMIT 1;

-- name: CountUsers :one
SELECT COUNT(*) FROM users;

-- SetUserStatus moves an account from one status to another in one
-- conditional update, so two admins acting at once cannot both succeed.
-- name: SetUserStatus :execrows
UPDATE users
SET status = sqlc.arg(to_status)
WHERE username = sqlc.arg(username) AND status = sqlc.arg(from_status);

-- SetRecoveryPhraseIfUnset gives an admin-created account its recovery phrase
-- on its first sign-in (#1873). Only an account with neither a phrase nor a
-- recovery key matches, so two sign-ins at once cannot both hand out a phrase,
-- and one racing a recovery-key rotation cannot undo it (#2430).
-- name: SetRecoveryPhraseIfUnset :execrows
UPDATE users
SET recovery_phrase_hash = ?
WHERE id = ? AND recovery_phrase_hash = '' AND recovery_key_hash = '';

-- SetRecoveryKey gives an account the recovery key its client derived from a
-- phrase it generated (#2430), and clears the phrase hash so the old phrase,
-- which the Quark saw, stops recovering the account.
-- name: SetRecoveryKey :exec
UPDATE users
SET recovery_key_hash = ?, recovery_phrase_hash = ''
WHERE id = ?;

-- SetUserCredentials replaces everything an account signs in with (#2430). A
-- recovery writes all three so that whichever of the password and the auth
-- key it did not set is cleared, and the old one stops signing in.
-- name: SetUserCredentials :exec
UPDATE users
SET password_hash = ?, auth_key_hash = ?, auth_salt = ?
WHERE id = ?;

-- SetAuthKeyIfUnset upgrades an account to an auth key on a sign-in that
-- carried both the password and the key (#2430). Only an empty hash matches,
-- so an upgraded account's key is never overwritten.
-- name: SetAuthKeyIfUnset :exec
UPDATE users
SET auth_key_hash = ?, auth_salt = ?
WHERE id = ? AND auth_key_hash = '';

-- name: CreateSession :one
INSERT INTO sessions (token, user_id, expires_at, last_used_at)
VALUES (?, ?, ?, ?)
RETURNING *;

-- Only an active account's session counts (#1908): a pending account has
-- never been approved, and a disabled one was turned off.
-- name: GetSession :one
SELECT s.*, u.username
FROM sessions s
JOIN users u ON s.user_id = u.id
WHERE s.token = ? AND s.expires_at > datetime('now') AND u.status = 'active'
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

-- "Sign out everywhere else" (#1663): every session of the user but the one
-- the request came in on.
-- name: DeleteOtherUserSessions :exec
DELETE FROM sessions WHERE user_id = ? AND token != ?;

-- name: ListActiveSessionsForUser :many
SELECT token, user_id, expires_at, created_at, last_used_at
FROM sessions
WHERE user_id = ? AND expires_at > datetime('now')
ORDER BY created_at DESC;

-- Deletes one user. sessions.user_id is ON DELETE CASCADE (001_auth) and
-- connections set _foreign_keys=on, so the user's sessions go with the row.
-- name: DeleteUser :exec
DELETE FROM users WHERE id = ?;

-- ListActiveUsers lists the accounts a file or folder can be shared with
-- (#1911): active ones only, and nothing about them beyond their names.
-- name: ListActiveUsers :many
SELECT id, username FROM users WHERE status = 'active' ORDER BY username;

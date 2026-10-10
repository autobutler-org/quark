-- name: ListSettings :many
SELECT key, value FROM settings;

-- name: GetSetting :one
SELECT value FROM settings WHERE key = ?;

-- name: SetSetting :exec
INSERT INTO settings (key, value) VALUES (?, ?)
ON CONFLICT (key) DO UPDATE SET value = excluded.value;

-- name: AddSetting :exec
-- Keeps a value already there: for the salt secret two instances may both try
-- to create, and for the import of settings.json.
INSERT INTO settings (key, value) VALUES (?, ?)
ON CONFLICT (key) DO NOTHING;

-- name: GetUserSettings :one
SELECT settings FROM user_settings WHERE user_id = ?;

-- name: SetUserSettings :exec
INSERT INTO user_settings (user_id, settings) VALUES (?, ?)
ON CONFLICT (user_id) DO UPDATE SET settings = excluded.settings;

-- name: AddUserSettings :exec
-- For the import of user-settings/: keeps settings already there, and skips a
-- file whose account is gone.
INSERT INTO user_settings (user_id, settings)
SELECT u.id, sqlc.arg(settings) FROM users u WHERE u.id = sqlc.arg(user_id)
ON CONFLICT (user_id) DO NOTHING;

-- name: AddAccountRequestDecision :exec
INSERT INTO account_request_history (username, outcome, decided_by, decided_at)
VALUES (?, ?, ?, ?)
ON CONFLICT DO NOTHING;

-- name: TrimAccountRequestHistory :exec
DELETE FROM account_request_history
WHERE id NOT IN (SELECT id FROM account_request_history ORDER BY id DESC LIMIT ?);

-- name: ListAccountRequestHistory :many
SELECT username, outcome, decided_by, decided_at
FROM account_request_history
ORDER BY id DESC
LIMIT ?;

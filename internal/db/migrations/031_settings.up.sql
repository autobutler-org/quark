-- State that lived in small files in the data directory, moved here so every
-- instance on one database reads and writes the same values (#3083).

-- The Quark's settings, one row per key so a save of one never reverts
-- another. value is the JSON of that one setting. A feature flag is the key
-- featureFlags.<flag>. Was settings.json and last-snapshot-backup.
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- What one account chose for itself, as the JSON of usersettingsutil.Settings.
-- Was user-settings/<user id>.json.
CREATE TABLE user_settings (
    user_id INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    settings TEXT NOT NULL
);

-- The decisions admins made about account requests, oldest first by id. Was
-- account-request-history.jsonl. The unique index makes importing that file
-- twice, or from two instances at once, add nothing.
CREATE TABLE account_request_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    outcome TEXT NOT NULL,
    decided_by TEXT NOT NULL,
    decided_at DATETIME NOT NULL,
    UNIQUE (username, outcome, decided_by, decided_at)
);

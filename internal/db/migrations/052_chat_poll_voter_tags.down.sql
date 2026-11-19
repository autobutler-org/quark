-- A tagged answer cannot be traced back to its account, so it goes.
CREATE TABLE chat_poll_answers_old (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id  INTEGER NOT NULL REFERENCES chat_polls (message_id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at  DATETIME NOT NULL DEFAULT (datetime('now')),
    UNIQUE (message_id, user_id)
);

INSERT INTO chat_poll_answers_old (id, message_id, user_id, key_version, ciphertext, created_at, updated_at)
SELECT id, message_id, user_id, key_version, ciphertext, created_at, updated_at
FROM chat_poll_answers WHERE user_id IS NOT NULL;

DROP TABLE chat_poll_answers;

ALTER TABLE chat_poll_answers_old RENAME TO chat_poll_answers;

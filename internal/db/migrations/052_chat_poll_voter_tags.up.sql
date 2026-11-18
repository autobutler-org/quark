-- An anonymous poll's answer names no account (#3942). Its row holds a voter
-- tag instead: HMAC-SHA256 over the poll and the account under a key kept in
-- the data directory, outside this database and every backup
-- (chatutil's voter tag). UNIQUE (message_id, voter_tag) still holds each
-- account to one answer, and the Quark finds the caller's own by recomputing
-- the tag. A poll that names who answered keeps user_id.
--
-- A row has one or the other. SQL cannot compute the tag, so the anonymous
-- answers already stored keep user_id here, and the server converts them at
-- start (chatutil.TagAnonymousPollAnswers). SQLite cannot drop NOT NULL in
-- place, so the table is rebuilt, ids and all; voter_tag goes last, where
-- PostgreSQL's ADD COLUMN puts it.
CREATE TABLE chat_poll_answers_new (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id  INTEGER NOT NULL REFERENCES chat_polls (message_id) ON DELETE CASCADE,
    user_id     INTEGER REFERENCES users (id) ON DELETE CASCADE,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now')),
    updated_at  DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now')),
    voter_tag   BLOB,
    UNIQUE (message_id, user_id),
    UNIQUE (message_id, voter_tag),
    CHECK ((user_id IS NULL) <> (voter_tag IS NULL))
);

INSERT INTO chat_poll_answers_new (id, message_id, user_id, key_version, ciphertext, created_at, updated_at)
SELECT id, message_id, user_id, key_version, ciphertext, created_at, updated_at FROM chat_poll_answers;

DROP TABLE chat_poll_answers;

ALTER TABLE chat_poll_answers_new RENAME TO chat_poll_answers;

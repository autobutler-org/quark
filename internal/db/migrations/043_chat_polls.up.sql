-- Chat polls (#3893). A poll is a chat message whose ciphertext holds the
-- question and options; this row holds the settings the Quark enforces, which
-- it must read, so they are plaintext. An answer is ciphertext under the
-- channel's key like a reaction: the Quark knows who answered which poll and
-- when, never what. ciphertext is nonce || XChaCha20-Poly1305 output over a
-- plaintext padded to 4 KiB, so every answer is the same size.
--
-- A poll is closed once closed_at is set, by its author, or closes_at has
-- passed. Nothing runs at closes_at: an answer is checked when it arrives.
CREATE TABLE chat_polls (
    message_id          INTEGER PRIMARY KEY REFERENCES chat_messages (id) ON DELETE CASCADE,
    closes_at           DATETIME,
    closed_at           DATETIME,
    allow_change        BOOLEAN NOT NULL,
    anonymous           BOOLEAN NOT NULL,
    results_after_close BOOLEAN NOT NULL
);

-- One answer per account and poll; a changed answer replaces the row.
CREATE TABLE chat_poll_answers (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id  INTEGER NOT NULL REFERENCES chat_polls (message_id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at  DATETIME NOT NULL DEFAULT (datetime('now')),
    UNIQUE (message_id, user_id)
);

-- A deleted poll's settings and answers go with its ciphertext, in the
-- statement that tombstones it; the answers follow chat_polls by cascade.
CREATE TRIGGER chat_polls_tombstone
AFTER UPDATE OF deleted_at ON chat_messages
WHEN NEW.deleted_at IS NOT NULL
BEGIN
    DELETE FROM chat_polls WHERE message_id = NEW.id;
END;

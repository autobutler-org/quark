-- Channel keys and who has been given them (#2417). A channel's messages are
-- encrypted under a symmetric key the Quark never sees; each version of it
-- reaches a member only as a grant, the key sealed to that member's X25519
-- key (016) and signed by the member who granted it. Clients create keys and
-- fill grants, because the Quark can't.

CREATE TABLE chat_channel_keys (
    channel_id INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    version    INTEGER NOT NULL CHECK (version > 0),
    created_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (channel_id, version)
);

-- user_id and granted_by are kept as NULL when the account is deleted: a
-- current-version grant whose recipient is gone is how the Quark knows the key
-- must rotate, and a grant whose granter is gone still verifies against
-- granter_sign_key, the granter's published Ed25519 key copied here when the
-- grant was uploaded.
CREATE TABLE chat_key_grants (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id       INTEGER NOT NULL,
    version          INTEGER NOT NULL,
    user_id          INTEGER REFERENCES users (id) ON DELETE SET NULL,
    sealed_key       BLOB NOT NULL,
    granted_by       INTEGER REFERENCES users (id) ON DELETE SET NULL,
    granter_sign_key BLOB NOT NULL,
    signature        BLOB NOT NULL,
    created_at       DATETIME NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (channel_id, version) REFERENCES chat_channel_keys (channel_id, version) ON DELETE CASCADE
);

-- The first grant for a member and version wins; later uploads are ignored.
CREATE UNIQUE INDEX idx_chat_key_grants_recipient
    ON chat_key_grants (channel_id, version, user_id);

-- Membership and key changes, shown as system lines in the channel. The Quark
-- writes the row with a payload it built; the actor's client then signs it,
-- and signer_sign_key is the actor's published key when it did. An unsigned
-- row is shown as unverified.
CREATE TABLE chat_channel_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id      INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    kind            TEXT NOT NULL CHECK (kind IN ('member_set', 'member_removed', 'key_created')),
    actor_id        INTEGER REFERENCES users (id) ON DELETE SET NULL,
    payload         TEXT NOT NULL,
    signature       BLOB,
    signer_sign_key BLOB,
    created_at      DATETIME NOT NULL DEFAULT (datetime('now')),
    CHECK ((signature IS NULL) = (signer_sign_key IS NULL))
);

CREATE INDEX idx_chat_channel_events_channel
    ON chat_channel_events (channel_id, id);

-- Each account's chat identity (#2416): an X25519 key that channel keys are
-- sealed to and an Ed25519 key that signs grants, generated on the client.
-- The private seeds are stored only wrapped, under Argon2id of the login
-- password and, when the client had it, of the recovery phrase; the Quark
-- never holds a key that opens them. kdf_params is the client's JSON record
-- of the Argon2id cost, opaque here.
CREATE TABLE user_chat_keys (
    user_id             INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    box_public_key      BLOB NOT NULL,
    sign_public_key     BLOB NOT NULL,
    wrapped_by_password BLOB NOT NULL,
    salt_pw             BLOB NOT NULL,
    -- Null for keys made at a sign-in that had no recovery phrase to hand.
    wrapped_by_phrase   BLOB,
    salt_rp             BLOB,
    kdf_params          TEXT NOT NULL,
    created_at          DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at          DATETIME NOT NULL DEFAULT (datetime('now')),
    CHECK ((wrapped_by_phrase IS NULL) = (salt_rp IS NULL))
);

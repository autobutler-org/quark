package db

import "database/sql"

// ChatBackupVersion is the format of the chat backup file, stored in its
// user_version. It moves when ChatBackupSchemaDDL does, and a restore refuses
// a version it does not know rather than guess at its columns.
const ChatBackupVersion = 1

// ChatBackupSchemaDDL is the schema of the chat backup file pkg/backup writes
// beside a snapshot (#2428). It is a transport format, not a database anyone
// queries: each chat table has the live table's columns in the live table's
// order, and none of its foreign keys, indexes or triggers. The live schema
// enforces all of that again when a restore loads the rows.
//
// users and groups are a directory, not the accounts: the name behind every id
// the chat rows mention, so a restore can find the same account on a Quark
// that numbered its accounts differently. No password hash is ever copied.
//
// A migration that changes a chat table changes this too, and bumps
// ChatBackupVersion; TestChatBackupSchema_MatchesLiveTables in pkg/backup
// fails until the columns agree.
const ChatBackupSchemaDDL = `
PRAGMA user_version = 1;

CREATE TABLE users (
    id       INTEGER PRIMARY KEY,
    username TEXT NOT NULL
);

CREATE TABLE groups (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE chat_servers (
    id         INTEGER PRIMARY KEY,
    name       TEXT NOT NULL,
    created_at DATETIME NOT NULL
);

CREATE TABLE chat_channels (
    id         INTEGER PRIMARY KEY,
    server_id  INTEGER NOT NULL,
    kind       TEXT NOT NULL,
    name       TEXT NOT NULL,
    topic      TEXT NOT NULL,
    is_default INTEGER NOT NULL,
    created_by INTEGER,
    created_at DATETIME NOT NULL
);

CREATE TABLE chat_channel_members (
    id          INTEGER PRIMARY KEY,
    channel_id  INTEGER NOT NULL,
    user_id     INTEGER,
    group_id    INTEGER,
    permissions INTEGER NOT NULL
);

CREATE TABLE user_chat_keys (
    user_id             INTEGER PRIMARY KEY,
    box_public_key      BLOB NOT NULL,
    sign_public_key     BLOB NOT NULL,
    wrapped_by_password BLOB NOT NULL,
    salt_pw             BLOB NOT NULL,
    wrapped_by_phrase   BLOB,
    salt_rp             BLOB,
    kdf_params          TEXT NOT NULL,
    created_at          DATETIME NOT NULL,
    updated_at          DATETIME NOT NULL
);

CREATE TABLE chat_channel_keys (
    channel_id INTEGER NOT NULL,
    version    INTEGER NOT NULL,
    created_by INTEGER,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (channel_id, version)
);

CREATE TABLE chat_key_grants (
    id               INTEGER PRIMARY KEY,
    channel_id       INTEGER NOT NULL,
    version          INTEGER NOT NULL,
    user_id          INTEGER,
    sealed_key       BLOB NOT NULL,
    granted_by       INTEGER,
    granter_sign_key BLOB NOT NULL,
    signature        BLOB NOT NULL,
    created_at       DATETIME NOT NULL
);

CREATE TABLE chat_channel_events (
    id              INTEGER PRIMARY KEY,
    channel_id      INTEGER NOT NULL,
    kind            TEXT NOT NULL,
    actor_id        INTEGER,
    payload         TEXT NOT NULL,
    signature       BLOB,
    signer_sign_key BLOB,
    created_at      DATETIME NOT NULL
);

CREATE TABLE chat_messages (
    id          INTEGER PRIMARY KEY,
    channel_id  INTEGER NOT NULL,
    author_id   INTEGER,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB,
    created_at  DATETIME NOT NULL,
    edited_at   DATETIME,
    deleted_at  DATETIME,
    nonce       BLOB
);

CREATE TABLE chat_reactions (
    id          INTEGER PRIMARY KEY,
    message_id  INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL
);
`

// InitChatBackupSchema creates the chat backup tables in d, a database file
// that holds nothing yet.
func InitChatBackupSchema(d *sql.DB) error {
	_, err := d.Exec(ChatBackupSchemaDDL)
	return err
}

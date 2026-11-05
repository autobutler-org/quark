package db

// ChatBackupVersion is the format of the chat backup file, stored in its
// user_version. It moves when ChatBackupSchemaDDL does, and a restore refuses
// a version it does not know rather than guess at its columns.
const ChatBackupVersion = 3

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
// ChatBackupVersion when a restore could no longer read the file;
// TestChatBackupSchema_MatchesLiveTables in pkg/backup fails until the columns
// agree. chat_messages.client_message_id (#3531) is exported but never
// restored, so it left the version at 1: a file with or without it restores
// the same. Version 2 added chat_polls and chat_poll_answers (#3893).
// Version 3 added chat_attachments (#2425).
const ChatBackupSchemaDDL = `
PRAGMA user_version = 3;

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
    id                INTEGER PRIMARY KEY,
    channel_id        INTEGER NOT NULL,
    author_id         INTEGER,
    key_version       INTEGER NOT NULL,
    ciphertext        BLOB,
    created_at        DATETIME NOT NULL,
    edited_at         DATETIME,
    deleted_at        DATETIME,
    nonce             BLOB,
    client_message_id TEXT
);

CREATE TABLE chat_reactions (
    id          INTEGER PRIMARY KEY,
    message_id  INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL
);

CREATE TABLE chat_polls (
    message_id          INTEGER PRIMARY KEY,
    closes_at           DATETIME,
    closed_at           DATETIME,
    allow_change        BOOLEAN NOT NULL,
    anonymous           BOOLEAN NOT NULL,
    results_after_close BOOLEAN NOT NULL
);

CREATE TABLE chat_poll_answers (
    id          INTEGER PRIMARY KEY,
    message_id  INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    key_version INTEGER NOT NULL,
    ciphertext  BLOB NOT NULL,
    created_at  DATETIME NOT NULL,
    updated_at  DATETIME NOT NULL
);

CREATE TABLE chat_attachments (
    id          TEXT PRIMARY KEY,
    channel_id  INTEGER NOT NULL,
    message_id  INTEGER,
    uploader_id INTEGER NOT NULL,
    byte_size   INTEGER NOT NULL,
    created_at  DATETIME NOT NULL
);
`

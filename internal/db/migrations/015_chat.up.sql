-- Chat channels and who may see them (#2415). The shape copies path_access
-- (010): a member row names one account or one group, at read, write or owner,
-- and membership is additive, the best level winning. Admins do not bypass it:
-- channel content is end-to-end encrypted, so an admin who is not a member
-- could not read it anyway. Messages and keys are separate tables (#2417,
-- #2418).

-- One row in phase 1. The table exists so channels have a parent when a Quark
-- hosts more than one server, without a migration that moves every channel.
CREATE TABLE chat_servers (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT (datetime('now'))
);

-- kind is 'channel' for a named channel and 'dm' for a direct message (#2423),
-- which has no name; it is here now so DMs don't have to rebuild the table.
-- is_default marks general, which can't be deleted.
CREATE TABLE chat_channels (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    server_id  INTEGER NOT NULL REFERENCES chat_servers (id) ON DELETE CASCADE,
    kind       TEXT NOT NULL DEFAULT 'channel' CHECK (kind IN ('channel', 'dm')),
    name       TEXT NOT NULL DEFAULT '',
    topic      TEXT NOT NULL DEFAULT '',
    is_default INTEGER NOT NULL DEFAULT 0,
    created_by INTEGER REFERENCES users (id) ON DELETE SET NULL,
    created_at DATETIME NOT NULL DEFAULT (datetime('now'))
);

-- Channel names are unique per server ignoring case, like group names (012).
-- DMs have no name, so they are left out.
CREATE UNIQUE INDEX idx_chat_channels_name
    ON chat_channels (server_id, name COLLATE NOCASE) WHERE kind = 'channel';

CREATE TABLE chat_channel_members (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    user_id    INTEGER REFERENCES users (id) ON DELETE CASCADE,
    group_id   INTEGER REFERENCES groups (id) ON DELETE CASCADE,
    level      TEXT NOT NULL CHECK (level IN ('read', 'write', 'owner')),
    CHECK ((user_id IS NULL) <> (group_id IS NULL))
);

-- One row per channel and principal. A plain UNIQUE would treat the NULL half
-- of every row as distinct, so each principal kind gets a partial index.
CREATE UNIQUE INDEX idx_chat_channel_members_user
    ON chat_channel_members (user_id, channel_id) WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX idx_chat_channel_members_group
    ON chat_channel_members (group_id, channel_id) WHERE group_id IS NOT NULL;

CREATE INDEX idx_chat_channel_members_channel
    ON chat_channel_members (channel_id);

-- The server, and general for everyone: every current and future account is a
-- member without anyone doing anything.
INSERT INTO chat_servers (name) VALUES ('Quark');

INSERT INTO chat_channels (server_id, name, is_default)
SELECT id, 'general', 1 FROM chat_servers;

INSERT INTO chat_channel_members (channel_id, group_id, level)
SELECT chat_channels.id, groups.id, 'write'
FROM chat_channels, groups
WHERE chat_channels.is_default = 1 AND groups.name = 'everyone' AND groups.builtin = 1;

-- Who may reach a path (#1902). Quark is the source of truth for access: the
-- drives it manages may be exFAT or NTFS with every file owned by one host
-- user and no extended attributes, so nothing about access can live on disk.
--
-- Rows are keyed by (device_serial, rel_path), the key the photo tables use.
-- rel_path is slash-separated, cleaned and has no leading slash; '' is the
-- device root. Access is additive down the tree: a path's level is the highest
-- level on it or any ancestor. Admins bypass the table entirely, so a path
-- with no rows is admin-only.

CREATE TABLE groups (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    name    TEXT NOT NULL UNIQUE,
    builtin INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE group_members (
    group_id INTEGER NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
    user_id  INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, user_id)
);

CREATE TABLE path_access (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    device_serial TEXT NOT NULL DEFAULT '',
    rel_path      TEXT NOT NULL,
    user_id       INTEGER REFERENCES users (id) ON DELETE CASCADE,
    group_id      INTEGER REFERENCES groups (id) ON DELETE CASCADE,
    level         TEXT NOT NULL CHECK (level IN ('read', 'write', 'owner')),
    CHECK ((user_id IS NULL) <> (group_id IS NULL))
);

-- One row per path and principal. A plain UNIQUE would treat the NULL half of
-- every row as distinct, so each principal kind gets a partial index.
CREATE UNIQUE INDEX idx_path_access_user
    ON path_access (user_id, device_serial, rel_path) WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX idx_path_access_group
    ON path_access (group_id, device_serial, rel_path) WHERE group_id IS NOT NULL;

CREATE INDEX idx_path_access_path
    ON path_access (device_serial, rel_path);

-- Every active user is in everyone; it has no member rows.
INSERT INTO groups (name, builtin) VALUES ('everyone', 1);

-- ListChatChannelsForUser lists the channels an account has a row on,
-- directly, through a group, or through everyone: one result row per
-- membership row, adjacent per channel, since SQLite has no bitwise-OR
-- aggregate and the caller unions the permissions (chatutil.ListChannels).
-- is_private is whether everyone has no row on the channel.
-- name: ListChatChannelsForUser :many
SELECT
    chat_channels.id,
    chat_channels.server_id,
    chat_channels.kind,
    chat_channels.name,
    chat_channels.topic,
    chat_channels.is_default,
    chat_channels.created_by,
    chat_channels.created_at,
    chat_channels.forked,
    chat_channels.anonymous,
    chat_channel_members.permissions,
    CAST(CASE WHEN NOT EXISTS (
        SELECT
            1
        FROM
            chat_channel_members AS everyone_rows
            JOIN groups ON groups.id = everyone_rows.group_id
        WHERE
            everyone_rows.channel_id = chat_channels.id
            AND groups.name = 'everyone'
            AND groups.builtin = 1
    ) THEN 1 ELSE 0 END AS BIGINT) AS is_private
FROM
    chat_channels
    JOIN chat_channel_members ON chat_channel_members.channel_id = chat_channels.id
WHERE
    chat_channel_members.user_id = sqlc.arg(user_id)
    OR chat_channel_members.group_id IN (
        SELECT
            group_id
        FROM
            group_members
        WHERE
            group_members.user_id = sqlc.arg(user_id)
    )
    OR chat_channel_members.group_id IN (
        SELECT
            id
        FROM
            groups
        WHERE
            name = 'everyone'
            AND builtin = 1
    )
ORDER BY
    chat_channels.is_default DESC,
    LOWER(chat_channels.name),
    chat_channels.id;

-- ListAllChatChannels is every named channel on the Quark, for an admin
-- looking for the ones they are not in (#2422), ordered as
-- ListChatChannelsForUser. Direct messages are left out: they are for their
-- members alone, admins included (#2423).
-- name: ListAllChatChannels :many
SELECT
    chat_channels.id,
    chat_channels.server_id,
    chat_channels.kind,
    chat_channels.name,
    chat_channels.topic,
    chat_channels.is_default,
    chat_channels.created_by,
    chat_channels.created_at,
    chat_channels.anonymous,
    CAST(CASE WHEN NOT EXISTS (
        SELECT
            1
        FROM
            chat_channel_members AS everyone_rows
            JOIN groups ON groups.id = everyone_rows.group_id
        WHERE
            everyone_rows.channel_id = chat_channels.id
            AND groups.name = 'everyone'
            AND groups.builtin = 1
    ) THEN 1 ELSE 0 END AS BIGINT) AS is_private
FROM
    chat_channels
WHERE
    chat_channels.kind = 'channel'
ORDER BY
    chat_channels.is_default DESC,
    LOWER(chat_channels.name),
    chat_channels.id;

-- ListChatChannelPermsForUser is the set on every row of one channel that
-- reaches an account, for chatutil.ResolvePerms to union.
-- name: ListChatChannelPermsForUser :many
SELECT
    chat_channel_members.permissions
FROM
    chat_channel_members
WHERE
    chat_channel_members.channel_id = sqlc.arg(channel_id)
    AND (
        chat_channel_members.user_id = sqlc.arg(user_id)
        OR chat_channel_members.group_id IN (
            SELECT
                group_id
            FROM
                group_members
            WHERE
                group_members.user_id = sqlc.arg(user_id)
        )
        OR chat_channel_members.group_id IN (
            SELECT
                id
            FROM
                groups
            WHERE
                name = 'everyone'
                AND builtin = 1
        )
    );

-- name: GetChatChannel :one
SELECT * FROM chat_channels WHERE id = sqlc.arg(id) LIMIT 1;

-- LockChatChannel changes nothing: it is a no-op UPDATE run for the row lock it
-- takes, as the first statement of a transaction that changes a channel's
-- members (#3171). PostgreSQL makes a second such transaction on the channel
-- wait here until the first commits, so its count of the holders of
-- manage_channel sees what the first did; without the lock two of them at
-- READ COMMITTED each count the other's holder as still there. On SQLite it
-- takes the write lock before the transaction has read anything, so a second
-- one waits under busy_timeout, where a transaction that read first fails as
-- soon as it tries to write. name is not a key column, so on PostgreSQL the
-- lock does not hold up an insert that references the channel.
-- name: LockChatChannel :exec
UPDATE chat_channels SET name = name WHERE id = sqlc.arg(id);

-- CreateChatChannel adds a channel to the Quark's one server. anonymous is 1
-- for an anonymous channel (#2949), and never changes afterward.
-- name: CreateChatChannel :one
INSERT INTO
    chat_channels (server_id, name, topic, created_by, anonymous)
VALUES
    ((SELECT MIN(id) FROM chat_servers), sqlc.arg(name), sqlc.arg(topic), sqlc.arg(created_by), sqlc.arg(anonymous)) RETURNING *;

-- CreateChatDirectMessage adds a direct message (#2423) unless one with the
-- same dm_key already exists, in which case it returns no row: the unique
-- index on dm_key settles two openers racing, on either engine. forked is 1
-- for one started by adding people to another.
-- name: CreateChatDirectMessage :one
INSERT INTO
    chat_channels (server_id, kind, created_by, dm_key, forked)
VALUES
    ((SELECT MIN(id) FROM chat_servers), 'dm', sqlc.arg(created_by), sqlc.arg(dm_key), sqlc.arg(forked)) ON CONFLICT (dm_key) DO NOTHING RETURNING *;

-- name: GetChatDirectMessage :one
SELECT * FROM chat_channels WHERE dm_key = sqlc.arg(dm_key) LIMIT 1;

-- name: UpdateChatChannel :one
UPDATE chat_channels SET name = sqlc.arg(name), topic = sqlc.arg(topic) WHERE id = sqlc.arg(id) RETURNING *;

-- DeleteChatChannel drops a channel and, by ON DELETE CASCADE, its members.
-- The default channel is never deleted.
-- name: DeleteChatChannel :execrows
DELETE FROM chat_channels WHERE id = sqlc.arg(id) AND is_default = 0;

-- ListChatChannelMembers lists a channel's rows with the name of the account
-- or group each names. The CASTs give sqlc a type for each COALESCE.
-- name: ListChatChannelMembers :many
SELECT
    chat_channel_members.user_id,
    chat_channel_members.group_id,
    chat_channel_members.permissions,
    CAST(COALESCE(users.username, groups.name) AS TEXT) AS name,
    CAST(COALESCE(groups.builtin, 0) AS BIGINT) AS builtin
FROM
    chat_channel_members
    LEFT JOIN users ON users.id = chat_channel_members.user_id
    LEFT JOIN groups ON groups.id = chat_channel_members.group_id
WHERE
    chat_channel_members.channel_id = sqlc.arg(channel_id)
ORDER BY
    chat_channel_members.group_id IS NULL,
    LOWER(COALESCE(users.username, groups.name));

-- ListChatChannelGroupUsers expands each group row on a channel into the
-- active accounts in it; everyone holds every active account.
-- name: ListChatChannelGroupUsers :many
SELECT
    chat_channel_members.group_id,
    users.id AS user_id,
    users.username
FROM
    chat_channel_members
    JOIN groups ON groups.id = chat_channel_members.group_id
    JOIN users ON users.status = 'active'
    AND (
        (
            groups.name = 'everyone'
            AND groups.builtin = 1
        )
        OR users.id IN (
            SELECT
                user_id
            FROM
                group_members
            WHERE
                group_members.group_id = chat_channel_members.group_id
        )
    )
WHERE
    chat_channel_members.channel_id = sqlc.arg(channel_id)
ORDER BY
    LOWER(users.username);

-- ListChatChannelMemberUsers resolves a channel's rows into the active
-- accounts they reach: one result row per account and membership row,
-- adjacent per account, for the caller to union.
-- name: ListChatChannelMemberUsers :many
SELECT
    users.id,
    users.username,
    chat_channel_members.permissions
FROM
    chat_channel_members
    LEFT JOIN groups ON groups.id = chat_channel_members.group_id
    JOIN users ON users.status = 'active'
    AND (
        users.id = chat_channel_members.user_id
        OR (
            groups.name = 'everyone'
            AND groups.builtin = 1
        )
        OR users.id IN (
            SELECT
                user_id
            FROM
                group_members
            WHERE
                group_members.group_id = chat_channel_members.group_id
        )
    )
WHERE
    chat_channel_members.channel_id = sqlc.arg(channel_id)
ORDER BY
    LOWER(users.username),
    users.id;

-- SetChatChannelUserMember gives an account a set on a channel, replacing the
-- set any earlier row for it carried.
-- name: SetChatChannelUserMember :exec
INSERT INTO
    chat_channel_members (channel_id, user_id, permissions)
VALUES
    (sqlc.arg(channel_id), sqlc.arg(user_id), sqlc.arg(permissions)) ON CONFLICT (user_id, channel_id)
WHERE
    user_id IS NOT NULL DO
UPDATE
SET
    permissions = excluded.permissions;

-- SetChatChannelGroupMember gives a group a set on a channel, replacing the
-- set any earlier row for it carried.
-- name: SetChatChannelGroupMember :exec
INSERT INTO
    chat_channel_members (channel_id, group_id, permissions)
VALUES
    (sqlc.arg(channel_id), sqlc.arg(group_id), sqlc.arg(permissions)) ON CONFLICT (group_id, channel_id)
WHERE
    group_id IS NOT NULL DO
UPDATE
SET
    permissions = excluded.permissions;

-- name: DeleteChatChannelUserMember :execrows
DELETE FROM chat_channel_members WHERE channel_id = sqlc.arg(channel_id) AND user_id = sqlc.arg(user_id);

-- name: DeleteChatChannelGroupMember :execrows
DELETE FROM chat_channel_members WHERE channel_id = sqlc.arg(channel_id) AND group_id = sqlc.arg(group_id);

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
    chat_channel_members.permissions,
    CAST(NOT EXISTS (
        SELECT
            1
        FROM
            chat_channel_members AS everyone_rows
            JOIN groups ON groups.id = everyone_rows.group_id
        WHERE
            everyone_rows.channel_id = chat_channels.id
            AND groups.name = 'everyone'
            AND groups.builtin = 1
    ) AS INTEGER) AS is_private
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
    chat_channels.name COLLATE NOCASE,
    chat_channels.id;

-- ListAllChatChannels is every channel on the Quark, for an admin looking
-- for the ones they are not in (#2422), ordered as ListChatChannelsForUser.
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
    CAST(NOT EXISTS (
        SELECT
            1
        FROM
            chat_channel_members AS everyone_rows
            JOIN groups ON groups.id = everyone_rows.group_id
        WHERE
            everyone_rows.channel_id = chat_channels.id
            AND groups.name = 'everyone'
            AND groups.builtin = 1
    ) AS INTEGER) AS is_private
FROM
    chat_channels
ORDER BY
    chat_channels.is_default DESC,
    chat_channels.name COLLATE NOCASE,
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
SELECT * FROM chat_channels WHERE id = ? LIMIT 1;

-- CreateChatChannel adds a channel to the Quark's one server.
-- name: CreateChatChannel :one
INSERT INTO
    chat_channels (server_id, name, topic, created_by)
VALUES
    ((SELECT MIN(id) FROM chat_servers), ?, ?, ?) RETURNING *;

-- name: UpdateChatChannel :one
UPDATE chat_channels SET name = ?, topic = ? WHERE id = ? RETURNING *;

-- DeleteChatChannel drops a channel and, by ON DELETE CASCADE, its members.
-- The default channel is never deleted.
-- name: DeleteChatChannel :execrows
DELETE FROM chat_channels WHERE id = ? AND is_default = 0;

-- ListChatChannelMembers lists a channel's rows with the name of the account
-- or group each names. The CASTs give sqlc a type for each COALESCE.
-- name: ListChatChannelMembers :many
SELECT
    chat_channel_members.user_id,
    chat_channel_members.group_id,
    chat_channel_members.permissions,
    CAST(COALESCE(users.username, groups.name) AS TEXT) AS name,
    CAST(COALESCE(groups.builtin, 0) AS INTEGER) AS builtin
FROM
    chat_channel_members
    LEFT JOIN users ON users.id = chat_channel_members.user_id
    LEFT JOIN groups ON groups.id = chat_channel_members.group_id
WHERE
    chat_channel_members.channel_id = ?
ORDER BY
    chat_channel_members.group_id IS NULL,
    name COLLATE NOCASE;

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
    chat_channel_members.channel_id = ?
ORDER BY
    users.username COLLATE NOCASE;

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
    chat_channel_members.channel_id = ?
ORDER BY
    users.username COLLATE NOCASE,
    users.id;

-- SetChatChannelUserMember gives an account a set on a channel, replacing the
-- set any earlier row for it carried.
-- name: SetChatChannelUserMember :exec
INSERT INTO
    chat_channel_members (channel_id, user_id, permissions)
VALUES
    (?, ?, ?) ON CONFLICT (user_id, channel_id)
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
    (?, ?, ?) ON CONFLICT (group_id, channel_id)
WHERE
    group_id IS NOT NULL DO
UPDATE
SET
    permissions = excluded.permissions;

-- name: DeleteChatChannelUserMember :execrows
DELETE FROM chat_channel_members WHERE channel_id = ? AND user_id = ?;

-- name: DeleteChatChannelGroupMember :execrows
DELETE FROM chat_channel_members WHERE channel_id = ? AND group_id = ?;

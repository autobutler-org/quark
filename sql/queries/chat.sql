-- ListChatChannelsForUser lists the channels an account is a member of,
-- directly, through a group, or through everyone, with its best level on each.
-- is_private is whether everyone has no row on the channel. Membership is
-- additive and the best level wins, as ListPathAccessForUser resolves
-- path_access; levels are ranked read = 1, write = 2, owner = 3 here and in
-- the queries below so SQL can take the best one.
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
    CAST(MAX(
        CASE chat_channel_members.level
            WHEN 'owner' THEN 3
            WHEN 'write' THEN 2
            ELSE 1
        END
    ) AS INTEGER) AS level_rank,
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
GROUP BY
    chat_channels.id
ORDER BY
    chat_channels.is_default DESC,
    chat_channels.name COLLATE NOCASE,
    chat_channels.id;

-- GetChatChannelLevelForUser is an account's best level on one channel, 0
-- when it is not a member.
-- name: GetChatChannelLevelForUser :one
SELECT
    CAST(COALESCE(MAX(
        CASE chat_channel_members.level
            WHEN 'owner' THEN 3
            WHEN 'write' THEN 2
            ELSE 1
        END
    ), 0) AS INTEGER) AS level_rank
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
    chat_channel_members.level,
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
-- accounts they reach, each with its best level.
-- name: ListChatChannelMemberUsers :many
SELECT
    users.id,
    users.username,
    CAST(MAX(
        CASE chat_channel_members.level
            WHEN 'owner' THEN 3
            WHEN 'write' THEN 2
            ELSE 1
        END
    ) AS INTEGER) AS level_rank
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
GROUP BY
    users.id
ORDER BY
    users.username COLLATE NOCASE;

-- SetChatChannelUserMember gives an account a level on a channel, replacing
-- the level any earlier row for it carried.
-- name: SetChatChannelUserMember :exec
INSERT INTO
    chat_channel_members (channel_id, user_id, level)
VALUES
    (?, ?, ?) ON CONFLICT (user_id, channel_id)
WHERE
    user_id IS NOT NULL DO
UPDATE
SET
    level = excluded.level;

-- SetChatChannelGroupMember gives a group a level on a channel, replacing the
-- level any earlier row for it carried.
-- name: SetChatChannelGroupMember :exec
INSERT INTO
    chat_channel_members (channel_id, group_id, level)
VALUES
    (?, ?, ?) ON CONFLICT (group_id, channel_id)
WHERE
    group_id IS NOT NULL DO
UPDATE
SET
    level = excluded.level;

-- name: DeleteChatChannelUserMember :execrows
DELETE FROM chat_channel_members WHERE channel_id = ? AND user_id = ?;

-- name: DeleteChatChannelGroupMember :execrows
DELETE FROM chat_channel_members WHERE channel_id = ? AND group_id = ?;

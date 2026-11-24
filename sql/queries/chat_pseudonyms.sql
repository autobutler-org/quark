-- ListChatChannelPseudonyms is every pseudonym an anonymous channel has handed
-- out (#2949), for chatutil to show its members by.
-- name: ListChatChannelPseudonyms :many
SELECT
    *
FROM
    chat_channel_pseudonyms
WHERE
    channel_id = sqlc.arg(channel_id)
ORDER BY
    user_id;

-- CreateChatChannelPseudonym gives an account its pseudonym in a channel
-- unless it already has one, which is 0 rows. A pseudonym id or alias another
-- account in the channel holds, whatever its case, is a unique violation, and
-- the caller draws again.
-- name: CreateChatChannelPseudonym :execrows
INSERT INTO
    chat_channel_pseudonyms (channel_id, user_id, pseudonym_id, alias)
VALUES
    (sqlc.arg(channel_id), sqlc.arg(user_id), sqlc.arg(pseudonym_id), sqlc.arg(alias)) ON CONFLICT (channel_id, user_id) DO NOTHING;

-- SetChatChannelPseudonymAlias renames an account's pseudonym in a channel.
-- An alias another account in the channel holds, whatever its case, is a
-- unique violation.
-- name: SetChatChannelPseudonymAlias :execrows
UPDATE chat_channel_pseudonyms
SET
    alias = sqlc.arg(alias)
WHERE
    channel_id = sqlc.arg(channel_id)
    AND user_id = sqlc.arg(user_id);

-- ChatAliasIsUsername is whether an alias is some account's username in any
-- case, which an alias may never be, so it can't pass for an account.
-- name: ChatAliasIsUsername :one
SELECT
    CAST(
        CASE
            WHEN EXISTS (
                SELECT
                    1
                FROM
                    users
                WHERE
                    LOWER(username) = LOWER(sqlc.arg(alias))
            ) THEN 1
            ELSE 0
        END AS BIGINT
    ) AS taken;

-- SetChatChannelPseudonymKeys stores the public keys an account's app derived
-- for one anonymous channel, unless it already published some, which is 0
-- rows.
-- name: SetChatChannelPseudonymKeys :execrows
UPDATE chat_channel_pseudonyms
SET
    box_public_key = sqlc.arg(box_public_key),
    sign_public_key = sqlc.arg(sign_public_key)
WHERE
    channel_id = sqlc.arg(channel_id)
    AND user_id = sqlc.arg(user_id)
    AND box_public_key IS NULL;

-- ClearChatChannelPseudonymKeysForUser forgets an account's per-channel keys
-- in every anonymous channel, once its chat identity, which they are derived
-- from, has changed.
-- name: ClearChatChannelPseudonymKeysForUser :exec
UPDATE chat_channel_pseudonyms
SET
    box_public_key = NULL,
    sign_public_key = NULL
WHERE
    user_id = sqlc.arg(user_id);

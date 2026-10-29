-- Feed subscriptions (#3714). Every query takes the account's user_id, so no
-- call can reach another account's rows. url is a credential and is returned
-- only to that account.

-- ListFeeds returns an account's subscriptions, filed folders first.
-- name: ListFeeds :many
SELECT
    *
FROM
    feeds
WHERE
    user_id = sqlc.arg(user_id)
ORDER BY
    LOWER(folder),
    LOWER(CASE WHEN name = '' THEN title ELSE name END),
    id;

-- GetFeed returns one of an account's subscriptions. Another account's id
-- finds nothing.
-- name: GetFeed :one
SELECT
    *
FROM
    feeds
WHERE
    id = sqlc.arg(id)
    AND user_id = sqlc.arg(user_id);

-- CreateFeed stores a subscription. A second row with the same url for the
-- same account is a unique violation. url is stored whole, token included.
-- name: CreateFeed :one
INSERT INTO feeds (
    user_id,
    url,
    title,
    name,
    site_link,
    icon,
    folder
) VALUES (
    sqlc.arg(user_id), sqlc.arg(url), sqlc.arg(title), sqlc.arg(name), sqlc.arg(site_link), sqlc.arg(icon), sqlc.arg(folder)
)
RETURNING
    *;

-- UpdateFeed renames one of an account's subscriptions or moves it to another
-- folder. Another account's id updates nothing and returns no row. The feed
-- URL is not changed here.
-- name: UpdateFeed :one
UPDATE feeds
SET
    name = sqlc.arg(name),
    folder = sqlc.arg(folder),
    updated_at = CURRENT_TIMESTAMP
WHERE
    id = sqlc.arg(id)
    AND user_id = sqlc.arg(user_id)
RETURNING
    *;

-- DeleteFeed removes one of an account's subscriptions and, by the foreign
-- key, its entries. Another account's id deletes nothing.
-- name: DeleteFeed :execrows
DELETE FROM feeds
WHERE
    id = sqlc.arg(id)
    AND user_id = sqlc.arg(user_id);

-- name: GetInstallID :one
SELECT install_id FROM install WHERE id = 1;

-- name: RotateInstallID :exec
-- For a reset that leaves the database standing (files or devices only): the
-- other instances still have to drop what they hold for the wiped install.
UPDATE install SET install_id = lower(hex(randomblob(16))) WHERE id = 1;

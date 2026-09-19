-- Groups an admin manages (#1910). The built-in everyone group is seeded by
-- 010_path_access; the builtin = 0 guards keep every change away from it.

-- name: ListGroups :many
SELECT * FROM groups ORDER BY builtin DESC, name COLLATE NOCASE, id;

-- ListGroupMembers lists every membership with the member's username, for
-- ListGroups to fold into its groups.
-- name: ListGroupMembers :many
SELECT
    group_members.group_id,
    users.id AS user_id,
    users.username
FROM
    group_members
    JOIN users ON users.id = group_members.user_id
ORDER BY
    users.username;

-- name: GetGroup :one
SELECT * FROM groups WHERE id = ? LIMIT 1;

-- name: CreateGroup :one
INSERT INTO groups (name) VALUES (?) RETURNING *;

-- name: RenameGroup :one
UPDATE groups SET name = ? WHERE id = ? AND builtin = 0 RETURNING *;

-- DeleteGroup drops a group; ON DELETE CASCADE drops its members and grants.
-- name: DeleteGroup :execrows
DELETE FROM groups WHERE id = ? AND builtin = 0;

-- AddGroupMember puts an account in a group. Adding a member again changes
-- nothing and reports no rows.
-- name: AddGroupMember :execrows
INSERT INTO group_members (group_id, user_id) VALUES (?, ?) ON CONFLICT DO NOTHING;

-- name: RemoveGroupMember :execrows
DELETE FROM group_members WHERE group_id = ? AND user_id = ?;

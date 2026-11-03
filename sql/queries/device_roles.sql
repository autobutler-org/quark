-- name: GetDeviceRole :one
SELECT role FROM device_roles WHERE device_serial = sqlc.arg(device_serial) LIMIT 1;

-- name: GetAllDeviceRoles :many
SELECT device_serial, role FROM device_roles;

-- name: UpsertDeviceRole :exec
INSERT INTO device_roles (device_serial, role, updated_at)
VALUES (sqlc.arg(device_serial), sqlc.arg(role), strftime('%Y-%m-%d %H:%M:%f', 'now'))
ON CONFLICT(device_serial) DO UPDATE SET
    role = excluded.role,
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now');

-- name: ClearDefaultStorageRole :exec
UPDATE device_roles SET role = 'unassigned', updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE role = 'default-storage';

-- name: DeleteDeviceRole :exec
DELETE FROM device_roles WHERE device_serial = sqlc.arg(device_serial);

package deviceutil

import (
	"context"

	"github.com/autobutler-org/quark/internal/db"
)

// DefaultStorageSerialParams looks up the drive holding the default-storage
// role.
type DefaultStorageSerialParams struct {
	// Ctx bounds the database read.
	Ctx context.Context
	// Database holds the roles. Nil reports no default-storage drive.
	Database *db.DatabaseSqlc
}

// DefaultStorageSerialResult names the default-storage drive.
type DefaultStorageSerialResult struct {
	// Serial is the drive's serial, empty when no drive holds the role or the
	// internal drive does. Live sync mirrors the internal drive onto this
	// drive and nothing else.
	Serial string
}

// DefaultStorageSerial returns the serial of the drive holding the
// default-storage role.
func DefaultStorageSerial(params DefaultStorageSerialParams) (DefaultStorageSerialResult, error) {
	if params.Database == nil {
		return DefaultStorageSerialResult{}, nil
	}
	roles, err := params.Database.Queries.GetAllDeviceRoles(params.Ctx)
	if err != nil {
		return DefaultStorageSerialResult{}, err
	}
	for _, r := range roles {
		if r.Role == "default-storage" {
			return DefaultStorageSerialResult{Serial: r.DeviceSerial}, nil
		}
	}
	return DefaultStorageSerialResult{}, nil
}

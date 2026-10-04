package deviceutil

import (
	"context"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// Connected devices are the HTTP peers behind /api/v0/devices, one
// connected_devices row per (IP address, User-Agent), not storage. Every
// request upserts a row, so without a bound one client cycling its
// User-Agent, or a crowd of clients, would grow the table forever (#2756).
const (
	// MaxConnectedDevices is how many peers the table holds, the most
	// recently seen kept.
	MaxConnectedDevices = 500
	// ConnectedDeviceMaxAge is how long a peer that stopped talking to the
	// appliance stays listed.
	ConnectedDeviceMaxAge = 30 * 24 * time.Hour
)

// RecordConnectedDeviceParams names the peer behind one request.
type RecordConnectedDeviceParams struct {
	Database  *db.DatabaseSqlc
	IPAddress string
	UserAgent string
}

// RecordConnectedDeviceResult reports what RecordConnectedDevice changed.
type RecordConnectedDeviceResult struct {
	// New is true when the peer had no row before this request.
	New bool
	// Pruned is how many rows a new peer pushed out.
	Pruned int64
}

// RecordConnectedDevice upserts the peer's row. A new row can take the table past
// MaxConnectedDevices, so a new peer prunes; a returning one, which is
// almost every request, costs the upsert alone.
func RecordConnectedDevice(ctx context.Context, params RecordConnectedDeviceParams) (RecordConnectedDeviceResult, error) {
	row, err := params.Database.Queries.UpsertConnectedDevice(ctx, db.UpsertConnectedDeviceParams{
		IpAddress: params.IPAddress,
		UserAgent: params.UserAgent,
	})
	if err != nil {
		return RecordConnectedDeviceResult{}, fmt.Errorf("record connected device: %w", err)
	}
	if row.RequestCount > 1 {
		return RecordConnectedDeviceResult{}, nil
	}
	pruned, err := PruneConnectedDevices(ctx, PruneConnectedDevicesParams{Database: params.Database})
	return RecordConnectedDeviceResult{New: true, Pruned: pruned.Removed}, err
}

// PruneConnectedDevicesParams configures PruneConnectedDevices.
type PruneConnectedDevicesParams struct {
	Database *db.DatabaseSqlc
	// Now is the clock the max age is measured from. Zero means time.Now.
	Now time.Time
}

// PruneConnectedDevicesResult reports how many rows PruneConnectedDevices deleted.
type PruneConnectedDevicesResult struct {
	Removed int64
}

// PruneConnectedDevices deletes peers not seen for ConnectedDeviceMaxAge and every peer past
// the MaxConnectedDevices most recently seen. The list is an admin view with
// no event of its own, so nothing is published.
func PruneConnectedDevices(ctx context.Context, params PruneConnectedDevicesParams) (PruneConnectedDevicesResult, error) {
	now := params.Now
	if now.IsZero() {
		now = time.Now()
	}
	removed, err := params.Database.Queries.PruneConnectedDevices(ctx, db.PruneConnectedDevicesParams{
		Cutoff: now.Add(-ConnectedDeviceMaxAge),
		Keep:   MaxConnectedDevices,
	})
	if err != nil {
		return PruneConnectedDevicesResult{}, fmt.Errorf("prune connected devices: %w", err)
	}
	return PruneConnectedDevicesResult{Removed: removed}, nil
}

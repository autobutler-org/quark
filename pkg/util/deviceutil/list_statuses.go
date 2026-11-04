package deviceutil

import (
	"context"
	"sync"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ListStatusesParams reports every detected device with the display name and
// role the database holds for it.
type ListStatusesParams struct {
	// Ctx bounds the database reads.
	Ctx context.Context
	// Storage detects the devices.
	Storage *storageutil.StorageService
	// Database holds the names and roles to overlay. Nil leaves the detector's
	// own names in place and reports no roles at all.
	Database *db.DatabaseSqlc
	// Health, when set, reports a drive's verdict instead of reading SMART.
	// Tests pass a fake. Nil reads through storageutil. A missing tool or a
	// failed read is an Unknown verdict and does not fail the list.
	Health func(context.Context, storageutil.Device) *storageutil.DiskHealth
	// Registry is the VFS registry file operations read. When an enabled
	// external drive has no files namespace, ListStatuses invalidates the
	// device cache so the OnDevicesChanged listener can register it before
	// the client treats the drive as an upload target (#3957). Nil skips that.
	Registry vfs.Registry
}

// ListStatusesResult carries the assembled statuses.
type ListStatusesResult struct {
	Statuses []*storageutil.DeviceStatus
}

// ListStatuses assembles the device list the storage UI renders. A database
// that cannot be read is not an error: the statuses still describe the
// hardware, which is the half a client cannot get anywhere else.
func ListStatuses(params ListStatusesParams) (ListStatusesResult, error) {
	statuses, err := params.Storage.GetDeviceStatuses()
	if err != nil {
		return ListStatusesResult{}, err
	}
	adoptUnregisteredDevices(params.Storage, params.Registry, statuses)

	// Overlay display names and roles from DB, keyed by device serial.
	if params.Database != nil {
		ctx := params.Ctx

		nameMap := make(map[string]string)
		if names, err := params.Database.Queries.GetAllDeviceNames(ctx); err == nil {
			for _, n := range names {
				nameMap[n.DeviceSerial] = n.DisplayName
			}
		}

		roleMap := make(map[string]string)
		if roles, err := params.Database.Queries.GetAllDeviceRoles(ctx); err == nil {
			for _, r := range roles {
				roleMap[r.DeviceSerial] = r.Role
			}
		}

		for i := range statuses {
			serial := ""
			if statuses[i].UsbInfo != nil {
				serial = statuses[i].UsbInfo.GetSerial()
			}
			if name, ok := nameMap[serial]; ok {
				statuses[i].Name = name
			}
			if role, ok := roleMap[serial]; ok {
				statuses[i].Role = role
			} else {
				statuses[i].Role = RoleUnassigned
			}
		}
	}

	fillDriveHealth(params.Ctx, statuses, params.Health)
	return ListStatusesResult{Statuses: statuses}, nil
}

// adoptUnregisteredDevices makes an enabled external drive that the registry
// has no files namespace for ready before this list is returned. The Files
// page reads the list and then uploads, and the upload 404s when the
// namespace was never registered (#3957). InvalidateDeviceCache runs the
// OnDevicesChanged listener, which syncs namespaces. A list that already
// matches does not invalidate, so a steady poll keeps the device cache.
func adoptUnregisteredDevices(storage *storageutil.StorageService, registry vfs.Registry, statuses []*storageutil.DeviceStatus) {
	if storage == nil || registry == nil {
		return
	}
	for _, status := range statuses {
		if status.IsInternal || !status.IsEnabled || status.UsbInfo == nil {
			continue
		}
		serial := status.UsbInfo.GetSerial()
		if serial == "" {
			continue
		}
		if _, ok := registry.Get(vfs.FilesNamespace(serial)); ok {
			continue
		}
		storage.InvalidateDeviceCache()
		return
	}
}

// fillDriveHealth sets Health on every status. A nil reader result, or a nil
// Health func that cannot read SMART, becomes Unknown and never Healthy.
// WorseThanDefault is set when a drive's verdict is worse than the current
// default-storage drive.
func fillDriveHealth(ctx context.Context, statuses []*storageutil.DeviceStatus, read func(context.Context, storageutil.Device) *storageutil.DiskHealth) {
	if ctx == nil {
		ctx = context.Background()
	}
	healths := make([]*storageutil.DiskHealth, len(statuses))
	if read != nil {
		for i, status := range statuses {
			healths[i] = read(ctx, status.Device)
		}
	} else {
		var wg sync.WaitGroup
		for i, status := range statuses {
			wg.Add(1)
			go func(i int, device storageutil.Device) {
				defer wg.Done()
				healths[i] = storageutil.CachedDriveHealth(ctx, device.DevicePath)
			}(i, status.Device)
		}
		wg.Wait()
	}

	defaultRank := -1
	defaultSerial := ""
	haveDefault := false
	for i, status := range statuses {
		health := healths[i]
		if health == nil {
			unknown := storageutil.UnknownDiskHealth()
			health = &unknown
		}
		copied := *health
		status.Health = &copied
		if status.Role == "default-storage" {
			defaultRank = storageutil.HealthRank(copied.Verdict)
			defaultSerial = deviceSerial(status.Device)
			haveDefault = true
		}
	}
	if !haveDefault {
		return
	}
	for _, status := range statuses {
		if deviceSerial(status.Device) == defaultSerial {
			continue
		}
		if storageutil.HealthRank(status.Health.Verdict) > defaultRank {
			status.Health.WorseThanDefault = true
		}
	}
}

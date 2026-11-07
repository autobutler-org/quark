package deviceutil

import (
	"context"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

const (
	// ReplaceSoonAcknowledgment is the error when a Replace soon drive is
	// given default storage or a backup role, or a backup is started onto it,
	// without acknowledgeHealth. Files already on the drive are left in place.
	ReplaceSoonAcknowledgment = "This drive should be replaced soon. Pass acknowledgeHealth to continue. Files already on the drive are left in place."
	// ReplaceSoonWorseAcknowledgment is that error when the drive would also
	// replace a healthier default-storage drive.
	ReplaceSoonWorseAcknowledgment = "This drive should be replaced soon, and it is in worse health than the current default storage. Pass acknowledgeHealth to continue. Files already on the drive are left in place."
)

// AcknowledgmentRequiredError is a Replace soon drive the caller has not
// confirmed. The handler answers it with 409.
type AcknowledgmentRequiredError struct {
	// Stronger is true when this assigns default storage and the target is in
	// worse health than the drive that holds it now.
	Stronger bool
}

func (e *AcknowledgmentRequiredError) Error() string {
	if e.Stronger {
		return ReplaceSoonWorseAcknowledgment
	}
	return ReplaceSoonAcknowledgment
}

// BackupHealthParams gates starting a snapshot backup onto a Replace soon drive.
type BackupHealthParams struct {
	Ctx context.Context
	// Storage lists connected devices. Nil skips the check.
	Storage *storageutil.StorageService
	// Serial is the backup target.
	Serial string
	// AcknowledgeHealth lets the backup proceed onto a Replace soon drive.
	// Files already on the drive are left in place.
	AcknowledgeHealth bool
	// Health, when set, reports a verdict instead of reading SMART. Tests use it.
	Health func(storageutil.Device) *storageutil.DiskHealth
}

// RefuseReplaceSoonTarget reports an acknowledgment error when serial is a
// connected Replace soon drive and AcknowledgeHealth is false. An empty
// serial is the internal drive. Watch and Unknown do not block. A drive that
// is not connected is left for the backup itself to reject.
func RefuseReplaceSoonTarget(params BackupHealthParams) error {
	if params.Storage == nil {
		return nil
	}
	statuses, err := params.Storage.GetDeviceStatuses()
	if err != nil {
		return err
	}
	device, found := deviceBySerial(statuses, params.Serial)
	if !found {
		return nil
	}
	return refuseReplaceSoon(healthFor(params.Ctx, params.Health, device), params.AcknowledgeHealth, false)
}

func refuseReplaceSoon(health *storageutil.DiskHealth, acknowledge, stronger bool) error {
	if health == nil || health.Verdict != storageutil.HealthReplaceSoon || acknowledge {
		return nil
	}
	return &AcknowledgmentRequiredError{Stronger: stronger}
}

func healthFor(ctx context.Context, read func(storageutil.Device) *storageutil.DiskHealth, device storageutil.Device) *storageutil.DiskHealth {
	if read != nil {
		return read(device)
	}
	return storageutil.CachedDriveHealth(ctx, device.DevicePath)
}

func verdictOf(health *storageutil.DiskHealth) string {
	if health == nil || health.Verdict == "" {
		return storageutil.HealthUnknown
	}
	return health.Verdict
}

// deviceSerial is the serial a role row is keyed by. The internal drive's is empty.
func deviceSerial(device storageutil.Device) string {
	if device.IsInternal || device.UsbInfo == nil {
		return ""
	}
	return device.UsbInfo.GetSerial()
}

// deviceBySerial finds the connected device a role serial names. An empty
// serial is the internal drive only.
func deviceBySerial(statuses []*storageutil.DeviceStatus, serial string) (storageutil.Device, bool) {
	for _, status := range statuses {
		if serial == "" {
			if status.IsInternal {
				return status.Device, true
			}
			continue
		}
		if status.UsbInfo != nil && status.UsbInfo.GetSerial() == serial {
			return status.Device, true
		}
	}
	return storageutil.Device{}, false
}

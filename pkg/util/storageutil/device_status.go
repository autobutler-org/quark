package storageutil

// DeviceStatus represents the status of a storage device, including whether it's
// enabled for Quark file management
type DeviceStatus struct {
	Device
	IsEnabled bool             `json:"isEnabled"`
	DataDir   string           `json:"dataDir,omitempty"`
	FilesDir  string           `json:"filesDir,omitempty"`
	Role      string           `json:"role"`
	DiskProbe *DiskProbeResult `json:"diskProbe,omitempty"` // nil until probed
	// Health is the drive's SMART verdict. It is nil until a caller reads it.
	// The device list fills it; a failed read is Unknown, never Healthy.
	Health *DiskHealth `json:"health,omitempty"`
	// ActiveBackupJobID is the snapshot backup pending or running onto this
	// drive, for its status at /storage/devices/snapshot-backup/status/{jobId}.
	// Only a backup drive has one.
	ActiveBackupJobID string `json:"activeBackupJobId,omitempty"`
}

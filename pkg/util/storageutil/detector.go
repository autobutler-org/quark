package storageutil

// Detector interface for cross-platform storage detection
type Detector interface {
	DetectDevices() ([]Device, error)
}

// rootDetector is a Detector with a cheap path for file requests: the same
// devices as DetectDevices, but only DevicePath, MountPoint, IsInternal and
// UsbInfo are guaranteed. A Detector without it (a test fake) falls back to
// DetectDevices.
type rootDetector interface {
	DetectRoots() ([]Device, error)
}

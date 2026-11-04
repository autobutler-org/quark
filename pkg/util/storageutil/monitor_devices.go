package storageutil

// externalMountedUsbDevices is the mounted external volumes in devices, as
// the USB devices usbDeviceMonitor compares between polls. The serial is
// the one the detector published. On macOS that is the volume UUID. An
// internal volume, or one with no serial or no mount, is left out.
func externalMountedUsbDevices(devices []Device) []UsbDevice {
	out := make([]UsbDevice, 0)
	for _, device := range devices {
		if device.IsInternal || device.MountPoint == "" || device.UsbInfo == nil {
			continue
		}
		serial := device.UsbInfo.GetSerial()
		if serial == "" {
			continue
		}
		mountPath := device.UsbInfo.GetMountPath()
		if mountPath == "" {
			mountPath = device.MountPoint
		}
		out = append(out, &usbDevice{
			Path:      device.DevicePath,
			Serial:    serial,
			MountPath: mountPath,
			Product:   device.UsbInfo.GetProduct(),
		})
	}
	return out
}

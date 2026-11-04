package storageutil

import "testing"

// TestExternalMountedUsbDevices is the set the macOS USB monitor compares
// between polls (#3957). An internal volume and a volume with no serial stay
// out. A volume whose USB descriptor has no mount path still counts, using
// the mount the detector reported.
func TestExternalMountedUsbDevices(t *testing.T) {
	got := externalMountedUsbDevices([]Device{
		{
			Name: "Internal", MountPoint: "/", IsInternal: true, DevicePath: "/dev/disk1s1",
			UsbInfo: &usbDevice{Serial: "INTERNAL", MountPath: "/"},
		},
		{
			Name: "Quark", DevicePath: "/dev/disk12s1", MountPoint: "/Volumes/Quark",
			UsbInfo: &usbDevice{Serial: "UUID", MountPath: "/Volumes/Quark", Product: "Quark"},
		},
		{Name: "NoSerial", MountPoint: "/Volumes/Empty"},
		{Name: "Unmounted", DevicePath: "/dev/disk13", UsbInfo: &usbDevice{Serial: "GONE"}},
		{
			Name: "FromDf", DevicePath: "/dev/disk14s1", MountPoint: "/Volumes/FromDf",
			UsbInfo: &usbDevice{Serial: "DF-UUID"},
		},
	})
	if len(got) != 2 {
		t.Fatalf("got %d devices, want Quark and FromDf", len(got))
	}
	if got[0].GetSerial() != "UUID" || got[0].GetMountPath() != "/Volumes/Quark" || got[0].GetPath() != "/dev/disk12s1" || got[0].GetProduct() != "Quark" {
		t.Fatalf("Quark = serial %q mount %q path %q product %q", got[0].GetSerial(), got[0].GetMountPath(), got[0].GetPath(), got[0].GetProduct())
	}
	if got[1].GetSerial() != "DF-UUID" || got[1].GetMountPath() != "/Volumes/FromDf" || got[1].GetPath() != "/dev/disk14s1" {
		t.Fatalf("FromDf = serial %q mount %q path %q", got[1].GetSerial(), got[1].GetMountPath(), got[1].GetPath())
	}
}

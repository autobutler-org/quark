package storageutil

import "testing"

// #2047: the Devices page led with "Root Volume", which is what a Linux admin
// panel calls the disk it booted from and not what a household owner calls
// the storage inside their Quark.
func TestRootDeviceName(t *testing.T) {
	cases := []struct {
		name       string
		mountPoint string
		want       string
	}{
		{"the appliance's own root", "/", "Built-in storage"},
		{"an unset mount point", "", "Built-in storage"},
		{"a relative nothing", ".", "Built-in storage"},
		{"a named mount keeps its name", "/mnt/photos", "photos"},
		{"a trailing slash does not change the name", "/mnt/photos/", "photos"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := rootDeviceName(tc.mountPoint); got != tc.want {
				t.Errorf("rootDeviceName(%q) = %q, want %q", tc.mountPoint, got, tc.want)
			}
		})
	}
}

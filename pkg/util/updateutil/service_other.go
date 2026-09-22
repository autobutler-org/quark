//go:build !linux

package updateutil

// RunningAsInstalledService is false off Linux: only `quark install` on Linux
// sets up the systemd service.
func RunningAsInstalledService() bool {
	return false
}

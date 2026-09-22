//go:build !linux

package repairutil

// serviceReason: only a Linux Quark runs under the systemd unit that repairs.
func serviceReason() Reason {
	return ReasonUnsupportedOS
}

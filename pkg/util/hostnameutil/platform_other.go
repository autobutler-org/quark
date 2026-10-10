//go:build !linux

package hostnameutil

// unavailableReason: only a Linux Quark has systemd, sudoers and the helper.
func unavailableReason() Reason {
	return ReasonUnsupportedOS
}

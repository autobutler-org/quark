//go:build !linux

package sshutil

// unavailableReason: only a Linux Quark has sshd, systemd and the helper.
func unavailableReason() Reason {
	return ReasonUnsupportedOS
}

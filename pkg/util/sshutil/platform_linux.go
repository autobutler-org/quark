//go:build linux

package sshutil

import (
	"os"
	"os/user"
	"path/filepath"
	"strings"
)

const (
	sshdPath       = "/usr/sbin/sshd"
	serviceBinPath = "/opt/quark/bin/quark"
	passwdPath     = "/etc/passwd"
)

// unavailableReason checks, in the order to fix them, that this Quark is the
// installed service and that the host pieces SSH access needs are there.
func unavailableReason() Reason {
	if !runningAsInstalledService() {
		return ReasonNotService
	}
	if _, err := os.Stat(sshdPath); err != nil {
		return ReasonSSHDMissing
	}
	if _, err := os.Stat(HelperPath); err != nil {
		return ReasonHelperMissing
	}
	if !hasLoginShell(passwdPath, LoginUser) {
		return ReasonNoLoginShell
	}
	return ReasonNone
}

// runningAsInstalledService: started by systemd (which sets INVOCATION_ID), as
// the quark user, from the installed binary. Only then does the sudoers entry
// apply and the paths above belong to this Quark.
func runningAsInstalledService() bool {
	if os.Getenv("INVOCATION_ID") == "" {
		return false
	}
	if u, err := user.Current(); err != nil || u.Username != LoginUser {
		return false
	}
	exe, err := os.Executable()
	if err != nil {
		return false
	}
	resolved, err := filepath.EvalSymlinks(exe)
	return err == nil && resolved == serviceBinPath
}

// hasLoginShell reports whether username's shell in the passwd file at path
// lets a login through. nologin and false do not; an empty field means
// /bin/sh.
func hasLoginShell(path, username string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		fields := strings.Split(line, ":")
		if len(fields) != 7 || fields[0] != username {
			continue
		}
		switch filepath.Base(fields[6]) {
		case "nologin", "false":
			return false
		default:
			return true
		}
	}
	return false
}

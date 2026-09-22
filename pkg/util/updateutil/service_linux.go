//go:build linux

package updateutil

import (
	"os"
	"os/user"
	"path/filepath"
)

// serviceUser is the account the installed systemd unit runs Quark as.
const serviceUser = "quark"

// RunningAsInstalledService reports whether this process is the installed
// service: started by systemd (which sets INVOCATION_ID), as the quark user,
// from the binary in SelfUpdatableBinDir. Only then do the sudoers entries and
// the unit `quark install` writes apply to this Quark.
func RunningAsInstalledService() bool {
	if os.Getenv("INVOCATION_ID") == "" {
		return false
	}
	if u, err := user.Current(); err != nil || u.Username != serviceUser {
		return false
	}
	exe, err := os.Executable()
	if err != nil {
		return false
	}
	resolved, err := filepath.EvalSymlinks(exe)
	return err == nil && resolved == filepath.Join(SelfUpdatableBinDir, binaryName)
}

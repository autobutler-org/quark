// Package install sets Quark up as a systemd service on Linux, along with the root-owned helpers the service is
// allowed to call but not rewrite.
package install

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

// installSystemdService writes the unit and enables it. restart starts the
// service on the new unit; --system-only passes false, since it runs from the
// unit's own ExecStartPre and must never touch the run state (#2120).
func installSystemdService(restart bool) error {
	serviceFilePath := filepath.Join("/etc/systemd/system", systemdServiceName)
	changed, err := writeRootFileIfChanged(serviceFilePath, buildServiceFile(), 0o644)
	if err != nil {
		return fmt.Errorf("failed to write systemd service file: %w", err)
	}
	// /run/systemd/system exists only when systemd is the running init (the
	// sd_booted(3) check). Without it — an OS image build running `quark install`
	// in a chroot — there is no daemon to reload or start the service on, but
	// `systemctl enable` still works offline.
	_, err = os.Stat("/run/systemd/system")
	booted := err == nil
	// A reload during ExecStartPre does not disturb the start in progress:
	// systemd carries a running unit's position in its command list across a
	// reload. The new unit applies from the next start.
	if booted && changed {
		if err := exec.Command("systemctl", "daemon-reload").Run(); err != nil {
			return fmt.Errorf("failed to reload systemd daemon: %w", err)
		}
	}
	// Enable the service to start on boot
	if err := exec.Command("systemctl", "enable", strings.Split(systemdServiceName, ".")[0]).Run(); err != nil {
		return fmt.Errorf("failed to enable systemctl service: %w", err)
	}
	if !booted || !restart {
		return nil
	}
	// Start the service immediately
	if err := exec.Command("systemctl", "restart", strings.Split(systemdServiceName, ".")[0]).Run(); err != nil {
		return fmt.Errorf("failed to start systemctl service: %w", err)
	}
	return nil
}

func installPlistService() error {
	legacyFilePath := filepath.Join("/Library/LaunchDaemons", legacyPlistServiceName)
	if _, err := os.Stat(legacyFilePath); err == nil {
		// Unload fails when the service is already stopped, which is fine.
		_ = exec.Command("launchctl", "unload", legacyFilePath).Run()
		if err := os.Remove(legacyFilePath); err != nil {
			return fmt.Errorf("failed to remove legacy plist service file: %w", err)
		}
	}
	serviceFilePath := filepath.Join("/Library/LaunchDaemons", plistServiceName)
	if err := os.WriteFile(serviceFilePath, []byte(buildServiceFile()), 0644); err != nil {
		return fmt.Errorf("failed to write plist service file: %w", err)
	}
	if err := exec.Command("launchctl", "load", serviceFilePath).Run(); err != nil {
		return fmt.Errorf("failed to load plist service: %w", err)
	}
	return nil
}

const sudoersDropInPath = "/etc/sudoers.d/quark"

func createServiceUser() error {
	if _, err := user.Lookup(serviceUserName); err == nil {
		return nil
	}
	return exec.Command(
		"useradd",
		"--system",
		"--no-create-home",
		"--shell", serviceLoginShell,
		"--comment", "Quark service account",
		serviceUserName,
	).Run()
}

// createServiceDataDir makes the data directory and hands it to the service
// account. recursive also hands over everything inside it; --system-only skips
// that, since it runs on every start and the tree holds all user data and any
// mounted drives.
func createServiceDataDir(recursive bool) error {
	if err := os.MkdirAll(serviceDataDir, 0750); err != nil {
		return fmt.Errorf("failed to create service data dir: %w", err)
	}
	svcUser, err := user.Lookup(serviceUserName)
	if err != nil {
		return fmt.Errorf("failed to look up service user: %w", err)
	}
	if !recursive {
		uid, err := strconv.Atoi(svcUser.Uid)
		if err != nil {
			return fmt.Errorf("service user %q has a non-numeric uid %q: %w", serviceUserName, svcUser.Uid, err)
		}
		gid, err := strconv.Atoi(svcUser.Gid)
		if err != nil {
			return fmt.Errorf("service user %q has a non-numeric gid %q: %w", serviceUserName, svcUser.Gid, err)
		}
		return os.Chown(serviceDataDir, uid, gid)
	}
	return exec.Command("chown", "-R",
		fmt.Sprintf("%s:%s", svcUser.Uid, svcUser.Gid),
		serviceDataDir,
	).Run()
}

func installSudoersRule() error {
	_, err := writeRootFileIfChanged(sudoersDropInPath, sudoersContent(), 0o440)
	return err
}

// serviceGroupID returns the numeric gid the service runs as. An explicit
// quark group is preferred when one exists, since useradd's group handling
// varies by distribution; otherwise the service user's own primary group.
func serviceGroupID() (int, error) {
	if grp, err := user.LookupGroup(serviceGroupName); err == nil {
		if gid, err := strconv.Atoi(grp.Gid); err == nil {
			return gid, nil
		}
	}
	svcUser, err := user.Lookup(serviceUserName)
	if err != nil {
		return 0, fmt.Errorf("failed to look up service user %q: %w", serviceUserName, err)
	}
	gid, err := strconv.Atoi(svcUser.Gid)
	if err != nil {
		return 0, fmt.Errorf("service user %q has a non-numeric gid %q: %w", serviceUserName, svcUser.Gid, err)
	}
	return gid, nil
}

// installBinary places the binary somewhere the unprivileged service can
// replace it, and keeps legacyBinPath working as a symlink.
//
// Ownership is root:quark with the directory setgid and group-writable. Root
// still owns the files, so the service cannot tamper with the installed binary
// through the file itself — but it can create and rename within the directory,
// which is all replaceSelf needs (#1609).
func installBinary(executable string) error {
	gid, err := serviceGroupID()
	if err != nil {
		return err
	}

	if err := os.MkdirAll(serviceBinDir, 0775); err != nil {
		return fmt.Errorf("failed to create %s: %w", serviceBinDir, err)
	}
	// MkdirAll applies umask and ignores setgid, so set the mode explicitly.
	if err := os.Chmod(serviceBinDir, serviceBinDirMode); err != nil {
		return fmt.Errorf("failed to set permissions on %s: %w", serviceBinDir, err)
	}
	if err := os.Chown(serviceBinDir, 0, gid); err != nil {
		return fmt.Errorf("failed to set ownership on %s: %w", serviceBinDir, err)
	}

	// Skip the copy when already running from the install path — re-running
	// `quark install` to repair an existing install must not truncate the
	// binary it is reading from.
	if resolved, err := filepath.EvalSymlinks(executable); err != nil || resolved != serviceBinPath {
		if err := exec.Command("cp", "-v", executable, serviceBinPath).Run(); err != nil {
			return fmt.Errorf("failed to copy binary to %s: %w", serviceBinPath, err)
		}
	}
	if err := os.Chmod(serviceBinPath, binaryMode); err != nil {
		return fmt.Errorf("failed to set permissions on %s: %w", serviceBinPath, err)
	}
	// Root keeps ownership of the file itself; only the group is the service
	// account, and only the directory is group-writable.
	if err := os.Chown(serviceBinPath, 0, gid); err != nil {
		return fmt.Errorf("failed to set ownership on %s: %w", serviceBinPath, err)
	}

	return linkLegacyBinPath()
}

// linkLegacyBinPath keeps /usr/local/bin/quark resolving, as a symlink into
// serviceBinDir. Installs made before #1609 have a real binary there; it is
// replaced, since leaving it would shadow the updatable copy on PATH.
func linkLegacyBinPath() error {
	existing, err := os.Lstat(legacyBinPath)
	switch {
	case err == nil:
		if existing.Mode()&os.ModeSymlink != 0 {
			target, err := os.Readlink(legacyBinPath)
			if err == nil && target == serviceBinPath {
				return nil
			}
		}
		if err := os.Remove(legacyBinPath); err != nil {
			return fmt.Errorf("failed to replace %s: %w", legacyBinPath, err)
		}
	case !os.IsNotExist(err):
		return fmt.Errorf("failed to inspect %s: %w", legacyBinPath, err)
	}

	if err := os.MkdirAll(filepath.Dir(legacyBinPath), 0755); err != nil {
		return fmt.Errorf("failed to create %s: %w", filepath.Dir(legacyBinPath), err)
	}
	if err := os.Symlink(serviceBinPath, legacyBinPath); err != nil {
		return fmt.Errorf("failed to link %s -> %s: %w", legacyBinPath, serviceBinPath, err)
	}
	return nil
}

// Install sets Quark up as a system service. systemOnly is what the unit's
// ExecStartPre runs before every start (#2120): it reapplies the system setup
// — writing a file only when its content differs — and skips the binary copy
// and anything that would start, stop or restart the service.
func Install(systemOnly bool) error {
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get executable path: %w", err)
	}
	switch runtime.GOOS {
	case "linux":
		// The service account must exist before the binary is installed — the
		// install directory is group-owned by it.
		if err := createServiceUser(); err != nil {
			return fmt.Errorf("failed to create service user: %w", err)
		}
		if !systemOnly {
			if err := installBinary(executable); err != nil {
				return err
			}
		}
		if err := createServiceDataDir(!systemOnly); err != nil {
			return fmt.Errorf("failed to create service data directory: %w", err)
		}
		if err := installSudoersRule(); err != nil {
			return fmt.Errorf("failed to install sudoers rule: %w", err)
		}
		if err := ensureLoginShell(); err != nil {
			return fmt.Errorf("failed to give the service account a login shell: %w", err)
		}
		if err := installSSHHelper(); err != nil {
			return fmt.Errorf("failed to install the SSH access helper: %w", err)
		}
		if err := installSSHDropIn(); err != nil {
			return fmt.Errorf("failed to install the sshd drop-in: %w", err)
		}
		if err := installDNSSDService(); err != nil {
			return fmt.Errorf("failed to install the DNS-SD service file: %w", err)
		}
		if err := lockRoot(); err != nil {
			return fmt.Errorf("failed to lock the root password: %w", err)
		}
		return installSystemdService(!systemOnly)
	case "darwin": // coverage: ignore - Not run in CI
		if systemOnly {
			return fmt.Errorf("--system-only needs systemd; on macOS run `sudo quark install` instead")
		}
		if err := exec.Command("cp", "-v", executable, "/Applications/quark").Run(); err != nil {
			return fmt.Errorf("failed to copy binary to /Applications: %w", err)
		}
		return installPlistService()
	default:
		return fmt.Errorf("unsupported operating system: %s", runtime.GOOS)
	}
}

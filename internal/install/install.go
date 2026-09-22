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

func installSystemdService() error {
	serviceFilePath := filepath.Join("/etc/systemd/system", systemdServiceName)
	if err := os.WriteFile(serviceFilePath, []byte(buildServiceFile()), 0644); err != nil {
		return fmt.Errorf("failed to write systemd service file: %w", err)
	}
	// /run/systemd/system exists only when systemd is the running init (the
	// sd_booted(3) check). Without it — an OS image build running `quark install`
	// in a chroot — there is no daemon to reload or start the service on, but
	// `systemctl enable` still works offline.
	_, err := os.Stat("/run/systemd/system")
	booted := err == nil
	if booted {
		if err := exec.Command("systemctl", "daemon-reload").Run(); err != nil {
			return fmt.Errorf("failed to reload systemd daemon: %w", err)
		}
	}
	// Enable the service to start on boot
	if err := exec.Command("systemctl", "enable", strings.Split(systemdServiceName, ".")[0]).Run(); err != nil {
		return fmt.Errorf("failed to enable systemctl service: %w", err)
	}
	if !booted {
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
	return installNewsyslogConf()
}

// installNewsyslogConf gives the launchd daemon's log files a rotation policy.
// Without one they grow without bound, and a crash loop fills the error log
// fast: cobra prints its full usage text on every failed start (#2231).
func installNewsyslogConf() error {
	if err := os.MkdirAll(filepath.Dir(newsyslogConfPath), 0755); err != nil {
		return fmt.Errorf("failed to create %s: %w", filepath.Dir(newsyslogConfPath), err)
	}
	if err := os.WriteFile(newsyslogConfPath, []byte(newsyslogConfContent), 0644); err != nil {
		return fmt.Errorf("failed to write %s: %w", newsyslogConfPath, err)
	}
	return nil
}

// removeLegacyLogs deletes the unrotated files older installs wrote to. They
// are dead weight the moment the new service definition is in place, and the
// whole point of #2231 is that they can be large, so a reinstall that left them
// would not actually recover the disk.
//
// Failures are not fatal: the install has already succeeded by this point, and
// a leftover log is not worth failing it over.
func removeLegacyLogs() {
	for _, path := range legacyLogPaths {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			fmt.Printf("warning: could not remove the old log file %s: %v\n", path, err)
		}
	}
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

func createServiceDataDir() error {
	if err := os.MkdirAll(serviceDataDir, 0750); err != nil {
		return fmt.Errorf("failed to create service data dir: %w", err)
	}
	svcUser, err := user.Lookup(serviceUserName)
	if err != nil {
		return fmt.Errorf("failed to look up service user: %w", err)
	}
	return exec.Command("chown", "-R",
		fmt.Sprintf("%s:%s", svcUser.Uid, svcUser.Gid),
		serviceDataDir,
	).Run()
}

func installSudoersRule() error {
	return os.WriteFile(sudoersDropInPath, []byte(sudoersContent()), 0440)
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

func Install() error {
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
		if err := installBinary(executable); err != nil {
			return err
		}
		if err := createServiceDataDir(); err != nil {
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
		if err := installSystemdService(); err != nil {
			return err
		}
		removeLegacyLogs()
		return nil
	case "darwin": // coverage: ignore - Not run in CI
		if err := exec.Command("cp", "-v", executable, "/Applications/quark").Run(); err != nil {
			return fmt.Errorf("failed to copy binary to /Applications: %w", err)
		}
		if err := installPlistService(); err != nil {
			return err
		}
		removeLegacyLogs()
		return nil
	default:
		return fmt.Errorf("unsupported operating system: %s", runtime.GOOS)
	}
}

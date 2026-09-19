package install

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/sshutil"
)

const (
	// sshdDropInDir is where Debian's sshd_config includes drop-ins from, at
	// the top of the file. sshd keeps the first value it reads for a keyword,
	// so drop-ins win over the main file, and among drop-ins the one sorting
	// first wins. The 00- prefix puts Quark's first.
	sshdDropInDir  = "/etc/ssh/sshd_config.d"
	sshdDropInPath = sshdDropInDir + "/00-quark.conf"

	// sshdDropInContent refuses root and everyone but quark, and points sshd
	// at the key file the service manages (#2131). Password login is allowed
	// for quark, and only works once an admin sets a password; keys always
	// work. The closing `Match all` ends the Match block, so nothing sshd
	// reads after this file lands inside it.
	sshdDropInContent = `# Written by quark install. Changes are overwritten on the next install.
PermitRootLogin no
AllowUsers ` + sshutil.LoginUser + `

Match User ` + sshutil.LoginUser + `
	AuthorizedKeysFile ` + sshutil.AuthorizedKeysPath + `
	PasswordAuthentication yes
Match all
`

	// sshAccessHelperContent is the root helper behind sshutil.HelperPath: the
	// only root actions the service may take for SSH, each fixed. The one
	// sudoers entry for it takes any argument, so the script validates its
	// own. It never takes a username: the password it sets is always quark's,
	// and it reads it from stdin so it is never on a command line.
	sshAccessHelperContent = `#!/bin/sh
# Written by quark install. Changes are overwritten on the next install.
# Turns SSH access to this Quark on and off, and sets or clears the password
# of the ` + sshutil.LoginUser + ` login account.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

LOGIN_USER=` + sshutil.LoginUser + `

usage() {
	echo "usage: $0 enable|disable|set-password|clear-password" >&2
	exit 2
}

[ "$#" -eq 1 ] || usage

# Some Debian releases run sshd through ssh.socket. The socket and the service
# both want port 22, so the socket is kept off and the service does the work.
stop_socket() {
	if systemctl cat ssh.socket >/dev/null 2>&1; then
		systemctl disable --now ssh.socket
	fi
}

case "$1" in
enable)
	stop_socket
	systemctl enable --now ssh.service
	if command -v ufw >/dev/null 2>&1; then
		ufw allow 22/tcp
	fi
	;;
disable)
	stop_socket
	systemctl disable --now ssh.service
	if command -v ufw >/dev/null 2>&1; then
		# The rule may already be gone.
		ufw delete allow 22/tcp || true
	fi
	;;
set-password)
	password=""
	IFS= read -r password || true
	if [ -z "$password" ]; then
		echo "no password on stdin" >&2
		exit 2
	fi
	printf '%s:%s\n' "$LOGIN_USER" "$password" | chpasswd
	;;
clear-password)
	# '*' rather than the '!' that locking writes: no password matches it,
	# and the account stays unlocked so keys keep working.
	usermod -p '*' "$LOGIN_USER"
	;;
*)
	usage
	;;
esac
`
)

// sudoersContent is the whole of /etc/sudoers.d/quark: the mount rule, and
// the one entry that lets the service run the SSH helper.
func sudoersContent() string {
	mountsDir := filepath.Join(serviceDataDir, "data", "mounts")
	return fmt.Sprintf(
		"%s ALL=(root) NOPASSWD: /bin/mount * %s/*, /bin/umount %s/*\n"+
			"%s ALL=(root) NOPASSWD: %s\n",
		serviceUserName, mountsDir, mountsDir,
		serviceUserName, sshutil.HelperPath,
	)
}

// installSSHHelper writes the helper root-owned, in a root-owned directory
// outside the self-updatable serviceBinDir, so the service can run it through
// sudo but never change it.
func installSSHHelper() error {
	dir := filepath.Dir(sshutil.HelperPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("failed to create %s: %w", dir, err)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		return fmt.Errorf("failed to set permissions on %s: %w", dir, err)
	}
	if err := os.Chown(dir, 0, 0); err != nil {
		return fmt.Errorf("failed to set ownership on %s: %w", dir, err)
	}
	return writeRootFile(sshutil.HelperPath, sshAccessHelperContent, 0o755)
}

// installSSHDropIn writes the sshd drop-in when sshd is installed, and has a
// running sshd pick it up. Without sshd there is nothing to configure; the
// admin page says to install it.
func installSSHDropIn() error {
	if _, err := os.Stat(sshdDropInDir); err != nil {
		return nil
	}
	if err := writeRootFile(sshdDropInPath, sshdDropInContent, 0o644); err != nil {
		return err
	}
	if _, err := os.Stat("/run/systemd/system"); err != nil {
		return nil
	}
	// A no-op when sshd is not running.
	if err := exec.Command("systemctl", "try-reload-or-restart", "ssh.service").Run(); err != nil {
		return fmt.Errorf("failed to reload sshd: %w", err)
	}
	return nil
}

// ensureLoginShell gives the service account a shell, which SSH needs to log
// it in. Accounts made before #2131 have nologin.
func ensureLoginShell() error {
	return exec.Command("usermod", "--shell", serviceLoginShell, serviceUserName).Run()
}

// writeRootFile replaces path atomically with a root-owned file.
func writeRootFile(path, content string, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+"-*")
	if err != nil {
		return fmt.Errorf("failed to create temp file for %s: %w", path, err)
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	if _, err := tmp.WriteString(content); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("failed to write %s: %w", path, err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("failed to write %s: %w", path, err)
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return fmt.Errorf("failed to set permissions on %s: %w", path, err)
	}
	if err := os.Chown(tmp.Name(), 0, 0); err != nil {
		return fmt.Errorf("failed to set ownership on %s: %w", path, err)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		return fmt.Errorf("failed to replace %s: %w", path, err)
	}
	return nil
}

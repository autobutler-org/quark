package aptutil

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

const unattendedUpgradesPackage = "unattended-upgrades"

// installUnitName names the transient unit that installs unattended-upgrades.
// A second start while it still runs fails to create it, which is harmless.
const installUnitName = "quark-install-unattended-upgrades"

// commandTimeout bounds one apt-mark or dpkg-query call. Configure runs in the
// service's ExecStartPre, so a stuck dpkg lock must not hold the start.
const commandTimeout = 60 * time.Second

// unattendedUpgradesConfig allows Debian's security pocket and nothing else
// (#2122). Armbian's repository is never an allowed origin, and its kernel and
// board packages are blacklisted as well as held (#2124). It never reboots: an
// unattended reboot of a home server cuts off uploads, backups and sessions,
// so a fix that needs a restart waits for the next one the user makes.
const unattendedUpgradesConfig = `// Written by quark install. Changes are overwritten on the next install.
// Debian security updates only (#2122); kernel and board packages stay held (#2124).
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";

#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
	"origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
	"origin=Debian,codename=${distro_codename},label=Debian-Security";
};

Unattended-Upgrade::Package-Blacklist {
	"^linux-image-";
	"^linux-dtb-";
	"^linux-headers-";
	"^linux-u-boot-";
	"^armbian-bsp-";
	"^armbian-firmware";
};

Unattended-Upgrade::Automatic-Reboot "false";
`

const holdReleasedMarker = `Written by quark release-kernel-hold. While this file exists, quark install
leaves the kernel and board packages unheld. Delete it to hold them again.
`

func (params ConfigureParams) withDefaults() resolvedParams {
	p := resolvedParams{root: params.Root, runner: params.Run, lookPath: params.LookPath}
	if p.root == "" {
		p.root = "/"
	}
	if p.runner == nil {
		p.runner = execRunner
	}
	if p.lookPath == nil {
		p.lookPath = exec.LookPath
	}
	return p
}

func execRunner(ctx context.Context, name string, args ...string) ([]byte, error) {
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return out, fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

func (p resolvedParams) path(path string) string {
	return filepath.Join(p.root, path)
}

func (p resolvedParams) run(name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), commandTimeout)
	defer cancel()
	return p.runner(ctx, name, args...)
}

// missingTool names the first apt or dpkg command the host lacks, or "".
func (p resolvedParams) missingTool() string {
	for _, tool := range []string{"apt-get", "apt-mark", "dpkg-query"} {
		if _, err := p.lookPath(tool); err != nil {
			return tool
		}
	}
	return ""
}

// installedPackages lists the packages dpkg has installed. Removed packages
// whose configuration files remain ("rc") are left out.
func (p resolvedParams) installedPackages() ([]string, error) {
	out, err := p.run("dpkg-query", "-W", "-f", "${db:Status-Abbrev} ${Package}\n")
	if err != nil {
		return nil, fmt.Errorf("list installed packages: %w", err)
	}
	var pkgs []string
	for line := range strings.Lines(string(out)) {
		fields := strings.Fields(line)
		if len(fields) == 2 && len(fields[0]) >= 2 && fields[0][1] == 'i' {
			pkgs = append(pkgs, fields[1])
		}
	}
	return pkgs, nil
}

func (p resolvedParams) heldPackages() ([]string, error) {
	out, err := p.run("apt-mark", "showhold")
	if err != nil {
		return nil, fmt.Errorf("list held packages: %w", err)
	}
	return strings.Fields(string(out)), nil
}

// queueInstall hands the unattended-upgrades install to a transient systemd
// unit rather than running apt-get here: at boot the network may not be up
// yet, and an apt-get waiting on it would hold the service start. Without a
// running systemd (an image build in a chroot) the install is left to the next
// start.
func (p resolvedParams) queueInstall() (bool, error) {
	if _, err := p.lookPath("systemd-run"); err != nil {
		return false, nil
	}
	// The sd_booted(3) check: no running systemd, no unit to hand it to.
	if _, err := os.Stat(p.path("/run/systemd/system")); err != nil {
		return false, nil
	}
	_, err := p.run("systemd-run",
		"--unit="+installUnitName, "--no-block", "--collect",
		"--property=After=network-online.target", "--property=Wants=network-online.target",
		"--setenv=DEBIAN_FRONTEND=noninteractive",
		"/bin/sh", "-c", "apt-get update && apt-get install -y --no-install-recommends "+unattendedUpgradesPackage)
	if err != nil {
		return false, fmt.Errorf("queue the %s install: %w", unattendedUpgradesPackage, err)
	}
	return true, nil
}

// boardPackages keeps the packages HeldPackagePrefixes names, sorted.
func boardPackages(pkgs []string) []string {
	var out []string
	for _, pkg := range pkgs {
		if slices.ContainsFunc(HeldPackagePrefixes, func(prefix string) bool { return strings.HasPrefix(pkg, prefix) }) {
			out = append(out, pkg)
		}
	}
	slices.Sort(out)
	return out
}

// writeFileIfChanged writes content to path only when it differs from what is
// there, and reports whether it wrote. The files are short and ours.
func writeFileIfChanged(path, content string, mode os.FileMode) (bool, error) {
	if current, err := os.ReadFile(path); err == nil && string(current) == content {
		return false, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, fmt.Errorf("create %s: %w", filepath.Dir(path), err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(content), mode); err != nil {
		return false, fmt.Errorf("write %s: %w", path, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return false, fmt.Errorf("replace %s: %w", path, err)
	}
	return true, nil
}

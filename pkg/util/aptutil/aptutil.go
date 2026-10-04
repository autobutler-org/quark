// Package aptutil keeps a Debian-based Quark patched without risking its boot.
// `quark install` calls it as root on every service start, so the setup is
// versioned with the code and reaches devices already in the field: Debian
// security updates install themselves through unattended-upgrades (#2122), and
// the kernel, bootloader and board-support packages are held at the version
// the device booted with, so neither unattended-upgrades nor a manual
// `apt upgrade` can move them (#2124).
package aptutil

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

const (
	// UnattendedUpgradesConfigPath is the apt drop-in that limits
	// unattended-upgrades to Debian's security pocket and turns it on. It
	// sorts after the package's own 50unattended-upgrades, so its #clear
	// directives drop the origins that file allows.
	UnattendedUpgradesConfigPath = "/etc/apt/apt.conf.d/52quark-unattended-upgrades"
	// HoldReleasedMarkerPath, while it exists, stops Configure from holding
	// the kernel and board packages. ReleaseHold writes it; deleting it puts
	// the hold back on the next service start.
	HoldReleasedMarkerPath = "/etc/quark/release-kernel-hold"
)

// HeldPackagePrefixes name the packages Configure holds: the kernel and its
// device trees and headers, the bootloader, Armbian's board-support packages
// and firmware. Whichever of them are installed are held, so no board is
// named here.
var HeldPackagePrefixes = []string{
	"linux-image-",
	"linux-dtb-",
	"linux-headers-",
	"linux-u-boot-",
	"armbian-bsp-",
	"armbian-firmware",
}

// Runner runs a command and returns its standard output. Tests pass a fake,
// so nothing they do reaches the real package database.
type Runner func(ctx context.Context, name string, args ...string) ([]byte, error)

// ConfigureParams configures Configure and ReleaseHold. Every field is
// optional; empty means the real system.
type ConfigureParams struct {
	// Root prefixes every file path written or read. Empty means "/".
	Root string
	// Run runs apt-mark, dpkg-query and systemd-run. Nil means os/exec.
	Run Runner
	// LookPath finds a command on PATH. Nil means exec.LookPath.
	LookPath func(string) (string, error)
}

// ConfigureResult reports what Configure did.
type ConfigureResult struct {
	// Skipped is true when the host has no apt or dpkg (macOS, a minimal
	// container); SkipReason says which tool was missing.
	Skipped    bool
	SkipReason string
	// ConfigChanged is true when the unattended-upgrades drop-in was written.
	ConfigChanged bool
	// InstallQueued is true when unattended-upgrades was missing and its
	// install was handed to a transient systemd unit.
	InstallQueued bool
	// Held lists the packages newly held by this run.
	Held []string
	// HoldReleased is true when HoldReleasedMarkerPath exists, so nothing
	// was held.
	HoldReleased bool
}

// ReleaseHoldResult reports what ReleaseHold did.
type ReleaseHoldResult struct {
	// Released lists the packages whose hold was removed.
	Released []string
}

// Configure writes the unattended-upgrades drop-in, queues the package's
// install when it is missing, and holds the installed kernel and board
// packages. It changes nothing that is already right, and skips everything,
// without error, on a host without apt. A failing step does not stop the
// others; their errors are joined.
func Configure(params ConfigureParams) (ConfigureResult, error) {
	p := params.withDefaults()
	if missing := p.missingTool(); missing != "" {
		return ConfigureResult{Skipped: true, SkipReason: missing + " is not installed"}, nil
	}
	var result ConfigureResult
	var errs []error

	changed, err := writeFileIfChanged(p.path(UnattendedUpgradesConfigPath), unattendedUpgradesConfig, 0o644)
	if err != nil {
		errs = append(errs, err)
	}
	result.ConfigChanged = changed

	installed, err := p.installedPackages()
	if err != nil {
		return result, errors.Join(append(errs, err)...)
	}
	if !slices.Contains(installed, unattendedUpgradesPackage) {
		queued, err := p.queueInstall()
		if err != nil {
			errs = append(errs, err)
		}
		result.InstallQueued = queued
	}

	if _, err := os.Stat(p.path(HoldReleasedMarkerPath)); err == nil {
		result.HoldReleased = true
		return result, errors.Join(errs...)
	}
	held, err := p.heldPackages()
	if err != nil {
		return result, errors.Join(append(errs, err)...)
	}
	var toHold []string
	for _, pkg := range boardPackages(installed) {
		if !slices.Contains(held, pkg) {
			toHold = append(toHold, pkg)
		}
	}
	if len(toHold) > 0 {
		if _, err := p.run("apt-mark", append([]string{"hold"}, toHold...)...); err != nil {
			errs = append(errs, fmt.Errorf("hold %s: %w", strings.Join(toHold, " "), err))
		} else {
			result.Held = toHold
		}
	}
	return result, errors.Join(errs...)
}

// ReleaseHold lifts the hold on the kernel and board packages and writes
// HoldReleasedMarkerPath so the next service start leaves them unheld. It is
// the deliberate step before moving a board to a newer kernel; deleting the
// marker restores the hold.
func ReleaseHold(params ConfigureParams) (ReleaseHoldResult, error) {
	p := params.withDefaults()
	if missing := p.missingTool(); missing != "" {
		return ReleaseHoldResult{}, fmt.Errorf("%s is not installed; there is no hold to release", missing)
	}
	if err := os.MkdirAll(filepath.Dir(p.path(HoldReleasedMarkerPath)), 0o755); err != nil {
		return ReleaseHoldResult{}, fmt.Errorf("create %s: %w", filepath.Dir(HoldReleasedMarkerPath), err)
	}
	if _, err := writeFileIfChanged(p.path(HoldReleasedMarkerPath), holdReleasedMarker, 0o644); err != nil {
		return ReleaseHoldResult{}, err
	}
	held, err := p.heldPackages()
	if err != nil {
		return ReleaseHoldResult{}, err
	}
	release := boardPackages(held)
	if len(release) == 0 {
		return ReleaseHoldResult{}, nil
	}
	if _, err := p.run("apt-mark", append([]string{"unhold"}, release...)...); err != nil {
		return ReleaseHoldResult{}, fmt.Errorf("unhold %s: %w", strings.Join(release, " "), err)
	}
	return ReleaseHoldResult{Released: release}, nil
}

// Package memutil sizes Quark's memory limits from the board's RAM (#2761). The Go runtime gets a soft limit, set
// by `quark serve`, so the heap collects near its live set instead of growing to twice it; the service's cgroup gets
// a systemd MemoryHigh and MemoryMax, written by `quark install`, so the kernel throttles and then stops Quark and
// its ffmpeg children before the whole board swaps or the OOM killer picks a victim.
package memutil

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

const (
	// GoLimitPercent of RAM is the Go runtime's soft memory limit. The rest
	// is for ffmpeg children (0.7–2.5 GiB for a transcode), the page cache
	// and the OS.
	GoLimitPercent = 60
	// MemoryHighPercent of RAM is where systemd starts throttling and
	// reclaiming from the service's cgroup, Quark and its children together.
	MemoryHighPercent = 80
	// MemoryMaxPercent of RAM is the cgroup's hard ceiling: past it the
	// kernel OOM-kills inside the service, not elsewhere on the board.
	MemoryMaxPercent = 90

	// DropInPath is the systemd drop-in InstallDropIn writes.
	DropInPath = "/etc/systemd/system/quark.service.d/50-memory.conf"
)

// Limits are the memory limits for a board, in bytes.
type Limits struct {
	GoLimit    uint64
	MemoryHigh uint64
	MemoryMax  uint64
}

// LimitsFor derives the limits from a board's total RAM.
func LimitsFor(totalRAM uint64) Limits {
	return Limits{
		GoLimit:    totalRAM * GoLimitPercent / 100,
		MemoryHigh: totalRAM * MemoryHighPercent / 100,
		MemoryMax:  totalRAM * MemoryMaxPercent / 100,
	}
}

// Runner runs a command and returns its standard output. Tests pass a fake,
// so nothing they do reaches the real service manager.
type Runner func(ctx context.Context, name string, args ...string) ([]byte, error)

// ApplyGoLimitParams configures ApplyGoLimit. Every field is optional; nil
// means the real system.
type ApplyGoLimitParams struct {
	// TotalRAM reports the board's RAM in bytes. Nil means gopsutil.
	TotalRAM func() (uint64, error)
	// Getenv reads the environment. Nil means os.Getenv.
	Getenv func(string) string
	// SetMemoryLimit sets the runtime's limit. Nil means
	// debug.SetMemoryLimit.
	SetMemoryLimit func(int64) int64
}

// ApplyGoLimitResult reports the limit in force.
type ApplyGoLimitResult struct {
	// FromEnv is true when GOMEMLIMIT was set, so the runtime's own parse of
	// it stands and nothing was changed.
	FromEnv bool
	// Limit is the limit set, in bytes; zero when FromEnv.
	Limit int64
	// TotalRAM is the RAM the limit was derived from.
	TotalRAM uint64
}

// ApplyGoLimit sets the Go runtime's soft memory limit to GoLimitPercent of
// RAM, unless GOMEMLIMIT is set, which wins. On an error nothing is changed and
// the runtime keeps its default of no limit.
func ApplyGoLimit(params ApplyGoLimitParams) (ApplyGoLimitResult, error) {
	p := params.withDefaults()
	if p.Getenv("GOMEMLIMIT") != "" {
		return ApplyGoLimitResult{FromEnv: true}, nil
	}
	total, err := p.TotalRAM()
	if err != nil {
		return ApplyGoLimitResult{}, fmt.Errorf("read total RAM: %w", err)
	}
	limit := int64(LimitsFor(total).GoLimit)
	p.SetMemoryLimit(limit)
	return ApplyGoLimitResult{Limit: limit, TotalRAM: total}, nil
}

// InstallDropInParams configures InstallDropIn. Every field is optional;
// empty means the real system.
type InstallDropInParams struct {
	// Root prefixes every path read or written. Empty means "/".
	Root string
	// Run runs systemctl. Nil means os/exec.
	Run Runner
	// TotalRAM reports the board's RAM in bytes. Nil means gopsutil.
	TotalRAM func() (uint64, error)
}

// InstallDropInResult reports what InstallDropIn did.
type InstallDropInResult struct {
	// Skipped is true when systemd is not the running init; SkipReason says
	// so.
	Skipped    bool
	SkipReason string
	// Changed is true when the drop-in was written and systemd reloaded.
	Changed bool
	// Limits are the limits the drop-in holds.
	Limits Limits
}

// InstallDropIn writes DropInPath with a MemoryHigh and MemoryMax derived from
// this board's RAM, and reloads systemd when it changed. `quark install` runs
// it on every service start, so the ceiling follows a release that changes the
// fractions and a disk moved to a board with more RAM; with nothing changed it
// writes and runs nothing.
//
// It skips without error when systemd is not the running init: macOS, a
// container, or an OS image build in a chroot, whose RAM is the build host's.
// The first start on the board writes it then.
func InstallDropIn(params InstallDropInParams) (InstallDropInResult, error) {
	p := params.withDefaults()
	// /run/systemd/system exists only when systemd is the running init (the
	// sd_booted(3) check).
	if _, err := os.Stat(filepath.Join(p.root, "run/systemd/system")); err != nil {
		return InstallDropInResult{Skipped: true, SkipReason: "systemd is not running"}, nil
	}
	total, err := p.totalRAM()
	if err != nil {
		return InstallDropInResult{}, fmt.Errorf("read total RAM: %w", err)
	}
	limits := LimitsFor(total)
	result := InstallDropInResult{Limits: limits}
	changed, err := writeFileIfChanged(filepath.Join(p.root, DropInPath), dropInContent(total, limits), 0o644)
	if err != nil || !changed {
		return result, err
	}
	result.Changed = true
	ctx, cancel := context.WithTimeout(context.Background(), commandTimeout)
	defer cancel()
	if _, err := p.run(ctx, "systemctl", "daemon-reload"); err != nil {
		return result, fmt.Errorf("reload systemd: %w", err)
	}
	return result, nil
}

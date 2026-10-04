package memutil

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime/debug"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v4/mem"
)

// commandTimeout bounds the daemon-reload. InstallDropIn runs in the
// service's ExecStartPre, so a stuck systemctl must not hold the start.
const commandTimeout = 60 * time.Second

func (params ApplyGoLimitParams) withDefaults() ApplyGoLimitParams {
	if params.TotalRAM == nil {
		params.TotalRAM = totalRAM
	}
	if params.Getenv == nil {
		params.Getenv = os.Getenv
	}
	if params.SetMemoryLimit == nil {
		params.SetMemoryLimit = debug.SetMemoryLimit
	}
	return params
}

func (params InstallDropInParams) withDefaults() resolvedDropInParams {
	p := resolvedDropInParams{root: params.Root, run: params.Run, totalRAM: params.TotalRAM}
	if p.root == "" {
		p.root = "/"
	}
	if p.run == nil {
		p.run = execRunner
	}
	if p.totalRAM == nil {
		p.totalRAM = totalRAM
	}
	return p
}

// totalRAM reads the board's RAM through gopsutil, which builds for every
// target the backend is cross-compiled for, so no build tags are needed.
func totalRAM() (uint64, error) {
	v, err := mem.VirtualMemory()
	if err != nil {
		return 0, err
	}
	if v.Total == 0 {
		return 0, fmt.Errorf("total RAM reads as zero")
	}
	return v.Total, nil
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

// dropInContent is the drop-in for a board with total bytes of RAM. The
// values are bytes, which systemd takes without a suffix.
func dropInContent(total uint64, limits Limits) string {
	return fmt.Sprintf(`# Written by quark install from this board's %d MiB of RAM, and rewritten on
# every start (#2761). Changes are overwritten.
[Service]
MemoryHigh=%d
MemoryMax=%d
`, total>>20, limits.MemoryHigh, limits.MemoryMax)
}

// writeFileIfChanged writes content to path through a temporary file and a
// rename, and reports whether it wrote. A file already holding content is
// left alone.
func writeFileIfChanged(path, content string, mode os.FileMode) (bool, error) {
	// A few hundred bytes we wrote ourselves, not user content.
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

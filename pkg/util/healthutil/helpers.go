package healthutil

import (
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/load"
	"github.com/shirou/gopsutil/v4/mem"
	"github.com/shirou/gopsutil/v4/sensors"
)

// applyCPUThreshold implements the sustained-load rule: CPU must stay at or
// above CPUCriticalPercent for longer than CPUSustainedDuration before it
// alerts, so a brief spike does not mark the host unhealthy. Returns the
// updated "high since" marker — nil once CPU drops back below the limit.
func applyCPUThreshold(status *HealthStatus, cpuPercent float64, highSince *time.Time, now time.Time) *time.Time {
	if cpuPercent < CPUCriticalPercent {
		return nil
	}
	if highSince == nil {
		return &now
	}
	if now.Sub(*highSince) >= CPUSustainedDuration {
		status.Healthy = false
		status.Alerts = append(status.Alerts,
			fmt.Sprintf("CPU sustained above %.0f%% for >%s", CPUCriticalPercent, CPUSustainedDuration))
	}
	return highSince
}

// applyMemThreshold alerts when memory use reaches MemCriticalPercent.
func applyMemThreshold(status *HealthStatus, memPercent float64) {
	if memPercent >= MemCriticalPercent {
		status.Healthy = false
		status.Alerts = append(status.Alerts,
			fmt.Sprintf("Memory usage critical: %.1f%%", memPercent))
	}
}

// applyDiskThreshold alerts when use of the data directory's filesystem
// reaches DiskCriticalPercent.
func applyDiskThreshold(status *HealthStatus, diskPercent float64) {
	if diskPercent >= DiskCriticalPercent {
		status.Healthy = false
		status.Alerts = append(status.Alerts,
			fmt.Sprintf("Disk usage critical: %.1f%%", diskPercent))
	}
}

// applyTempThreshold alerts when the hottest thermal zone reaches
// TempCriticalCelsius (the Pi 5 throttle point).
func applyTempThreshold(status *HealthStatus, tempCelsius float64) {
	if tempCelsius >= TempCriticalCelsius {
		status.Healthy = false
		status.Alerts = append(status.Alerts,
			fmt.Sprintf("Temperature critical: %.1f°C", tempCelsius))
	}
}

// readHost samples the host through gopsutil. The caller holds c.mu, which
// guards cpuHighSince.
func (c *Collector) readHost() HealthStatus {
	status := HealthStatus{Healthy: true}
	status.Hostname, _ = os.Hostname()

	// CPU
	if cores, err := cpu.Percent(100*time.Millisecond, true); err == nil {
		status.CPUCorePercents = cores
	} else {
		slog.Warn("system metrics: cpu.Percent (per-core) failed", "err", err)
	}
	if agg, err := cpu.Percent(0, false); err == nil && len(agg) > 0 {
		status.CPUPercent = agg[0]
		c.cpuHighSince = applyCPUThreshold(&status, agg[0], c.cpuHighSince, time.Now())
	} else {
		slog.Warn("system metrics: cpu.Percent (aggregate) failed", "err", err)
	}

	// Memory
	if v, err := mem.VirtualMemory(); err == nil {
		status.MemPercent = v.UsedPercent
		status.MemUsedBytes = v.Used
		status.MemTotalBytes = v.Total
		applyMemThreshold(&status, v.UsedPercent)
	} else {
		slog.Warn("system metrics: mem.VirtualMemory failed", "err", err)
	}

	// Disk: the filesystem holding the data directory, the one the Devices
	// page sizes the internal device from, so the two agree when the data
	// directory is a mount of its own (#2467).
	if usage, err := disk.Usage(storageutil.DataFilesystemPath()); err == nil {
		status.DiskPercent = usage.UsedPercent
		status.DiskUsedBytes = usage.Used
		status.DiskTotalBytes = usage.Total
		applyDiskThreshold(&status, usage.UsedPercent)
	} else {
		slog.Warn("system metrics: disk.Usage failed", "err", err)
	}

	// Temperature (highest reading across all thermal zones)
	if temps, err := sensors.SensorsTemperatures(); err == nil {
		var maxTemp float64
		for _, t := range temps {
			if t.Temperature > maxTemp {
				maxTemp = t.Temperature
			}
		}
		status.TemperatureCelsius = maxTemp
		applyTempThreshold(&status, maxTemp)
	}
	// Temperature failure is non-fatal: not available in all environments.

	// Load averages — informational only, no alert threshold
	if avg, err := load.Avg(); err != nil {
		slog.Warn("system metrics: load.Avg failed", "err", err)
	} else {
		_ = avg // available if callers want to extend HealthStatus later
	}

	return status
}

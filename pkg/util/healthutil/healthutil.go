// Package healthutil provides gopsutil-based host hardware health metrics,
// and the check that the server's database answers.
// It is intentionally free of OTel dependencies so the health endpoint
// has no dependency on any telemetry backend.
package healthutil

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"slices"
	"sync"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

const (
	// Alert thresholds
	TempCriticalCelsius  = 80.0 // Pi 5 throttle point
	CPUCriticalPercent   = 90.0
	MemCriticalPercent   = 95.0
	DiskCriticalPercent  = 90.0
	CPUSustainedDuration = 60 * time.Second
)

// HealthStatus summarizes the current alert state for the health indicator.
type HealthStatus struct {
	Healthy            bool
	Alerts             []string
	CPUPercent         float64
	CPUCorePercents    []float64 // per-core utilization
	MemPercent         float64
	MemUsedBytes       uint64
	MemTotalBytes      uint64
	DiskPercent        float64
	DiskUsedBytes      uint64
	DiskTotalBytes     uint64
	TemperatureCelsius float64 // highest thermal zone reading, 0 if unavailable
	Hostname           string  // the host's name, empty if unavailable
}

// Collector samples host hardware metrics for the health endpoint.
// One Collector serves every /health request, so its state is behind mu.
type Collector struct {
	mu           sync.Mutex
	cpuHighSince *time.Time
	sample       HealthStatus
	sampledAt    time.Time
	// now and read stand in for the clock and the host in tests; nil means
	// time.Now and readHost.
	now  func() time.Time
	read func() HealthStatus
}

// sampleTTL is how long a read of the host is served. Clients poll every
// 15 s, so a few seconds is never stale to them.
const sampleTTL = 5 * time.Second

// Register creates a new Collector. Call this once at startup.
func Register() (*Collector, error) {
	return &Collector{}, nil
}

// The applyXThreshold helpers hold the alerting rules, split out from the
// gopsutil sampling in readHost so they can be tested without a machine
// that is genuinely at 95% memory or 80°C. Each mutates status in place,
// clearing Healthy and appending an alert when its limit is breached.

// CurrentHealth returns the host's state, read at most once per sampleTTL.
// Every open Files page asks on each refresh, and a read sleeps 100 ms and
// walks sysfs, which the kernel serializes: read per call, a hundred clients
// queued for seconds (#2750). Callers that arrive during a read wait for it
// and share it.
func (c *Collector) CurrentHealth() HealthStatus {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now
	if c.now != nil {
		now = c.now
	}
	if c.sampledAt.IsZero() || now().Sub(c.sampledAt) >= sampleTTL {
		read := c.readHost
		if c.read != nil {
			read = c.read
		}
		c.sample = read()
		c.sampledAt = now()
	}
	status := c.sample
	status.Alerts = slices.Clone(status.Alerts)
	status.CPUCorePercents = slices.Clone(status.CPUCorePercents)
	return status
}

// databasePingTimeout bounds how long a health check waits on the database.
// One that has not answered a ping by now is down or unreachable.
const databasePingTimeout = 2 * time.Second

// CheckDatabase pings sqlDB, the server's database on either backend, and
// when it does not answer within databasePingTimeout clears status.Healthy
// and adds an alert naming the engine. It is read on every call, not cached
// with the host sample: a database that has gone away should show at once.
func CheckDatabase(ctx context.Context, sqlDB *sql.DB, status *HealthStatus) {
	ctx, cancel := context.WithTimeout(ctx, databasePingTimeout)
	defer cancel()
	if err := sqlDB.PingContext(ctx); err != nil {
		name := backendNames[db.BackendOf(sqlDB)]
		slog.Warn("health: the database is not answering", "backend", name, "error", err)
		status.Healthy = false
		status.Alerts = append(status.Alerts, fmt.Sprintf("The %s database is not answering", name))
	}
}

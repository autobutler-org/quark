package healthutil

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// countingCollector returns a Collector whose host reads are counted and
// whose clock the test moves.
func countingCollector(clock *time.Time, reads *atomic.Int32) *Collector {
	return &Collector{
		now: func() time.Time { return *clock },
		read: func() HealthStatus {
			reads.Add(1)
			return HealthStatus{Healthy: true, CPUCorePercents: []float64{1, 2}}
		},
	}
}

// TestCurrentHealth_ReusesARecentSample pins that /health reads the host at
// most once per sampleTTL (#2750). Every Files refresh calls it, and a read
// sleeps 100 ms and walks sysfs, which the kernel serializes.
func TestCurrentHealth_ReusesARecentSample(t *testing.T) {
	clock := time.Unix(1_000, 0)
	var reads atomic.Int32
	c := countingCollector(&clock, &reads)

	c.CurrentHealth()
	c.CurrentHealth()
	clock = clock.Add(sampleTTL - time.Millisecond)
	c.CurrentHealth()
	if got := reads.Load(); got != 1 {
		t.Fatalf("host read %d times inside one window, want 1", got)
	}
	clock = clock.Add(time.Millisecond)
	c.CurrentHealth()
	if got := reads.Load(); got != 2 {
		t.Fatalf("host read %d times after the window passed, want 2", got)
	}
}

// TestCurrentHealth_ConcurrentCallersShareOneRead pins that callers arriving
// while a read is running wait for it rather than starting their own.
func TestCurrentHealth_ConcurrentCallersShareOneRead(t *testing.T) {
	clock := time.Unix(1_000, 0)
	var reads atomic.Int32
	c := countingCollector(&clock, &reads)
	release := make(chan struct{})
	read := c.read
	c.read = func() HealthStatus {
		<-release
		return read()
	}

	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c.CurrentHealth()
		}()
	}
	close(release)
	wg.Wait()
	if got := reads.Load(); got != 1 {
		t.Fatalf("10 concurrent callers read the host %d times, want 1", got)
	}
}

// TestCurrentHealth_CallersGetTheirOwnSlices pins that a caller changing what
// it got back cannot change the sample the next caller is served.
func TestCurrentHealth_CallersGetTheirOwnSlices(t *testing.T) {
	clock := time.Unix(1_000, 0)
	var reads atomic.Int32
	c := countingCollector(&clock, &reads)

	first := c.CurrentHealth()
	first.CPUCorePercents[0] = 99
	if second := c.CurrentHealth(); second.CPUCorePercents[0] != 1 {
		t.Fatalf("second caller saw %v, want the sample unchanged", second.CPUCorePercents)
	}
}

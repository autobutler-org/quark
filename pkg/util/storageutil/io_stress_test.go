package storageutil

// io_stress_test.go — IO stress benchmarks for pkg/util/storageutil.
//
// These benchmarks characterize system behavior under concurrent IO load,
// simulating the "family scenario": multiple operations hitting a single
// storage path simultaneously. They are self-contained (synthetic files,
// temp dirs) and do not require real hardware.
//
// Run with:
//
//	go test -bench=. -benchtime=5s -count=3 ./pkg/util/storageutil/
//
// Optional: set STRESS_DISK_PATH=/mnt/usb-hdd to run against a real device.
// The benchmark will use that path instead of a temp dir so results reflect
// actual disk latency.
//
// Output a JSON summary:
//
//	go test -bench=. -benchtime=5s -json ./pkg/util/storageutil/ | \
//	    go run golang.org/x/perf/cmd/benchstat@latest /dev/stdin

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/iosemutil"
)

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

// stressRoot returns the benchmark root directory.
// If STRESS_DISK_PATH is set, use it; otherwise use a temp dir.
func stressRoot(b *testing.B) string {
	b.Helper()
	if p := os.Getenv("STRESS_DISK_PATH"); p != "" {
		b.Logf("stress: using real disk path %s", p)
		return p
	}
	return b.TempDir()
}

// writeTestFile creates a file of the given size (bytes) filled with
// pseudo-random data. Returns the full path.
func writeTestFile(b *testing.B, dir, name string, size int) string {
	b.Helper()
	path := filepath.Join(dir, name)
	// Fill with a repeating pattern — filesystem benchmarks care about bytes
	// on disk, not randomness.
	data := make([]byte, size)
	for i := range data {
		data[i] = byte(i & 0xff)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		b.Fatalf("writeTestFile %s: %v", name, err)
	}
	return path
}

// copyBytes copies src to a new dst file, optionally acquiring sem first.
// Returns elapsed time.
func copyBytes(b *testing.B, src, dst string, sem *iosemutil.Semaphore) time.Duration {
	b.Helper()
	if sem != nil {
		if !sem.AcquireDefault(context.Background()) {
			b.Fatal("IO semaphore timeout")
		}
		defer sem.Release()
	}

	t0 := time.Now()
	in, err := os.Open(src)
	if err != nil {
		b.Fatalf("open src: %v", err)
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		b.Fatalf("create dst: %v", err)
	}
	defer out.Close()

	if _, err := io.Copy(out, in); err != nil {
		b.Fatalf("io.Copy: %v", err)
	}
	return time.Since(t0)
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenario A — concurrent interactive reads + background write
// ─────────────────────────────────────────────────────────────────────────────
//
// Models: N concurrent thumbnail-cache-miss reads while a backup is writing at
// full speed. Measures p50/p99 read latency during background write vs.
// baseline (no competing write).
//
// Metric: operations/second for reads; latency percentiles are printed to b.Log.

func BenchmarkScenarioA_ConcurrentReads_Baseline(b *testing.B) {
	benchScenarioA(b, false)
}

func BenchmarkScenarioA_ConcurrentReads_WithBackgroundWrite(b *testing.B) {
	benchScenarioA(b, true)
}

func benchScenarioA(b *testing.B, withBackgroundWrite bool) {
	root := stressRoot(b)
	const (
		readFileSize  = 512 * 1024      // 512 KB — thumbnail source
		writeFileSize = 4 * 1024 * 1024 // 4 MB — backup write chunk (smaller for tmpfs speed)
	)

	// Prepare source files.
	readSrc := writeTestFile(b, root, "read_src.bin", readFileSize)
	writeSrc := writeTestFile(b, root, "write_src.bin", writeFileSize)

	sem := iosemutil.New()

	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup

	if withBackgroundWrite {
		// Background goroutine: continuously copies to simulate backup throughput.
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-ctx.Done():
					return
				default:
					dst := filepath.Join(root, "write_dst.bin")
					copyBytes(b, writeSrc, dst, sem)
					os.Remove(dst)
				}
			}
		}()
	}

	latencies := make([]time.Duration, 0, b.N)
	var mu sync.Mutex

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			dst := filepath.Join(root, "read_dst_"+randomHex(8)+".bin")
			d := copyBytes(b, readSrc, dst, sem)
			mu.Lock()
			latencies = append(latencies, d)
			mu.Unlock()
			os.Remove(dst)
		}
	})
	b.StopTimer()
	cancel()
	wg.Wait()

	reportPercentiles(b, latencies)
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenario B — sequential large copies (backup simulation) with semaphore
// ─────────────────────────────────────────────────────────────────────────────
//
// Models: bulk file copy (device backup) while interactive reads are happening.
// Measures throughput in bytes/sec with and without semaphore throttling.

func BenchmarkScenarioB_LargeCopy_NoSemaphore(b *testing.B) {
	benchScenarioB(b, nil)
}

func BenchmarkScenarioB_LargeCopy_WithSemaphore(b *testing.B) {
	benchScenarioB(b, iosemutil.New())
}

func benchScenarioB(b *testing.B, sem *iosemutil.Semaphore) {
	root := stressRoot(b)
	const fileSize = 8 * 1024 * 1024 // 8 MB

	src := writeTestFile(b, root, "bulk_src.bin", fileSize)
	b.SetBytes(int64(fileSize))

	b.ResetTimer()
	for b.Loop() {
		dst := filepath.Join(root, "bulk_dst.bin")
		copyBytes(b, src, dst, sem)
		os.Remove(dst)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenario C — many small concurrent reads (cache-miss burst)
// ─────────────────────────────────────────────────────────────────────────────
//
// Models: 8 concurrent goroutines each reading a different small file —
// similar to 8 users browsing their photo grid simultaneously.

func BenchmarkScenarioC_ConcurrentSmallReads(b *testing.B) {
	root := stressRoot(b)
	const (
		numFiles = 8
		fileSize = 64 * 1024 // 64 KB each
	)

	srcs := make([]string, numFiles)
	for i := range numFiles {
		srcs[i] = writeTestFile(b, root, "small_"+itoa(i)+".bin", fileSize)
	}

	sem := iosemutil.New()
	b.SetBytes(int64(fileSize))

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		i := 0
		for pb.Next() {
			src := srcs[i%numFiles]
			dst := filepath.Join(root, "sc_dst_"+randomHex(8)+".bin")
			copyBytes(b, src, dst, sem)
			os.Remove(dst)
			i++
		}
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// Scenario D — semaphore acquisition latency under contention
// ─────────────────────────────────────────────────────────────────────────────
//
// Models: all semaphore slots filled; measures how quickly a new waiter is
// unblocked when a slot is released. Pure synchronization overhead, no disk IO.

func BenchmarkScenarioD_SemaphoreContention(b *testing.B) {
	sem := iosemutil.NewWithConcurrency(2) // tight concurrency to force contention
	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			if !sem.AcquireDefault(context.Background()) {
				b.Fatal("semaphore timeout")
			}
			sem.Release()
		}
	})
}

// BenchmarkScenarioD_SemaphoreNoContention is the baseline: slots always free.
func BenchmarkScenarioD_SemaphoreNoContention(b *testing.B) {
	sem := iosemutil.New() // every class's slots together; test uses GOMAXPROCS
	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			if !sem.AcquireDefault(context.Background()) {
				b.Fatal("semaphore timeout")
			}
			sem.Release()
		}
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

func reportPercentiles(b *testing.B, ds []time.Duration) {
	b.Helper()
	if len(ds) == 0 {
		return
	}
	// Simple insertion-sort for small N; latency slice grows to b.N*GOMAXPROCS.
	for i := 1; i < len(ds); i++ {
		for j := i; j > 0 && ds[j] < ds[j-1]; j-- {
			ds[j], ds[j-1] = ds[j-1], ds[j]
		}
	}
	p := func(pct float64) time.Duration {
		idx := int(float64(len(ds)-1) * pct / 100)
		return ds[idx]
	}
	b.Logf("latency: p50=%v p90=%v p99=%v (n=%d)", p(50), p(90), p(99), len(ds))
}

// randomHex returns a unique hex string for temporary filename suffixes.
var hexCounter uint64
var hexMu sync.Mutex

func randomHex(n int) string {
	hexMu.Lock()
	hexCounter++
	v := hexCounter
	hexMu.Unlock()
	const chars = "0123456789abcdef"
	b := make([]byte, n)
	for i := range b {
		b[i] = chars[v&0xf]
		v >>= 4
	}
	return string(b)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	buf := [20]byte{}
	pos := len(buf)
	for n > 0 {
		pos--
		buf[pos] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[pos:])
}

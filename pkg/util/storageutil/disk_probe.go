package storageutil

import (
	"math/rand/v2"
	"os"
	"path/filepath"
	"time"
)

// DiskSpeedClass classifies a storage device by measured IO performance.
type DiskSpeedClass string

const (
	// DiskSpeedUnknown means the device has not been probed yet.
	DiskSpeedUnknown DiskSpeedClass = "unknown"

	// DiskSpeedFast covers NVMe SSDs and fast SATA SSDs (>200 MB/s sequential read).
	DiskSpeedFast DiskSpeedClass = "fast"

	// DiskSpeedMedium covers SATA HDDs and USB 3.0 HDDs (20–200 MB/s sequential read).
	DiskSpeedMedium DiskSpeedClass = "medium"

	// DiskSpeedSlow covers USB 2.0 HDDs, very old spinning drives, and marginal
	// connections (<20 MB/s sequential read).
	DiskSpeedSlow DiskSpeedClass = "slow"
)

// DiskProbeResult holds the raw measurements and derived classification from a
// disk probe run on a specific directory.
type DiskProbeResult struct {
	// SeqReadMBps is the measured sequential read throughput in MB/s.
	SeqReadMBps float64 `json:"seqReadMBps"`

	// RandReadLatencyMs is the mean 4 KB random-read latency in milliseconds.
	RandReadLatencyMs float64 `json:"randReadLatencyMs"`

	// SpeedClass is the derived classification.
	SpeedClass DiskSpeedClass `json:"speedClass"`
}

const (
	probeSizeBytes   = 4 * 1024 * 1024 // 4 MB sequential read file
	randReadSize     = 4 * 1024        // 4 KB per random read
	randReadCount    = 10              // number of random read samples
	slowThresholdMBs = 20.0            // < 20 MB/s → slow
	fastThresholdMBs = 200.0           // > 200 MB/s → fast
)

// ProbeDisk measures the sequential read speed and random read latency of the
// filesystem at dir. It writes and reads a temporary file; the temp file is
// always removed before returning.
//
// Each read is timed on a file whose pages were just dropped from the page
// cache, so it is the device that answers and not memory (#2467).
//
// The probe is intentionally lightweight — it uses a 4 MB file for sequential
// reads and 10 × 4 KB reads for random latency. Suitable for calling at startup
// per device without perceptible delay.
func ProbeDisk(dir string) DiskProbeResult {
	result := DiskProbeResult{SpeedClass: DiskSpeedUnknown}

	tmpPath := filepath.Join(dir, ".quark-probe-tmp")
	defer os.Remove(tmpPath)
	if err := writeProbeFile(tmpPath); err != nil {
		return result
	}

	// --- Sequential read ---
	buf := make([]byte, probeSizeBytes)
	f, err := openProbeFile(tmpPath)
	if err != nil {
		return result
	}
	seqStart := time.Now()
	_, err = readFull(f, buf)
	seqElapsed := time.Since(seqStart)
	f.Close()
	if err != nil || seqElapsed == 0 {
		return result
	}
	seqMBps := float64(probeSizeBytes) / (1024 * 1024) / seqElapsed.Seconds()
	result.SeqReadMBps = seqMBps

	// --- Random read latency ---
	maxOffset := int64(probeSizeBytes - randReadSize)
	randBuf := make([]byte, randReadSize)
	var totalLatency time.Duration
	for i := 0; i < randReadCount; i++ {
		offset := rand.Int64N(maxOffset)
		// Reopened each time: the read before this one, and what the kernel
		// read ahead of it, put pages back in the cache.
		f, err := openProbeFile(tmpPath)
		if err != nil {
			break
		}
		start := time.Now()
		f.ReadAt(randBuf, offset) //nolint:errcheck // best-effort probe
		totalLatency += time.Since(start)
		f.Close()
	}
	result.RandReadLatencyMs = totalLatency.Seconds() * 1000 / float64(randReadCount)

	// --- Classify ---
	result.SpeedClass = classifyDisk(seqMBps)
	return result
}

// ClassifyDiskSpeed returns the DiskSpeedClass for a given sequential read
// throughput. Exported for testing.
func ClassifyDiskSpeed(seqMBps float64) DiskSpeedClass {
	return classifyDisk(seqMBps)
}

func classifyDisk(seqMBps float64) DiskSpeedClass {
	switch {
	case seqMBps >= fastThresholdMBs:
		return DiskSpeedFast
	case seqMBps >= slowThresholdMBs:
		return DiskSpeedMedium
	default:
		return DiskSpeedSlow
	}
}

// readFull reads len(buf) bytes from f into buf.
func readFull(f *os.File, buf []byte) (int, error) {
	total := 0
	for total < len(buf) {
		n, err := f.Read(buf[total:])
		total += n
		if err != nil {
			return total, err
		}
	}
	return total, nil
}

// writeProbeFile writes the probe's test file and flushes it to the device.
// Only pages that are already on the device can be dropped from the cache.
func writeProbeFile(path string) error {
	data := make([]byte, probeSizeBytes)
	for i := range data {
		data[i] = byte(i & 0xff)
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// openProbeFile opens the probe's test file with none of it in the page
// cache, so the next read has to go to the device.
func openProbeFile(path string) (*os.File, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	evictFromPageCache(f)
	return f, nil
}

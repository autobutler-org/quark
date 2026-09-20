package storageutil

import (
	"slices"
	"sync"
	"time"
)

// ttlCache holds a short-lived cached copy of a device query so callers in
// rapid succession do not each re-run device detection, which shells out once
// per volume on macOS (see #1022, #2191).
type ttlCache[T any] struct {
	mu       sync.Mutex
	result   T
	valid    bool
	cachedAt time.Time
	ttl      time.Duration
}

func (c *ttlCache[T]) get() (T, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.valid || time.Since(c.cachedAt) > c.ttl {
		var zero T
		return zero, false
	}
	return c.result, true
}

func (c *ttlCache[T]) set(result T) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.result = result
	c.valid = true
	c.cachedAt = time.Now()
}

// invalidate clears the cache so the next call re-detects devices.
func (c *ttlCache[T]) invalidate() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.valid = false
}

// diskProbeCache holds long-lived disk probe results keyed by device data
// directory. Probes are lightweight but still I/O-bound, so we cache them
// for probeResultTTL to avoid running a probe on every device-status refresh.
type diskProbeCache struct {
	mu      sync.Mutex
	results map[string]diskProbeCacheEntry
}

const probeResultTTL = 1 * time.Hour

type diskProbeCacheEntry struct {
	result   DiskProbeResult
	cachedAt time.Time
}

func (c *diskProbeCache) get(dir string) (DiskProbeResult, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.results == nil {
		return DiskProbeResult{}, false
	}
	entry, ok := c.results[dir]
	if !ok || time.Since(entry.cachedAt) > probeResultTTL {
		return DiskProbeResult{}, false
	}
	return entry.result, true
}

func (c *diskProbeCache) set(dir string, result DiskProbeResult) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.results == nil {
		c.results = make(map[string]diskProbeCacheEntry)
	}
	c.results[dir] = diskProbeCacheEntry{result: result, cachedAt: time.Now()}
}

// StorageService wraps a Detector and exposes device-querying methods.
// Construct with NewStorageService(d) and inject via deputil.Dependencies.
type StorageService struct {
	detector   Detector
	cache      ttlCache[[]*DeviceStatus]
	managed    ttlCache[[]ManagedDevice]
	roots      ttlCache[[]ManagedDevice]
	probeCache diskProbeCache
}

// NewStorageService returns a StorageService backed by the given Detector.
func NewStorageService(d Detector) *StorageService {
	return &StorageService{
		detector: d,
		cache:    ttlCache[[]*DeviceStatus]{ttl: 10 * time.Second},
		managed:  ttlCache[[]ManagedDevice]{ttl: 10 * time.Second},
		roots:    ttlCache[[]ManagedDevice]{ttl: 10 * time.Second},
	}
}

// GetManagedDevices returns all devices that have an quark data directory.
// Nearly every file request calls it, often twice, so the result is cached
// until the TTL lapses or InvalidateDeviceCache runs. The returned slice is a
// copy, so a caller may modify it.
func (s *StorageService) GetManagedDevices() ([]ManagedDevice, error) {
	if cached, ok := s.managed.get(); ok {
		return slices.Clone(cached), nil
	}
	devices, err := s.detector.DetectDevices()
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	managed := managedDevices(devices)
	s.managed.set(managed)
	return slices.Clone(managed), nil
}

// GetManagedRoots returns the same devices as GetManagedDevices for the file
// paths, which only need where each device's files live, which device it is,
// and what to call it. DataDir, FilesDir, MountPoint, DevicePath, IsInternal,
// UsbInfo and Name are set; the sizes, filesystem, model and categories a
// storage page shows may be empty. It skips the per-volume work of full
// detection (one `diskutil info` each on macOS, a walk of every files
// directory on both platforms), so a cache miss inside a file request stays
// cheap (#2195). It is cached like GetManagedDevices, and the returned slice
// is a copy.
func (s *StorageService) GetManagedRoots() ([]ManagedDevice, error) {
	if cached, ok := s.roots.get(); ok {
		return slices.Clone(cached), nil
	}
	detect := s.detector.DetectDevices
	if rd, ok := s.detector.(rootDetector); ok {
		detect = rd.DetectRoots
	}
	devices, err := detect()
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	roots := managedDevices(devices)
	s.roots.set(roots)
	return slices.Clone(roots), nil
}

// managedDevices keeps the devices that have, or can be given, a files
// directory.
func managedDevices(devices []Device) []ManagedDevice {
	var managed []ManagedDevice
	for _, device := range devices {
		dataDir := GetDataDirForDevice(device.MountPoint)
		filesDir, err := GetFilesDirForDevice(device.MountPoint)
		if err != nil {
			continue
		}
		managed = append(managed, ManagedDevice{
			Device:   device,
			DataDir:  dataDir,
			FilesDir: filesDir,
		})
	}
	return managed
}

// FindManagedDeviceBySerial finds a managed device by USB serial.
// An empty serial returns the first internal device. It reads
// GetManagedRoots, so only the fields that documents are guaranteed.
func (s *StorageService) FindManagedDeviceBySerial(serial string) (*ManagedDevice, error) {
	managed, err := s.GetManagedRoots()
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	for _, d := range managed {
		if serial == "" && d.IsInternal {
			return &d, nil
		}
		if d.UsbInfo != nil && d.UsbInfo.GetSerial() == serial {
			return &d, nil
		}
	}
	return nil, nil
}

// FindDeviceFilesDirBySerial returns the files directory of the managed device
// with the given USB serial. It reports false when the serial is empty, no
// device matches, or the devices cannot be listed, so callers keep whatever
// default files directory they already resolved.
func (s *StorageService) FindDeviceFilesDirBySerial(serial string) (string, bool) {
	if serial == "" {
		return "", false
	}
	devices, err := s.GetManagedRoots()
	if err != nil {
		return "", false // coverage: ignore - requires device detection failure
	}
	for _, d := range devices {
		if d.UsbInfo != nil && d.UsbInfo.GetSerial() == serial {
			return d.FilesDir, true
		}
	}
	return "", false
}

// GetDeviceStatuses returns all detected devices with their enable status.
// Results are cached for up to 10 seconds to avoid repeated disk probes when
// the endpoint is hit in rapid succession (#1022).
func (s *StorageService) GetDeviceStatuses() ([]*DeviceStatus, error) {
	if cached, ok := s.cache.get(); ok {
		return cached, nil
	}
	statuses, err := s.getDeviceStatusesFresh()
	if err != nil {
		return nil, err
	}
	s.cache.set(statuses)
	return statuses, nil
}

func (s *StorageService) getDeviceStatusesFresh() ([]*DeviceStatus, error) {
	devices, err := s.detector.DetectDevices()
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}

	managed, err := s.GetManagedDevices()
	if err != nil {
		return nil, err // coverage: ignore - requires filesystem errors reading managed devices
	}

	enabledMap := make(map[string]ManagedDevice)
	for _, md := range managed {
		enabledMap[md.MountPoint] = md
	}

	var statuses []*DeviceStatus
	for _, device := range devices {
		isEnabled := device.IsInternal
		dataDir := ""
		filesDir := ""
		if md, exists := enabledMap[device.MountPoint]; exists {
			isEnabled = true
			dataDir = md.DataDir
			filesDir = md.FilesDir
		}

		var probeResult *DiskProbeResult
		if dataDir != "" {
			if cached, ok := s.probeCache.get(dataDir); ok {
				// Use cached probe result — probe ran recently.
				probeResult = &cached
			} else {
				// Kick off a background probe; this call returns the unknown result.
				// The next GetDeviceStatuses call (after the probe completes) will
				// return the measured values from cache.
				go func(dir string) {
					r := ProbeDisk(dir)
					s.probeCache.set(dir, r)
					s.cache.invalidate() // expire status cache so next request shows new data
				}(dataDir)
			}
		}

		statuses = append(statuses, &DeviceStatus{
			Device:    device,
			IsEnabled: isEnabled,
			DataDir:   dataDir,
			FilesDir:  filesDir,
			DiskProbe: probeResult,
		})
	}
	return statuses, nil
}

// InvalidateDeviceCache clears the device status cache so the next call
// to GetDeviceStatuses re-probes all devices from disk. Call this after
// any mount/unmount operation to prevent stale UI state.
func (s *StorageService) InvalidateDeviceCache() {
	s.cache.invalidate()
	s.managed.invalidate()
	s.roots.invalidate()
}

// FindUsbDeviceBySerial finds a USB device by serial number.
func (s *StorageService) FindUsbDeviceBySerial(serial string) (UsbDevice, error) {
	return FindUsbDeviceBySerial(serial)
}

package storageutil

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"
)

func TestReadFileTrim(t *testing.T) {
	tests := []struct {
		name    string
		content string
		want    string
	}{
		{"trims whitespace", "  hello world \n", "hello world"},
		{"empty file", "", ""},
		{"no trim needed", "foo", "foo"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			file := filepath.Join(dir, "testfile")
			if err := os.WriteFile(file, []byte(tt.content), 0644); err != nil {
				t.Fatalf("failed to write temp file: %v", err)
			}
			got := readFileTrim(file)
			if got != tt.want {
				t.Errorf("readFileTrim() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestIsStorageDevice(t *testing.T) {
	tests := []struct {
		name         string
		product      string
		manufacturer string
		want         bool
	}{
		{"host controller", "xHCI Host Controller", "Linux", false},
		{"non-storage device", "Some Product", "Some Manufacturer", false},
		// Add more cases as needed
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			os.WriteFile(filepath.Join(dir, "product"), []byte(tt.product), 0644)
			os.WriteFile(filepath.Join(dir, "manufacturer"), []byte(tt.manufacturer), 0644)
			dev := &usbDevice{Path: dir}
			got := dev.IsStorageDevice()
			if got != tt.want {
				t.Errorf("IsStorageDevice() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestOwnsBlockDevice(t *testing.T) {
	const behindHub = "/sys/devices/pci0000:00/0000:00:14.0/usb2/2-1/2-1.1/2-1.1:1.0/host0/target0:0:0/0:0:0:0"
	const direct = "/sys/devices/pci0000:00/0000:00:14.0/usb2/2-1/2-1:1.0/host0/target0:0:0/0:0:0:0"
	tests := []struct {
		name     string
		usbDir   string
		resolved string
		want     bool
	}{
		{"drive behind hub", "2-1.1", behindHub, true},
		{"hub in front of drive", "2-1", behindHub, false},
		{"root hub", "usb2", behindHub, false},
		{"drive plugged in directly", "2-1", direct, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ownsBlockDevice(tt.usbDir, tt.resolved); got != tt.want {
				t.Errorf("ownsBlockDevice(%q) = %v, want %v", tt.usbDir, got, tt.want)
			}
		})
	}
}

func TestBytesConversions(t *testing.T) {
	tests := []struct {
		name  string
		bytes uint64
		kb    float64
		mb    float64
		gb    float64
	}{
		{"1KB", 1024, 1.0, 0.0009765625, 0.00000095367431640625},
		{"1MB", 1048576, 1024.0, 1.0, 0.0009765625},
		{"1GB", 1073741824, 1048576.0, 1024.0, 1.0},
		{"1TB", 1099511627776, 1073741824.0, 1048576.0, 1024.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Test BytesTo* functions
			kb := BytesToKB(tt.bytes)
			if kb != tt.kb {
				t.Errorf("BytesToKB(%d) = %f; want %f", tt.bytes, kb, tt.kb)
			}

			mb := BytesToMB(tt.bytes)
			if mb != tt.mb {
				t.Errorf("BytesToMB(%d) = %f; want %f", tt.bytes, mb, tt.mb)
			}

			gb := BytesToGB(tt.bytes)
			if gb != tt.gb {
				t.Errorf("BytesToGB(%d) = %f; want %f", tt.bytes, gb, tt.gb)
			}
		})
	}
}

func TestReverseConversions(t *testing.T) {
	tests := []struct {
		name  string
		kb    float64
		mb    float64
		gb    float64
		tb    float64
		bytes uint64
	}{
		{"1KB to bytes", 1.0, 0, 0, 0, 1024},
		{"1MB to bytes", 0, 1.0, 0, 0, 1048576},
		{"1GB to bytes", 0, 0, 1.0, 0, 1073741824},
		{"1TB to bytes", 0, 0, 0, 1.0, 1099511627776},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.kb > 0 {
				result := KBToBytes(tt.kb)
				if result != tt.bytes {
					t.Errorf("KBToBytes(%f) = %d; want %d", tt.kb, result, tt.bytes)
				}
			}
			if tt.mb > 0 {
				result := MBToBytes(tt.mb)
				if result != tt.bytes {
					t.Errorf("MBToBytes(%f) = %d; want %d", tt.mb, result, tt.bytes)
				}
			}
			if tt.gb > 0 {
				result := GBToBytes(tt.gb)
				if result != tt.bytes {
					t.Errorf("GBToBytes(%f) = %d; want %d", tt.gb, result, tt.bytes)
				}
			}
			if tt.tb > 0 {
				result := TBToBytes(tt.tb)
				if result != tt.bytes {
					t.Errorf("TBToBytes(%f) = %d; want %d", tt.tb, result, tt.bytes)
				}
			}
		})
	}
}

func TestCalculateSummary(t *testing.T) {
	devices := []Device{
		{
			TotalBytes:     1000000000000, // 1TB
			UsedBytes:      500000000000,  // 500GB
			AvailableBytes: 500000000000,  // 500GB
		},
		{
			TotalBytes:     2000000000000, // 2TB
			UsedBytes:      1000000000000, // 1TB
			AvailableBytes: 1000000000000, // 1TB
		},
	}

	summary := CalculateSummary(devices)

	if summary.TotalDevices != 2 {
		t.Errorf("Expected 2 devices, got %d", summary.TotalDevices)
	}

	if summary.TotalBytes != 3000000000000 {
		t.Errorf("Expected total bytes 3000000000000, got %d", summary.TotalBytes)
	}

	if summary.UsedBytes != 1500000000000 {
		t.Errorf("Expected used bytes 1500000000000, got %d", summary.UsedBytes)
	}

	if summary.AvailBytes != 1500000000000 {
		t.Errorf("Expected avail bytes 1500000000000, got %d", summary.AvailBytes)
	}

	// Check TB conversions (approximately)
	if summary.TotalTB < 2.7 || summary.TotalTB > 2.8 {
		t.Errorf("Expected TotalTB around 2.73, got %f", summary.TotalTB)
	}
}

func TestCalculateSummary_EmptyDevices(t *testing.T) {
	summary := CalculateSummary([]Device{})

	if summary.TotalDevices != 0 {
		t.Errorf("Expected 0 devices, got %d", summary.TotalDevices)
	}

	if summary.TotalBytes != 0 {
		t.Errorf("Expected 0 total bytes, got %d", summary.TotalBytes)
	}
}

// mockDetector is a Detector implementation for use in tests. The counter is
// mutex-guarded so concurrent callers can assert on it.
type mockDetector struct {
	devices []Device
	err     error
	delay   time.Duration
	mu      sync.Mutex
	calls   int
}

func (m *mockDetector) DetectDevices() ([]Device, error) {
	m.mu.Lock()
	m.calls++
	m.mu.Unlock()
	time.Sleep(m.delay)
	return m.devices, m.err
}

func (m *mockDetector) callCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.calls
}

// mockUsbDevice is a minimal UsbDevice implementation for use in tests.
type mockUsbDevice struct {
	serial     string
	mountPoint string
}

func (m *mockUsbDevice) GetPath() string                  { return "" }
func (m *mockUsbDevice) GetVendorID() string              { return "" }
func (m *mockUsbDevice) GetProductID() string             { return "" }
func (m *mockUsbDevice) GetManufacturer() string          { return "" }
func (m *mockUsbDevice) GetProduct() string               { return "" }
func (m *mockUsbDevice) GetSerial() string                { return m.serial }
func (m *mockUsbDevice) GetMountPath() string             { return m.mountPoint }
func (m *mockUsbDevice) BlockDevicePath() (string, bool)  { return "", false }
func (m *mockUsbDevice) IsStorageDevice() bool            { return true }
func (m *mockUsbDevice) Partitions() ([]Partition, error) { return nil, nil }

func TestGetManagedDevices(t *testing.T) {
	// Create a temporary directory to simulate a managed device
	tempDir := t.TempDir()
	filesDir := ConstructFilesDir(tempDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("Failed to create test files directory: %v", err)
	}

	// Verify the function executes against the real detector without error.
	svc := NewStorageService(NewDetector())
	devices, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatalf("GetManagedDevices() error = %v", err)
	}

	// Should return a slice (possibly empty if no managed devices exist in CI)
	if devices == nil {
		t.Error("GetManagedDevices() should return non-nil slice")
	}

	// Each device should have non-empty fields
	for i, device := range devices {
		if device.DataDir == "" {
			t.Errorf("Device %d has empty DataDir", i)
		}
		if device.FilesDir == "" {
			t.Errorf("Device %d has empty FilesDir", i)
		}
	}
}

func TestStorageService_GetManagedDevices(t *testing.T) {
	tempDir := t.TempDir()
	filesDir := ConstructFilesDir(tempDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}

	mock := &mockDetector{
		devices: []Device{
			{Name: "test-disk", MountPoint: tempDir, IsInternal: true},
		},
	}
	svc := NewStorageService(mock)

	devices, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatalf("svc.GetManagedDevices() error = %v", err)
	}
	if len(devices) != 1 {
		t.Fatalf("expected 1 managed device, got %d", len(devices))
	}
	if devices[0].Name != "test-disk" {
		t.Errorf("expected device name 'test-disk', got %q", devices[0].Name)
	}
}

// Device detection shells out once per volume on macOS, and every file request
// asked for the managed devices at least twice (#2191).
func TestStorageService_GetManagedDevices_Cached(t *testing.T) {
	tempDir := t.TempDir()
	if err := os.MkdirAll(ConstructFilesDir(tempDir), 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}
	mock := &mockDetector{devices: []Device{{Name: "test-disk", MountPoint: tempDir, IsInternal: true}}}
	svc := NewStorageService(mock)

	first, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatalf("svc.GetManagedDevices() error = %v", err)
	}
	first[0].Name = "changed by caller"
	second, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatalf("svc.GetManagedDevices() error = %v", err)
	}
	if mock.callCount() != 1 {
		t.Errorf("expected 1 detection for 2 calls, got %d", mock.callCount())
	}
	if second[0].Name != "test-disk" {
		t.Errorf("a caller's edit leaked into the cache: got %q", second[0].Name)
	}

	svc.InvalidateDeviceCache()
	if _, err := svc.GetManagedDevices(); err != nil {
		t.Fatalf("svc.GetManagedDevices() error = %v", err)
	}
	if mock.callCount() != 2 {
		t.Errorf("expected a fresh detection after invalidation, got %d calls", mock.callCount())
	}
}

// rootsDetector counts which detection path the service took.
type rootsDetector struct {
	mockDetector
	rootCalls int
}

func (r *rootsDetector) DetectRoots() ([]Device, error) {
	r.mu.Lock()
	r.rootCalls++
	r.mu.Unlock()
	time.Sleep(r.delay)
	return r.devices, r.err
}

func (r *rootsDetector) rootCallCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.rootCalls
}

// File requests resolve their roots without full detection (#2195).
func TestStorageService_GetManagedRoots(t *testing.T) {
	tempDir := t.TempDir()
	devices := []Device{{MountPoint: tempDir, IsInternal: true}}

	detector := &rootsDetector{mockDetector: mockDetector{devices: devices}}
	svc := NewStorageService(detector)
	for range 2 {
		roots, err := svc.GetManagedRoots()
		if err != nil {
			t.Fatalf("svc.GetManagedRoots() error = %v", err)
		}
		if len(roots) != 1 || roots[0].FilesDir != ConstructFilesDir(GetDataDirForDevice(tempDir)) {
			t.Fatalf("svc.GetManagedRoots() = %+v, want the one device at %s", roots, tempDir)
		}
	}
	if _, err := svc.FindManagedDeviceBySerial(""); err != nil {
		t.Fatalf("svc.FindManagedDeviceBySerial() error = %v", err)
	}
	if detector.rootCallCount() != 1 || detector.callCount() != 0 {
		t.Errorf("expected 1 cached root detection and no full one, got %d and %d", detector.rootCallCount(), detector.callCount())
	}
	svc.InvalidateDeviceCache()
	if _, err := svc.GetManagedRoots(); err != nil {
		t.Fatalf("svc.GetManagedRoots() error = %v", err)
	}
	if detector.rootCallCount() != 2 {
		t.Errorf("expected a fresh root detection after invalidation, got %d", detector.rootCallCount())
	}

	// A Detector without DetectRoots falls back to full detection.
	fallback := &mockDetector{devices: devices}
	if roots, err := NewStorageService(fallback).GetManagedRoots(); err != nil || len(roots) != 1 {
		t.Fatalf("fallback GetManagedRoots() = %+v, %v", roots, err)
	}
	if fallback.callCount() != 1 {
		t.Errorf("expected the fallback to run DetectDevices once, got %d", fallback.callCount())
	}
}

// Every request that missed the cache used to run its own detection, so a
// lapse under load stampeded into one subprocess-heavy scan per request
// (#2197). One detection per lapse serves every waiter.
func TestStorageService_ConcurrentMissesDetectOnce(t *testing.T) {
	tempDir := t.TempDir()
	if err := os.MkdirAll(ConstructFilesDir(tempDir), 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}
	detector := &rootsDetector{mockDetector: mockDetector{
		devices: []Device{{Name: "test-disk", MountPoint: tempDir, IsInternal: true}},
		delay:   20 * time.Millisecond,
	}}
	svc := NewStorageService(detector)

	var wg sync.WaitGroup
	for range 15 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if devices, err := svc.GetManagedDevices(); err != nil || len(devices) != 1 {
				t.Errorf("svc.GetManagedDevices() = %+v, %v", devices, err)
			}
			if roots, err := svc.GetManagedRoots(); err != nil || len(roots) != 1 {
				t.Errorf("svc.GetManagedRoots() = %+v, %v", roots, err)
			}
		}()
	}
	wg.Wait()

	if got := detector.callCount(); got != 1 {
		t.Errorf("expected 1 full detection for 15 concurrent callers, got %d", got)
	}
	if got := detector.rootCallCount(); got != 1 {
		t.Errorf("expected 1 root detection for 15 concurrent callers, got %d", got)
	}
}

// blockingDetector pauses inside its first detection so a test can invalidate
// mid-flight. It reads the devices before pausing, so the paused detection
// returns what was mounted when it started, not what the test swaps in.
type blockingDetector struct {
	mockDetector
	once    sync.Once
	started chan struct{}
	release chan struct{}
}

func (b *blockingDetector) DetectDevices() ([]Device, error) {
	devices, err := b.mockDetector.DetectDevices()
	b.once.Do(func() {
		close(b.started)
		<-b.release
	})
	return devices, err
}

// A detection that started before an invalidation predates whatever the caller
// invalidated for, so it must not be the answer later callers see.
func TestStorageService_InvalidateDuringDetection(t *testing.T) {
	before, after := t.TempDir(), t.TempDir()
	for _, dir := range []string{before, after} {
		if err := os.MkdirAll(ConstructFilesDir(dir), 0755); err != nil {
			t.Fatalf("failed to create files dir: %v", err)
		}
	}
	detector := &blockingDetector{
		mockDetector: mockDetector{devices: []Device{{Name: "before", MountPoint: before}}},
		started:      make(chan struct{}),
		release:      make(chan struct{}),
	}
	svc := NewStorageService(detector)

	done := make(chan struct{})
	go func() {
		defer close(done)
		if _, err := svc.GetManagedDevices(); err != nil {
			t.Errorf("svc.GetManagedDevices() error = %v", err)
		}
	}()

	<-detector.started
	svc.InvalidateDeviceCache()
	detector.devices = []Device{{Name: "after", MountPoint: after}}
	close(detector.release)
	<-done

	devices, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatalf("svc.GetManagedDevices() error = %v", err)
	}
	if len(devices) != 1 || devices[0].Name != "after" {
		t.Errorf("svc.GetManagedDevices() = %+v, want the device detected after invalidation", devices)
	}
	if got := detector.callCount(); got != 2 {
		t.Errorf("expected the invalidated detection to be discarded and re-run, got %d detections", got)
	}
}

// A failed detection is not cached, so the next call tries again.
func TestStorageService_DetectionErrorNotCached(t *testing.T) {
	tempDir := t.TempDir()
	if err := os.MkdirAll(ConstructFilesDir(tempDir), 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}
	detector := &mockDetector{
		devices: []Device{{Name: "test-disk", MountPoint: tempDir, IsInternal: true}},
		err:     errors.New("detection failed"),
	}
	svc := NewStorageService(detector)

	if _, err := svc.GetManagedDevices(); err == nil {
		t.Fatal("svc.GetManagedDevices() = nil error, want the detector's failure")
	}
	detector.err = nil
	devices, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatalf("svc.GetManagedDevices() error = %v", err)
	}
	if len(devices) != 1 {
		t.Errorf("svc.GetManagedDevices() = %+v, want the device detected after the failure", devices)
	}
	if got := detector.callCount(); got != 2 {
		t.Errorf("expected the failure not to be cached, got %d detections", got)
	}
}

func TestStorageService_IsolatedFromDefault(t *testing.T) {
	// Constructing a StorageService with a mock should return a non-nil instance.
	mock := &mockDetector{}
	svc := NewStorageService(mock)
	if svc == nil {
		t.Fatal("expected non-nil StorageService")
	}
}

func TestStorageService_FindManagedDeviceBySerial(t *testing.T) {
	tempDir := t.TempDir()
	filesDir := ConstructFilesDir(tempDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}

	serial := "ABC123"
	usbInfo := &mockUsbDevice{serial: serial, mountPoint: tempDir}
	mock := &mockDetector{
		devices: []Device{
			{Name: "usb-disk", MountPoint: tempDir, IsInternal: false, UsbInfo: usbInfo},
		},
	}
	svc := NewStorageService(mock)

	device, err := svc.FindManagedDeviceBySerial(serial)
	if err != nil {
		t.Fatalf("FindManagedDeviceBySerial() error = %v", err)
	}
	if device == nil {
		t.Fatal("expected to find device, got nil")
	}
	if device.Name != "usb-disk" {
		t.Errorf("expected 'usb-disk', got %q", device.Name)
	}
}

func TestStorageService_FindManagedDeviceBySerial_EmptySerial(t *testing.T) {
	tempDir := t.TempDir()
	filesDir := ConstructFilesDir(tempDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}

	mock := &mockDetector{
		devices: []Device{
			{Name: "internal", MountPoint: tempDir, IsInternal: true},
		},
	}
	svc := NewStorageService(mock)

	// Empty serial should return first internal device
	device, err := svc.FindManagedDeviceBySerial("")
	if err != nil {
		t.Fatalf("FindManagedDeviceBySerial() error = %v", err)
	}
	if device == nil {
		t.Fatal("expected to find internal device, got nil")
	}
	if device.Name != "internal" {
		t.Errorf("expected 'internal', got %q", device.Name)
	}
}

func TestGetDeviceStatuses(t *testing.T) {
	// This test verifies that GetDeviceStatuses properly merges
	// detected devices with managed devices to build status information
	svc := NewStorageService(NewDetector())
	statuses, err := svc.GetDeviceStatuses()
	if err != nil {
		t.Fatalf("GetDeviceStatuses() error = %v", err)
	}

	// Should return at least one device (the system device)
	if len(statuses) == 0 {
		t.Error("GetDeviceStatuses() returned no devices")
	}

	// Verify each status has required fields
	for i, status := range statuses {
		if status.Name == "" {
			t.Errorf("statuses[%d].Name is empty", i)
		}
		if status.MountPoint == "" {
			t.Errorf("statuses[%d].MountPoint is empty", i)
		}

		// If device is enabled, it should have DataDir and FilesDir
		if status.IsEnabled {
			if status.DataDir == "" {
				t.Errorf("statuses[%d].DataDir is empty for enabled device %s", i, status.Name)
			}
			if status.FilesDir == "" {
				t.Errorf("statuses[%d].FilesDir is empty for enabled device %s", i, status.Name)
			}
		}
	}

	// At least one device should be enabled (the system device)
	hasEnabled := false
	for _, status := range statuses {
		if status.IsEnabled {
			hasEnabled = true
			break
		}
	}
	if !hasEnabled {
		t.Error("GetDeviceStatuses() should have at least one enabled device")
	}
}

func TestGetDataDir(t *testing.T) {
	dataDir := GetDataDir()
	if dataDir == "" {
		t.Error("Expected non-empty data directory")
	}
}

func TestGetDataDirForDevice_SystemDevice(t *testing.T) {
	// Test with system root device
	dataDir := GetDataDirForDevice("/")
	if dataDir == "" {
		t.Error("Expected non-empty data directory for root device")
	}
}

func TestGetDataDirForDevice_MacOSSystemVolume(t *testing.T) {
	// Test with macOS system volume path
	dataDir := GetDataDirForDevice("/System/Volumes/Data")
	if dataDir == "" {
		t.Error("Expected non-empty data directory for macOS system volume")
	}
}

func TestGetDataDirForDevice_ExternalDevice(t *testing.T) {
	// Test with external device mount point
	dataDir := GetDataDirForDevice("/Volumes/External")
	expected := "/Volumes/External/quark/data"
	if dataDir != expected {
		t.Errorf("Expected %s, got %s", expected, dataDir)
	}
}

func TestGetFilesDir(t *testing.T) {
	filesDir, err := GetFilesDir()
	if err != nil {
		t.Fatalf("Expected no error, got: %v", err)
	}
	if filesDir == "" {
		t.Error("Expected non-empty files directory")
	}
}

func TestDetermineFileTypeFromPath(t *testing.T) {
	tests := []struct {
		path     string
		expected FileType
	}{
		{"document.pdf", FileTypePDF},
		{"presentation.pptx", FileTypeSlideshow},
		{"presentation.ppt", FileTypeSlideshow},
		{"photo.png", FileTypeImage},
		// SVG is XML, not a raster codec — it must not land in the image
		// bucket that feeds thumbnails and JPEG conversion (#1806).
		{"logo.svg", FileTypeSvg},
		{"LOGO.SVG", FileTypeSvg},
		{"photo.jpg", FileTypeImage},
		{"photo.jpeg", FileTypeImage},
		{"video.mp4", FileTypeVideo},
		{"video.mov", FileTypeVideo},
		{"video.mkv", FileTypeVideo},
		{"video.webm", FileTypeVideo},
		{"video.avi", FileTypeVideo},
		{"video.wmv", FileTypeVideo},
		{"video.flv", FileTypeVideo},
		{"book.epub", FileTypeEpub},
		{"document.docx", FileTypeDocx},
		{"notes.qdoc", FileTypeQdoc},
		{"budget.qsheet", FileTypeQsheet},
		{"deck.qslide", FileTypeQslide},
		{"budget.xlsx", FileTypeXlsx},
		{"macros.xlsm", FileTypeXlsx},
		{"BUDGET.XLSX", FileTypeXlsx}, // Test case insensitivity
		// The legacy binary format is not OOXML, so it stays unclassified
		// rather than promising a conversion that cannot run (#1741).
		{"legacy.xls", FileTypeGeneric},
		{"archive.zip", FileTypeArchive},
		{"file.txt", FileTypeText},
		{"photo.cr2", FileTypeImage},
		{"photo.cr3", FileTypeImage},
		{"photo.nef", FileTypeImage},
		{"photo.arw", FileTypeImage},
		{"photo.dng", FileTypeImage},
		{"photo.orf", FileTypeImage},
		{"photo.rw2", FileTypeImage},
		{"photo.raw", FileTypeImage},
		{"song.mp3", FileTypeAudio},
		{"track.wav", FileTypeAudio},
		{"music.flac", FileTypeAudio},
		{"clip.aac", FileTypeAudio},
		{"sound.ogg", FileTypeAudio},
		{"voice.m4a", FileTypeAudio},
		{"IMAGE.PNG", FileTypeImage},     // Test case insensitivity
		{"PHOTO.CR2", FileTypeImage},     // RAW case insensitivity
		{"generic.bin", FileTypeGeneric}, // Unknown/generic type
		// Plain text
		{"readme.md", FileTypeText},
		{"notes.txt", FileTypeText},
		{"CHANGES.log", FileTypeText},
		{"config.env", FileTypeText},
		{"readme.rst", FileTypeText},
		// Code / markup (FileTypeCode)
		{"main.go", FileTypeCode},
		{"script.py", FileTypeCode},
		{"app.js", FileTypeCode},
		{"component.jsx", FileTypeCode},
		{"component.tsx", FileTypeCode},
		{"style.css", FileTypeCode},
		{"style.scss", FileTypeCode},
		{"index.html", FileTypeCode},
		{"data.json", FileTypeCode},
		{"config.yaml", FileTypeCode},
		{"config.toml", FileTypeCode},
		{"schema.sql", FileTypeCode},
		{"main.rs", FileTypeCode},
		{"App.java", FileTypeCode},
		{"Main.kt", FileTypeCode},
		{"util.swift", FileTypeCode},
		{"widget.dart", FileTypeCode},
		{"lib.c", FileTypeCode},
		{"header.h", FileTypeCode},
		{"class.cpp", FileTypeCode},
		{"setup.sh", FileTypeCode},
		{"main.rb", FileTypeCode},
		// .ts stays video (MPEG-2 transport stream)
		{"stream.ts", FileTypeVideo},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			result := DetermineFileTypeFromPath(tt.path)
			if result != tt.expected {
				t.Errorf("DetermineFileTypeFromPath(%s) = %s; want %s", tt.path, result, tt.expected)
			}
		})
	}
}

func TestIsRawImageExtension(t *testing.T) {
	rawExts := []string{".raw", ".cr2", ".cr3", ".nef", ".arw", ".dng", ".orf", ".rw2"}
	for _, ext := range rawExts {
		if !IsRawImageExtension(ext) {
			t.Errorf("IsRawImageExtension(%q) = false; want true", ext)
		}
	}
	notRaw := []string{".jpg", ".png", ".heic", ".mp4", ".pdf", ""}
	for _, ext := range notRaw {
		if IsRawImageExtension(ext) {
			t.Errorf("IsRawImageExtension(%q) = true; want false", ext)
		}
	}
}

func TestImageMIMEType_RawFormats(t *testing.T) {
	tests := []struct {
		ext  string
		want string
	}{
		{".cr2", "image/x-canon-cr2"},
		{".cr3", "image/x-canon-cr3"},
		{".nef", "image/x-nikon-nef"},
		{".arw", "image/x-sony-arw"},
		{".dng", "image/x-adobe-dng"},
		{".orf", "image/x-olympus-orf"},
		{".rw2", "image/x-panasonic-rw2"},
		{".raw", "image/x-raw"},
	}
	for _, tt := range tests {
		got := ImageMIMETypeFromExtension(tt.ext)
		if got != tt.want {
			t.Errorf("ImageMIMETypeFromExtension(%q) = %q; want %q", tt.ext, got, tt.want)
		}
	}
}

func TestVideoMIMETypeFromExtension(t *testing.T) {
	tests := []struct {
		extension string
		expected  string
	}{
		{extension: ".mp4", expected: "video/mp4"},
		{extension: ".m4v", expected: "video/x-m4v"},
		{extension: ".webm", expected: "video/webm"},
		{extension: ".ogv", expected: "video/ogg"},
		{extension: ".avi", expected: "video/x-msvideo"},
		{extension: ".mov", expected: "video/quicktime"},
		{extension: "mp4", expected: "video/mp4"},
		{extension: ".MP4", expected: "video/mp4"},
		{extension: " .mov ", expected: "video/quicktime"},
		{extension: ".mkv", expected: "video/x-matroska"},
		{extension: ".unknown", expected: "application/octet-stream"},
		{extension: "", expected: "application/octet-stream"},
	}

	for _, tt := range tests {
		t.Run(tt.extension, func(t *testing.T) {
			result := VideoMIMETypeFromExtension(tt.extension)
			if result != tt.expected {
				t.Errorf("VideoMIMETypeFromExtension(%q) = %q; want %q", tt.extension, result, tt.expected)
			}
		})
	}
}

func TestAudioMIMETypeFromExtension(t *testing.T) {
	tests := []struct {
		extension string
		expected  string
	}{
		{extension: ".mp3", expected: "audio/mpeg"},
		{extension: ".wav", expected: "audio/wav"},
		{extension: ".flac", expected: "audio/flac"},
		{extension: ".aac", expected: "audio/aac"},
		{extension: ".ogg", expected: "audio/ogg"},
		{extension: ".m4a", expected: "audio/mp4"},
		{extension: ".wma", expected: "audio/x-ms-wma"},
		{extension: ".opus", expected: "audio/opus"},
		{extension: "mp3", expected: "audio/mpeg"},
		{extension: ".MP3", expected: "audio/mpeg"},
		{extension: " .wav ", expected: "audio/wav"},
		{extension: ".unknown", expected: "application/octet-stream"},
		{extension: "", expected: "application/octet-stream"},
	}

	for _, tt := range tests {
		t.Run(tt.extension, func(t *testing.T) {
			result := AudioMIMETypeFromExtension(tt.extension)
			if result != tt.expected {
				t.Errorf("AudioMIMETypeFromExtension(%q) = %q; want %q", tt.extension, result, tt.expected)
			}
		})
	}
}

func TestSizeBytesToString(t *testing.T) {
	tests := []struct {
		name     string
		bytes    int64
		expected string
	}{
		{"0 bytes", 0, "0 B"},
		{"500 bytes", 500, "500 B"},
		{"1 KB", 1024, "1.0 KB"},
		{"1 MB", 1048576, "1.0 MB"},
		{"1 GB", 1073741824, "1.0 GB"},
		{"1 TB", 1099511627776, "1.0 TB"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := SizeBytesToString(tt.bytes)
			if result != tt.expected {
				t.Errorf("SizeBytesToString(%d) = %s; want %s", tt.bytes, result, tt.expected)
			}
		})
	}
}

func TestCustomFileInfo(t *testing.T) {
	fi := NewCustomFileInfo().WithName("testdir").WithSize(4096)

	if fi.Name() != "testdir/" {
		t.Errorf("Expected name 'testdir/', got '%s'", fi.Name())
	}

	if fi.Size() != 4096 {
		t.Errorf("Expected size 4096, got %d", fi.Size())
	}

	if !fi.IsDir() {
		t.Error("Expected IsDir() to be true")
	}

	// Test Mode()
	mode := fi.Mode()
	if mode != 0666 {
		t.Errorf("Expected mode 0666, got %v", mode)
	}

	// Test ModTime()
	modTime := fi.ModTime()
	if modTime.IsZero() {
		t.Error("Expected non-zero ModTime")
	}

	// Test Sys()
	if fi.Sys() != nil {
		t.Error("Expected Sys() to return nil")
	}
}

func TestGetDeviceInfoForPath_MacOSVolume(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Skipping macOS-specific test")
	}

	deviceName, devicePath := GetDeviceInfoForPath("/Volumes/MyDrive/some/file.txt")
	if deviceName != "MyDrive" {
		t.Errorf("Expected deviceName 'MyDrive', got '%s'", deviceName)
	}
	if devicePath != "/Volumes/MyDrive" {
		t.Errorf("Expected devicePath '/Volumes/MyDrive', got '%s'", devicePath)
	}
}

func TestGetDeviceInfoForPath_MacOSMainDrive(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Skipping macOS-specific test")
	}

	deviceName, devicePath := GetDeviceInfoForPath("/Users/test/file.txt")
	if deviceName != "Macintosh HD" {
		t.Errorf("Expected deviceName 'Macintosh HD', got '%s'", deviceName)
	}
	if devicePath != "/" {
		t.Errorf("Expected devicePath '/', got '%s'", devicePath)
	}
}

func TestGetDeviceInfoForPath_LinuxMedia(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Skipping Linux-specific test")
	}

	deviceName, devicePath := GetDeviceInfoForPath("/media/user/USB/file.txt")
	if deviceName != "USB" {
		t.Errorf("Expected deviceName 'USB', got '%s'", deviceName)
	}
	if devicePath != "/media/user/USB" {
		t.Errorf("Expected devicePath '/media/user/USB', got '%s'", devicePath)
	}
}

func TestGetDeviceInfoForPath_LinuxMnt(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Skipping Linux-specific test")
	}

	deviceName, devicePath := GetDeviceInfoForPath("/mnt/external/file.txt")
	if deviceName != "external" {
		t.Errorf("Expected deviceName 'external', got '%s'", deviceName)
	}
	if devicePath != "/mnt/external" {
		t.Errorf("Expected devicePath '/mnt/external', got '%s'", devicePath)
	}
}

func TestGetDeviceInfoForPath_LinuxRoot(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Skipping Linux-specific test")
	}

	deviceName, devicePath := GetDeviceInfoForPath("/home/user/file.txt")
	if deviceName != "Root" {
		t.Errorf("Expected deviceName 'Root', got '%s'", deviceName)
	}
	if devicePath != "/" {
		t.Errorf("Expected devicePath '/', got '%s'", devicePath)
	}
}

func TestNewDetector(t *testing.T) {
	detector := NewDetector()
	if detector == nil {
		t.Error("Expected non-nil detector")
	}
}

func TestGetFolderSize(t *testing.T) {
	tmpDir := t.TempDir()

	// Create test files
	os.WriteFile(filepath.Join(tmpDir, "file1.txt"), []byte("12345"), 0644)
	os.WriteFile(filepath.Join(tmpDir, "file2.txt"), []byte("67890"), 0644)

	size, err := GetFolderSize(tmpDir)
	if err != nil {
		t.Fatalf("GetFolderSize failed: %v", err)
	}

	if size != 10 {
		t.Errorf("Expected size 10, got %d", size)
	}
}

func TestGetFolderSize_WithSubdirectories(t *testing.T) {
	tmpDir := t.TempDir()

	os.WriteFile(filepath.Join(tmpDir, "file1.txt"), []byte("abc"), 0644)

	subDir := filepath.Join(tmpDir, "subdir")
	os.Mkdir(subDir, 0755)
	os.WriteFile(filepath.Join(subDir, "file2.txt"), []byte("defgh"), 0644)

	size, err := GetFolderSize(tmpDir)
	if err != nil {
		t.Fatalf("GetFolderSize failed: %v", err)
	}

	// Should be 3 + 5 = 8 bytes
	if size != 8 {
		t.Errorf("Expected size 8, got %d", size)
	}
}

func TestInitializeDeviceDataDir(t *testing.T) {
	// Create a temporary directory to use as a mount point
	tempDir := t.TempDir()

	err := InitializeDeviceDataDir(tempDir)
	if err != nil {
		t.Fatalf("InitializeDeviceDataDir() error = %v", err)
	}

	// Verify the directory structure was created
	// For external devices, the path is: mountPoint/quark/data/files
	dataDir := filepath.Join(tempDir, "quark", "data")
	filesDir := ConstructFilesDir(dataDir)
	if _, err := os.Stat(filesDir); os.IsNotExist(err) {
		t.Errorf("Expected files directory to be created at %s", filesDir)
	}
}

func TestInitializeDeviceDataDir_AlreadyExists(t *testing.T) {
	// Create a temporary directory with existing structure
	tempDir := t.TempDir()
	dataDir := filepath.Join(tempDir, "quark", "data")
	filesDir := ConstructFilesDir(dataDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("Failed to create test directory: %v", err)
	}

	// Should succeed even if directory already exists
	err := InitializeDeviceDataDir(tempDir)
	if err != nil {
		t.Errorf("InitializeDeviceDataDir() should succeed when directory exists, got error: %v", err)
	}
}

func TestDetermineFileTypeFromPath_EmptyOrSlashPath(t *testing.T) {
	// Test that "" and "/" are treated as folders
	tests := []struct {
		path string
	}{
		{""},
		{"/"},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			result := DetermineFileTypeFromPath(tt.path)
			if result != FileTypeFolder {
				t.Errorf("DetermineFileTypeFromPath(%q) = %s; want %s", tt.path, result, FileTypeFolder)
			}
		})
	}
}

func TestDetermineFileTypeFromPath_DirectoryPath(t *testing.T) {
	// Test a directory path (uses os.Stat and IsDir check)
	tempDir := t.TempDir()

	result := DetermineFileTypeFromPath(tempDir)
	if result != FileTypeFolder {
		t.Errorf("DetermineFileTypeFromPath(%s) = %s; want %s", tempDir, result, FileTypeFolder)
	}
}

func TestDetermineFileTypeFromPath_NonexistentFile(t *testing.T) {
	// Test a nonexistent file (os.Stat will fail, should return FileTypeGeneric)
	result := DetermineFileTypeFromPath("/nonexistent/path/file.unknown")
	if result != FileTypeGeneric {
		t.Errorf("DetermineFileTypeFromPath(nonexistent) = %s; want %s", result, FileTypeGeneric)
	}
}

func TestGetAvailableSpaceInBytes(t *testing.T) {
	// Test that GetAvailableSpaceInBytes returns a non-zero value for a valid directory
	tempDir := t.TempDir()

	availableSpace := GetAvailableSpaceInBytes(tempDir)

	// We just verify that it returns a reasonable value (greater than 0)
	// The actual value will vary by system
	if availableSpace == 0 {
		t.Errorf("GetAvailableSpaceInBytes() = 0; want > 0")
	}
}

func TestNewDeviceFileInfo(t *testing.T) {
	// Create a test file to get real FileInfo
	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.txt")
	if err := os.WriteFile(testFile, []byte("test content"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	fileInfo, err := os.Stat(testFile)
	if err != nil {
		t.Fatalf("Failed to stat test file: %v", err)
	}

	// Create DeviceFileInfo using constructor
	deviceName := "TestDevice"
	devicePath := "/test/path"
	fullPath := testFile

	deviceFileInfo := NewDeviceFileInfo(fileInfo, deviceName, devicePath, fullPath, "")

	// Verify all fields are set correctly
	if deviceFileInfo.DeviceName != deviceName {
		t.Errorf("DeviceName = %s; want %s", deviceFileInfo.DeviceName, deviceName)
	}
	if deviceFileInfo.DevicePath != devicePath {
		t.Errorf("DevicePath = %s; want %s", deviceFileInfo.DevicePath, devicePath)
	}
	if deviceFileInfo.FullPath != fullPath {
		t.Errorf("FullPath = %s; want %s", deviceFileInfo.FullPath, fullPath)
	}
	if deviceFileInfo.FileInfo != fileInfo {
		t.Errorf("FileInfo not set correctly")
	}
}

func TestDeviceFileInfo_WrapperMethods(t *testing.T) {
	// Create a test file to get real FileInfo
	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.txt")
	content := []byte("test content for wrapper methods")
	if err := os.WriteFile(testFile, content, 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	fileInfo, err := os.Stat(testFile)
	if err != nil {
		t.Fatalf("Failed to stat test file: %v", err)
	}

	deviceFileInfo := NewDeviceFileInfo(fileInfo, "Device", "/device", testFile, "")

	// Test Name() wrapper
	if deviceFileInfo.Name() != fileInfo.Name() {
		t.Errorf("Name() = %s; want %s", deviceFileInfo.Name(), fileInfo.Name())
	}

	// Test Size() wrapper
	if deviceFileInfo.Size() != fileInfo.Size() {
		t.Errorf("Size() = %d; want %d", deviceFileInfo.Size(), fileInfo.Size())
	}

	// Test Mode() wrapper
	if deviceFileInfo.Mode() != fileInfo.Mode() {
		t.Errorf("Mode() = %v; want %v", deviceFileInfo.Mode(), fileInfo.Mode())
	}

	// Test ModTime() wrapper
	if !deviceFileInfo.ModTime().Equal(fileInfo.ModTime()) {
		t.Errorf("ModTime() = %v; want %v", deviceFileInfo.ModTime(), fileInfo.ModTime())
	}

	// Test IsDir() wrapper
	if deviceFileInfo.IsDir() != fileInfo.IsDir() {
		t.Errorf("IsDir() = %v; want %v", deviceFileInfo.IsDir(), fileInfo.IsDir())
	}

	// Test Sys() wrapper
	if deviceFileInfo.Sys() != fileInfo.Sys() {
		t.Errorf("Sys() mismatch")
	}
}

// writeFileAt creates parent directories as needed and writes content.
func writeFileAt(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatalf("failed to create parent directories for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatalf("failed to write %s: %v", path, err)
	}
}

// requireFileContent asserts the file exists with exactly the given content.
func requireFileContent(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("expected %s to exist: %v", path, err)
	}
	if string(got) != want {
		t.Errorf("%s content mismatch: got %q, want %q", path, string(got), want)
	}
}

// TestSetupFilesDir checks the startup setup creates the storage root and
// leaves an existing one alone.
func TestSetupFilesDir(t *testing.T) {
	dataDir := t.TempDir()
	writeFileAt(t, filepath.Join(ConstructFilesDir(dataDir), "keep.txt"), "keep me")

	if err := setupFilesDirIn(dataDir); err != nil {
		t.Fatalf("setupFilesDirIn returned an unexpected error: %v", err)
	}
	requireFileContent(t, filepath.Join(ConstructFilesDir(dataDir), "keep.txt"), "keep me")

	fresh := t.TempDir()
	if err := setupFilesDirIn(fresh); err != nil {
		t.Fatalf("setupFilesDirIn returned an unexpected error: %v", err)
	}
	info, err := os.Stat(ConstructFilesDir(fresh))
	if err != nil {
		t.Fatalf("files directory should exist: %v", err)
	}
	if !info.IsDir() {
		t.Errorf("files storage path should be a directory")
	}
}

// TestGetFilesDirForDeviceUsesFilesName pins the on-disk name for external
// devices.
func TestGetFilesDirForDeviceUsesFilesName(t *testing.T) {
	mountPoint := t.TempDir()
	deviceDataDir := GetDataDirForDevice(mountPoint)

	filesDir, err := GetFilesDirForDevice(mountPoint)
	if err != nil {
		t.Fatalf("GetFilesDirForDevice returned an error: %v", err)
	}

	if want := ConstructFilesDir(deviceDataDir); filesDir != want {
		t.Errorf("files dir mismatch: got %q, want %q", filesDir, want)
	}
	if filepath.Base(filesDir) != "files" {
		t.Errorf("device storage dir should be named files, got %q", filepath.Base(filesDir))
	}
}

// --- Impl function tests (using dependency injection) ---

func TestNumberedName(t *testing.T) {
	for _, tc := range []struct {
		name string
		n    int
		want string
	}{
		{"a.txt", 0, "a.txt"},
		{"a.txt", 2, "a_(2).txt"},
		{"archive.tar.gz", 1, "archive.tar_(1).gz"},
		{"README", 1, "README_(1)"},
		{".env", 1, "file_(1).env"},
	} {
		if got := NumberedName(tc.name, tc.n); got != tc.want {
			t.Errorf("NumberedName(%q, %d) = %q, want %q", tc.name, tc.n, got, tc.want)
		}
	}
}

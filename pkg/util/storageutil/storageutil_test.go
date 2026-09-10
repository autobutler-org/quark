package storageutil

import (
	"bytes"
	"fmt"
	"mime/multipart"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
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

// mockDetector is a Detector implementation for use in tests.
type mockDetector struct {
	devices []Device
	err     error
}

func (m *mockDetector) DetectDevices() ([]Device, error) {
	return m.devices, m.err
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

func TestStorageService_FindDeviceFilesDirBySerial(t *testing.T) {
	tempDir := t.TempDir()
	filesDir := ConstructFilesDir(tempDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}

	const serial = "ABC123"
	mock := &mockDetector{
		devices: []Device{
			{Name: "internal", MountPoint: tempDir, IsInternal: true},
			{Name: "usb-disk", MountPoint: tempDir, UsbInfo: &mockUsbDevice{serial: serial, mountPoint: tempDir}},
		},
	}
	svc := NewStorageService(mock)

	want, err := GetFilesDirForDevice(tempDir)
	if err != nil {
		t.Fatalf("GetFilesDirForDevice() error = %v", err)
	}
	dir, ok := svc.FindDeviceFilesDirBySerial(serial)
	if !ok {
		t.Fatal("expected to find device files dir")
	}
	if dir != want {
		t.Errorf("expected %q, got %q", want, dir)
	}

	// An empty serial must not match the internal device: callers keep their default.
	if _, ok := svc.FindDeviceFilesDirBySerial(""); ok {
		t.Error("expected no match for an empty serial")
	}
	if _, ok := svc.FindDeviceFilesDirBySerial("NOPE"); ok {
		t.Error("expected no match for an unknown serial")
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

func TestStatFilesInMultipleDirs(t *testing.T) {
	// Create temporary directories for multiple devices
	tmpDir1 := t.TempDir()
	tmpDir2 := t.TempDir()

	// Create files in first directory
	os.WriteFile(filepath.Join(tmpDir1, "file1.txt"), []byte("content1"), 0644)
	os.Mkdir(filepath.Join(tmpDir1, "dir1"), 0755)

	// Create files in second directory (including a duplicate name)
	os.WriteFile(filepath.Join(tmpDir2, "file2.txt"), []byte("content2"), 0644)
	os.WriteFile(filepath.Join(tmpDir2, "file1.txt"), []byte("different content"), 0644)

	dirsWithDevice := []DirWithDevice{
		{Dir: tmpDir1, DeviceName: "Device1", DevicePath: "/dev1"},
		{Dir: tmpDir2, DeviceName: "Device2", DevicePath: "/dev2"},
	}

	files, err := StatFilesInMultipleDirs(dirsWithDevice)
	if err != nil {
		t.Fatalf("StatFilesInMultipleDirs failed: %v", err)
	}

	// Should have 4 entries: dir1, file1.txt (from dev1), file1.txt (from dev2), file2.txt
	if len(files) != 4 {
		t.Errorf("Expected 4 files, got %d", len(files))
	}
}

func TestStatFilesInMultipleDirs_WithNonexistentDir(t *testing.T) {
	// Test that nonexistent directories are skipped
	tmpDir := t.TempDir()
	os.WriteFile(filepath.Join(tmpDir, "file.txt"), []byte("content"), 0644)

	dirsWithDevice := []DirWithDevice{
		{Dir: "/nonexistent/path", DeviceName: "BadDevice", DevicePath: "/bad"},
		{Dir: tmpDir, DeviceName: "GoodDevice", DevicePath: "/good"},
	}

	files, err := StatFilesInMultipleDirs(dirsWithDevice)
	if err != nil {
		t.Fatalf("StatFilesInMultipleDirs failed: %v", err)
	}

	// Should only have file from the valid directory
	if len(files) != 1 {
		t.Errorf("Expected 1 file, got %d", len(files))
	}
}

func TestNewDetector(t *testing.T) {
	detector := NewDetector()
	if detector == nil {
		t.Error("Expected non-nil detector")
	}
}

func TestDeleteFiles_SingleDevice(t *testing.T) {
	// Create a temporary files directory
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "testfile.txt")
	os.WriteFile(testFile, []byte("test content"), 0644)

	// This test would need the GetFilesDir to return our tmpDir
	// Since we can't easily mock that, we'll test the structure
	params := DeleteFilesParams{
		RootDir:   "",
		FilePaths: []string{"testfile.txt"},
	}

	// Note: This will fail in testing because GetFilesDir returns a fixed path
	// In a real app, you'd use dependency injection
	svc := NewStorageService(NewDetector())
	_, err := svc.DeleteFiles(params)
	// We expect an error since the file isn't in the actual GetFilesDir()
	_ = err // Just verify it doesn't panic
}

func TestMoveFile(t *testing.T) {
	params := MoveFileParams{
		OldFilePath: "old/path/file.txt",
		NewFilePath: "new/path/file.txt",
	}

	// This will fail because GetFilesDir returns a fixed path
	// but it tests the code doesn't panic
	svc := NewStorageService(NewDetector())
	_, err := svc.MoveFile(params)
	_ = err
}

func TestCreateFolder(t *testing.T) {
	params := CreateFolderParams{
		FolderDir:  "",
		FolderName: "testfolder",
	}

	// This will create a real folder in the GetFilesDir
	// Clean up afterwards if needed
	svc := NewStorageService(NewDetector())
	result, err := svc.CreateFolder(params)
	if err != nil {
		// Expected since we can't control GetFilesDir in tests
		t.Logf("CreateFolder returned error (expected): %v", err)
	} else if result != nil {
		// If it succeeded, verify the result structure
		if result.CurrentDir != params.FolderDir {
			t.Errorf("Expected CurrentDir %s, got %s", params.FolderDir, result.CurrentDir)
		}
	}
}

func TestDownloadFile(t *testing.T) {
	params := DownloadFileParams{
		FilePath: "nonexistent/file.txt",
	}

	svc := NewStorageService(NewDetector())
	_, err := svc.DownloadFile(params)
	// Should fail because file doesn't exist
	if err == nil {
		t.Error("Expected error for non-existent file")
	}
}

func TestFindFileAcrossDevices(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.txt")
	os.WriteFile(testFile, []byte("content"), 0644)

	dirs := []DirWithDevice{
		{
			Dir:        tmpDir,
			DeviceName: "TestDevice",
			DevicePath: "/test",
		},
	}

	fullPath, err := FindFileAcrossDevices(dirs, "test.txt")
	if err != nil {
		t.Fatalf("FindFileAcrossDevices failed: %v", err)
	}

	if fullPath != testFile {
		t.Errorf("Expected %s, got %s", testFile, fullPath)
	}
}

func TestFindFileAcrossDevices_NotFound(t *testing.T) {
	tmpDir := t.TempDir()

	dirs := []DirWithDevice{
		{
			Dir:        tmpDir,
			DeviceName: "TestDevice",
			DevicePath: "/test",
		},
	}

	_, err := FindFileAcrossDevices(dirs, "nonexistent.txt")
	if err == nil {
		t.Error("Expected error for non-existent file")
	}
}

func TestStatFilesInDir(t *testing.T) {
	tmpDir := t.TempDir()

	// Create test files
	os.WriteFile(filepath.Join(tmpDir, "file1.txt"), []byte("content1"), 0644)
	os.WriteFile(filepath.Join(tmpDir, "file2.txt"), []byte("content2"), 0644)
	os.Mkdir(filepath.Join(tmpDir, "subdir"), 0755)

	files, err := StatFilesInDir(tmpDir, "TestDevice", "/test", "")
	if err != nil {
		t.Fatalf("StatFilesInDir failed: %v", err)
	}

	// Should have 3 entries: 1 directory + 2 files
	if len(files) != 3 {
		t.Errorf("Expected 3 files, got %d", len(files))
	}

	// Verify directory comes first (due to sorting)
	if !files[0].IsDir() {
		t.Error("Expected first entry to be a directory")
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

func TestDoesFileExist(t *testing.T) {
	tmpDir := t.TempDir()
	existingFile := filepath.Join(tmpDir, "exists.txt")
	os.WriteFile(existingFile, []byte("content"), 0644)

	if !DoesFileExist(existingFile) {
		t.Error("Expected file to exist")
	}

	nonExistentFile := filepath.Join(tmpDir, "does-not-exist.txt")
	if DoesFileExist(nonExistentFile) {
		t.Error("Expected file to not exist")
	}
}

func TestMoveFile_CreateDirectory(t *testing.T) {
	// This test validates that MoveFile creates the destination directory
	// We can't easily test this without interfering with GetFilesDir(),
	// but we can at least verify the function structure
	params := MoveFileParams{
		OldFilePath: "nonexistent/old.txt",
		NewFilePath: "new/path/file.txt",
	}

	svc := NewStorageService(NewDetector())
	_, err := svc.MoveFile(params)
	// Expected to fail since the source doesn't exist
	if err == nil {
		t.Error("Expected error when source file doesn't exist")
	}
}

func TestMoveFile_ToRootDirectory(t *testing.T) {
	// Test the newDir == "." condition by using a file in the current directory
	// When NewFilePath has no directory component, filepath.Dir returns "."
	svc := NewStorageService(NewDetector())

	params := MoveFileParams{
		OldFilePath: "subdir/file.txt",
		NewFilePath: "newfile.txt", // No directory component
	}

	// This will fail because the file doesn't exist, but we can at least
	// verify the NewDir logic would work correctly
	_, err := svc.MoveFile(params)

	// We expect an error because the file doesn't exist
	if err == nil {
		t.Fatal("Expected error when moving non-existent file")
	}

	// Even though the move fails, we can test the logic separately
	newDir := filepath.Dir("newfile.txt")
	if newDir == "." {
		newDir = ""
	}

	if newDir != "" {
		t.Errorf("Expected newDir to be empty string when filepath.Dir returns '.', got '%s'", newDir)
	}

	// Also verify with an actual successful move
	tmpDir := t.TempDir()

	// Create source file
	sourceFile := filepath.Join(tmpDir, "subdir", "source.txt")
	os.MkdirAll(filepath.Dir(sourceFile), 0755)
	os.WriteFile(sourceFile, []byte("test"), 0644)

	// Get the current files dir and construct paths relative to it
	filesDir, err := GetFilesDir()
	if err != nil {
		t.Fatalf("GetFilesDir failed: %v", err)
	}

	// Create test structure in actual filesDir
	testSourceDir := filepath.Join(filesDir, "test_move_root")
	testSourceFile := filepath.Join(testSourceDir, "subdir", "file.txt")
	os.MkdirAll(filepath.Dir(testSourceFile), 0755)
	os.WriteFile(testSourceFile, []byte("content"), 0644)
	defer os.RemoveAll(testSourceDir)

	params2 := MoveFileParams{
		OldFilePath: "test_move_root/subdir/file.txt",
		NewFilePath: "test_move_root/moved.txt",
	}

	result2, err := svc.MoveFile(params2)
	if err != nil {
		t.Fatalf("MoveFile failed: %v", err)
	}

	// NewDir should be "test_move_root"
	if result2.NewDir != "test_move_root" {
		t.Errorf("Expected NewDir 'test_move_root', got '%s'", result2.NewDir)
	}

	// Now test the case where newDir == "." (moving to root)
	testSourceFile2 := filepath.Join(testSourceDir, "subdir", "file2.txt")
	os.WriteFile(testSourceFile2, []byte("content2"), 0644)

	params3 := MoveFileParams{
		OldFilePath: "test_move_root/subdir/file2.txt",
		NewFilePath: "rootfile.txt", // No directory path, filepath.Dir will return "."
	}

	result3, err := svc.MoveFile(params3)
	if err != nil {
		t.Fatalf("MoveFile to root failed: %v", err)
	}

	// When filepath.Dir returns ".", it should be converted to ""
	if result3.NewDir != "" {
		t.Errorf("Expected NewDir to be empty string, got '%s'", result3.NewDir)
	}

	// Clean up the file we moved to root
	os.Remove(filepath.Join(filesDir, "rootfile.txt"))
}

func TestDownloadFile_MultiDevice_NotFound(t *testing.T) {
	params := DownloadFileParams{
		FilePath: "test/nonexistent.txt",
	}

	svc := NewStorageService(NewDetector())
	_, err := svc.DownloadFile(params)
	if err == nil {
		t.Error("Expected error when file doesn't exist on any device")
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

func TestDetermineFileType_NilFile(t *testing.T) {
	// Test with nil file - should return FileTypeSpacer
	result := DetermineFileType("", nil)
	if result != FileTypeSpacer {
		t.Errorf("DetermineFileType(nil) = %s; want %s", result, FileTypeSpacer)
	}
}

func TestDetermineFileType_Directory(t *testing.T) {
	// Test with a directory DeviceFileInfo
	tempDir := t.TempDir()
	testDir := filepath.Join(tempDir, "testdir")
	if err := os.Mkdir(testDir, 0755); err != nil {
		t.Fatalf("Failed to create test directory: %v", err)
	}

	fileInfo, err := os.Stat(testDir)
	if err != nil {
		t.Fatalf("Failed to stat test directory: %v", err)
	}

	deviceFileInfo := &DeviceFileInfo{
		FileInfo:   fileInfo,
		DeviceName: "test-device",
		DevicePath: tempDir,
		FullPath:   testDir,
	}

	result := DetermineFileType("", deviceFileInfo)
	if result != FileTypeFolder {
		t.Errorf("DetermineFileType(directory) = %s; want %s", result, FileTypeFolder)
	}
}

func TestDetermineFileType_RegularFile(t *testing.T) {
	// Test with a regular file - should use DetermineFileTypeFromPath
	// Create a test file in the actual filesDir
	filesDir, err := GetFilesDir()
	if err != nil {
		t.Fatalf("GetFilesDir failed: %v", err)
	}
	testDir := filepath.Join(filesDir, "test_determine_type")
	testFile := filepath.Join(testDir, "test.pdf")

	os.MkdirAll(testDir, 0755)
	defer os.RemoveAll(testDir)

	if err := os.WriteFile(testFile, []byte("test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	fileInfo, err := os.Stat(testFile)
	if err != nil {
		t.Fatalf("Failed to stat test file: %v", err)
	}

	deviceFileInfo := &DeviceFileInfo{
		FileInfo:   fileInfo,
		DeviceName: "test-device",
		DevicePath: filesDir,
		FullPath:   testFile,
	}

	result := DetermineFileType("test_determine_type", deviceFileInfo)
	if result != FileTypePDF {
		t.Errorf("DetermineFileType(test.pdf) = %s; want %s", result, FileTypePDF)
	}
}

func TestDetermineFileType_FileNotFoundInFilesDir(t *testing.T) {
	// Test when file.IsDir() is false but the file doesn't exist in filesDir
	// This should return FileTypeGeneric
	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "ghost.txt")
	if err := os.WriteFile(testFile, []byte("test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	fileInfo, err := os.Stat(testFile)
	if err != nil {
		t.Fatalf("Failed to stat test file: %v", err)
	}

	deviceFileInfo := &DeviceFileInfo{
		FileInfo:   fileInfo,
		DeviceName: "test-device",
		DevicePath: tempDir,
		FullPath:   testFile,
	}

	// The file exists in tempDir but not in filesDir, so os.Stat will fail
	result := DetermineFileType("nonexistent_root", deviceFileInfo)
	if result != FileTypeGeneric {
		t.Errorf("DetermineFileType(file not in filesDir) = %s; want %s", result, FileTypeGeneric)
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

func TestGetNonConflictingPath(t *testing.T) {
	tmpDir := t.TempDir()

	tests := []struct {
		name            string
		setup           func(t *testing.T, dir string) // Setup function to create files
		inputPath       string
		expectedPath    string
		expectedContent string // For validating the file can be created
	}{
		{
			name: "returns original path when no conflict exists",
			setup: func(t *testing.T, dir string) {
				// Don't create any files
			},
			inputPath:    filepath.Join(tmpDir, "newfile.txt"),
			expectedPath: filepath.Join(tmpDir, "newfile.txt"),
		},
		{
			name: "suffixes with _(1) when file exists",
			setup: func(t *testing.T, dir string) {
				if err := os.WriteFile(filepath.Join(dir, "file.txt"), []byte("original"), 0644); err != nil {
					t.Fatalf("failed to create test file: %v", err)
				}
			},
			inputPath:    filepath.Join(tmpDir, "file.txt"),
			expectedPath: filepath.Join(tmpDir, "file_(1).txt"),
		},
		{
			name: "increments suffix when multiple conflicts exist",
			setup: func(t *testing.T, dir string) {
				for i := 0; i < 2; i++ {
					path := filepath.Join(dir, fmt.Sprintf("file%s.txt", func() string {
						if i == 0 {
							return ""
						}
						return fmt.Sprintf("_(%d)", i)
					}()))
					if err := os.WriteFile(path, []byte("content"), 0644); err != nil {
						t.Fatalf("failed to create test file: %v", err)
					}
				}
			},
			inputPath:    filepath.Join(tmpDir, "file.txt"),
			expectedPath: filepath.Join(tmpDir, "file_(2).txt"),
		},
		{
			name: "handles files without extension",
			setup: func(t *testing.T, dir string) {
				if err := os.WriteFile(filepath.Join(dir, "file"), []byte("original"), 0644); err != nil {
					t.Fatalf("failed to create test file: %v", err)
				}
			},
			inputPath:    filepath.Join(tmpDir, "file"),
			expectedPath: filepath.Join(tmpDir, "file_(1)"),
		},
		{
			name: "handles files with multiple dots in name",
			setup: func(t *testing.T, dir string) {
				if err := os.WriteFile(filepath.Join(dir, "file.backup.txt"), []byte("original"), 0644); err != nil {
					t.Fatalf("failed to create test file: %v", err)
				}
			},
			inputPath:    filepath.Join(tmpDir, "file.backup.txt"),
			expectedPath: filepath.Join(tmpDir, "file.backup_(1).txt"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create a fresh temp directory for this test
			testDir := t.TempDir()

			tt.setup(t, testDir)

			inputPath := filepath.Join(testDir, filepath.Base(tt.inputPath))
			result := GetNonConflictingPath(inputPath)

			expectedPath := filepath.Join(testDir, filepath.Base(tt.expectedPath))
			if result != expectedPath {
				t.Errorf("GetNonConflictingPath(%s) = %s, want %s", filepath.Base(inputPath), filepath.Base(result), filepath.Base(expectedPath))
			}
		})
	}
}

// --- Impl function tests (using dependency injection) ---

func makeManagedDeviceForImpl(t *testing.T, name string) *ManagedDevice {
	t.Helper()
	dir := t.TempDir()
	filesDir := filepath.Join(dir, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}
	return &ManagedDevice{
		Device: Device{
			Name:       name,
			MountPoint: dir,
			IsInternal: true,
		},
		DataDir:  dir,
		FilesDir: filesDir,
	}
}

func TestDeleteFilesImpl(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	testFile := filepath.Join(device.FilesDir, "to-delete.txt")
	if err := os.WriteFile(testFile, []byte("content"), 0644); err != nil {
		t.Fatal(err)
	}

	params := DeleteFilesParams{RootDir: "", FilePaths: []string{"to-delete.txt"}}
	_, err := DeleteFilesImpl(params, device, "")
	if err != nil {
		t.Fatalf("DeleteFilesImpl failed: %v", err)
	}
	if _, err := os.Stat(testFile); !os.IsNotExist(err) {
		t.Error("Expected file to be deleted")
	}
}

func TestCreateFolderImpl(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")

	params := CreateFolderParams{FolderDir: "", FolderName: "new-folder"}
	result, err := CreateFolderImpl(params, device, "")
	if err != nil {
		t.Fatalf("CreateFolderImpl failed: %v", err)
	}
	if result.CurrentDir != "" {
		t.Errorf("Expected empty CurrentDir, got %q", result.CurrentDir)
	}
	if _, err := os.Stat(filepath.Join(device.FilesDir, "new-folder")); err != nil {
		t.Errorf("Expected folder to exist: %v", err)
	}
}

func TestDownloadFileImpl(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	testFile := filepath.Join(device.FilesDir, "file.txt")
	if err := os.WriteFile(testFile, []byte("hello"), 0644); err != nil {
		t.Fatal(err)
	}

	params := DownloadFileParams{FilePath: "file.txt"}
	result, err := DownloadFileImpl(params, device, "")
	if err != nil {
		t.Fatalf("DownloadFileImpl failed: %v", err)
	}
	if result.FullPath != testFile {
		t.Errorf("Expected FullPath %s, got %s", testFile, result.FullPath)
	}
	if result.IsFolder {
		t.Error("Expected IsFolder false for a file")
	}
}

func TestDownloadFileImpl_NotFound(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	params := DownloadFileParams{FilePath: "nonexistent.txt"}
	_, err := DownloadFileImpl(params, device, "")
	if err == nil {
		t.Error("Expected error for non-existent file")
	}
}

func TestMoveFileImpl(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	src := filepath.Join(device.FilesDir, "source.txt")
	if err := os.WriteFile(src, []byte("move me"), 0644); err != nil {
		t.Fatal(err)
	}

	params := MoveFileParams{OldFilePath: "source.txt", NewFilePath: "dest.txt"}
	result, err := MoveFileImpl(params, device, device, device.FilesDir)
	if err != nil {
		t.Fatalf("MoveFileImpl failed: %v", err)
	}
	_ = result
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Error("Expected source file to be gone")
	}
	if _, err := os.Stat(filepath.Join(device.FilesDir, "dest.txt")); err != nil {
		t.Errorf("Expected dest file to exist: %v", err)
	}
}

func TestBackupToDeviceWithDevices(t *testing.T) {
	source := makeManagedDeviceForImpl(t, "source")
	target := makeManagedDeviceForImpl(t, "target")

	// Write some files to source
	if err := os.WriteFile(filepath.Join(source.FilesDir, "a.txt"), []byte("hello"), 0644); err != nil {
		t.Fatal(err)
	}
	subDir := filepath.Join(source.FilesDir, "sub")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(subDir, "b.txt"), []byte("world"), 0644); err != nil {
		t.Fatal(err)
	}

	params := BackupToDeviceParams{SourceDeviceSerial: "source", TargetDeviceSerial: "target"}
	result, err := BackupToDeviceWithDevices(params, source, target)
	if err != nil {
		t.Fatalf("BackupToDeviceWithDevices failed: %v", err)
	}
	if result.SourceDeviceSerial != "source" || result.TargetDeviceSerial != "target" {
		t.Errorf("Unexpected result: %+v", result)
	}
	if _, err := os.Stat(filepath.Join(target.FilesDir, "a.txt")); err != nil {
		t.Errorf("Expected a.txt in target: %v", err)
	}
	if _, err := os.Stat(filepath.Join(target.FilesDir, "sub", "b.txt")); err != nil {
		t.Errorf("Expected sub/b.txt in target: %v", err)
	}
}

func TestUploadFilesStreamed_SingleFile(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	content := []byte("hello world")
	body, contentType := makeMultipartBody(t, "files", "test.txt", content)
	r := multipart.NewReader(body, boundaryFromContentType(t, contentType))
	err := UploadFilesStreamedImpl(UploadFilesStreamedParams{
		Reader:       r,
		RootDir:      "",
		DeviceSerial: "",
	}, device, device.FilesDir)
	if err != nil {
		t.Fatalf("UploadFilesStreamedImpl failed: %v", err)
	}
	dest := filepath.Join(device.FilesDir, "test.txt")
	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("Expected uploaded file at %s: %v", dest, err)
	}
	if string(got) != string(content) {
		t.Errorf("Expected content %q, got %q", content, got)
	}
}

func TestUploadFilesStreamed_ConflictRename(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	existing := filepath.Join(device.FilesDir, "file.txt")
	if err := os.WriteFile(existing, []byte("old"), 0644); err != nil {
		t.Fatal(err)
	}
	content := []byte("new content")
	body, contentType := makeMultipartBody(t, "files", "file.txt", content)
	r := multipart.NewReader(body, boundaryFromContentType(t, contentType))
	err := UploadFilesStreamedImpl(UploadFilesStreamedParams{
		Reader:       r,
		RootDir:      "",
		DeviceSerial: "",
	}, device, device.FilesDir)
	if err != nil {
		t.Fatalf("UploadFilesStreamedImpl failed: %v", err)
	}
	old, _ := os.ReadFile(existing)
	if string(old) != "old" {
		t.Error("Original file was overwritten, expected conflict rename")
	}
	renamed := filepath.Join(device.FilesDir, "file_(1).txt")
	got, err := os.ReadFile(renamed)
	if err != nil {
		t.Fatalf("Expected renamed file at %s: %v", renamed, err)
	}
	if string(got) != string(content) {
		t.Errorf("Expected new content %q, got %q", content, got)
	}
}

func TestUploadFilesStreamed_SubDirectory(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "test-device")
	content := []byte("nested file")
	body, contentType := makeMultipartBody(t, "files", "notes.txt", content)
	r := multipart.NewReader(body, boundaryFromContentType(t, contentType))
	err := UploadFilesStreamedImpl(UploadFilesStreamedParams{
		Reader:       r,
		RootDir:      "docs/2024",
		DeviceSerial: "",
	}, device, device.FilesDir)
	if err != nil {
		t.Fatalf("UploadFilesStreamedImpl failed: %v", err)
	}
	dest := filepath.Join(device.FilesDir, "docs", "2024", "notes.txt")
	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("Expected uploaded file at %s: %v", dest, err)
	}
	if string(got) != string(content) {
		t.Errorf("Expected content %q, got %q", content, got)
	}
}

func TestBackupToDevice_SameSerial(t *testing.T) {
	source := makeManagedDeviceForImpl(t, "source")
	_, err := BackupToDeviceWithDevices(BackupToDeviceParams{
		SourceDeviceSerial: "same-serial",
		TargetDeviceSerial: "same-serial",
	}, source, source)
	if err == nil {
		t.Error("Expected error when source and target serials are the same")
	}
}

// makeMultipartBody builds a multipart/form-data body for testing uploads.
func makeMultipartBody(t *testing.T, field, filename string, content []byte) (*bytes.Buffer, string) {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	part, err := w.CreateFormFile(field, filename)
	if err != nil {
		t.Fatalf("failed to create form file: %v", err)
	}
	if _, err := part.Write(content); err != nil {
		t.Fatalf("failed to write form content: %v", err)
	}
	w.Close()
	return &buf, w.FormDataContentType()
}

func boundaryFromContentType(t *testing.T, ct string) string {
	t.Helper()
	parts := strings.SplitN(ct, "boundary=", 2)
	if len(parts) != 2 {
		t.Fatalf("unexpected content type: %s", ct)
	}
	return parts[1]
}

// TestStatDownloadAgreeOnDeviceDir is a regression guard for #1538.
//
// StatFileImpl and DownloadFileImpl must resolve a relative path against the
// SAME base directory. They previously diverged in the VFS layer: Stat used the
// managed device's FilesDir while Open re-derived from the default one, so on
// installs where those differ Stat succeeded (no 404) and Open found nothing —
// the download returned 200 with an empty body.
func TestStatDownloadAgreeOnDeviceDir(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "device-with-own-dir")
	// A default files dir that is deliberately NOT the device's.
	defaultDir := t.TempDir()

	testFile := filepath.Join(device.FilesDir, "interview.py")
	content := []byte("print('hello')\n")
	if err := os.WriteFile(testFile, content, 0644); err != nil {
		t.Fatal(err)
	}

	statRes, err := StatFileImpl(StatFileParams{FilePath: "interview.py"}, device, defaultDir)
	if err != nil {
		t.Fatalf("StatFileImpl: %v", err)
	}
	dlRes, err := DownloadFileImpl(DownloadFileParams{FilePath: "interview.py"}, device, defaultDir)
	if err != nil {
		t.Fatalf("DownloadFileImpl: %v", err)
	}

	if statRes.FullPath != dlRes.FullPath {
		t.Errorf("Stat and Download disagree on path:\n  stat=%s\n  down=%s",
			statRes.FullPath, dlRes.FullPath)
	}
	if statRes.FullPath != testFile {
		t.Errorf("expected %s, got %s", testFile, statRes.FullPath)
	}
	// The resolved file must actually be readable — the empty-body symptom.
	got, err := os.ReadFile(dlRes.FullPath)
	if err != nil {
		t.Fatalf("resolved download path is not readable: %v", err)
	}
	if len(got) != len(content) {
		t.Errorf("expected %d bytes, got %d", len(content), len(got))
	}
}

// TestStatFilePopulatesSizeAndModTime guards the secondary half of #1538:
// FileInfo.Size feeds Content-Length on the non-seeker download path, so a
// zero here would advertise an empty body.
func TestStatFilePopulatesSizeAndModTime(t *testing.T) {
	device := makeManagedDeviceForImpl(t, "sizes")
	content := []byte("0123456789")
	if err := os.WriteFile(filepath.Join(device.FilesDir, "f.bin"), content, 0644); err != nil {
		t.Fatal(err)
	}

	res, err := StatFileImpl(StatFileParams{FilePath: "f.bin"}, device, "")
	if err != nil {
		t.Fatalf("StatFileImpl: %v", err)
	}
	if res.Size != int64(len(content)) {
		t.Errorf("expected Size %d, got %d", len(content), res.Size)
	}
	if res.ModTime.IsZero() {
		t.Error("expected non-zero ModTime")
	}
}

package storageutil

import (
	"os"
	"path/filepath"
	"strings"
)

type Device struct {
	Name           string            `json:"name"`
	DevicePath     string            `json:"devicePath"`        // e.g., "/dev/disk3s5"
	MountPoint     string            `json:"mountPoint"`        // e.g., "/", "/Volumes/External"
	FileSystem     string            `json:"fileSystem"`        // e.g., "APFS", "ext4", "NTFS"
	TotalBytes     uint64            `json:"totalBytes"`        // Total capacity in bytes
	UsedBytes      uint64            `json:"usedBytes"`         // Used space in bytes
	AvailableBytes uint64            `json:"availableBytes"`    // Available space in bytes
	IsInternal     bool              `json:"isInternal"`        // True if internal drive
	Model          string            `json:"model"`             // Device model name
	Categories     map[string]uint64 `json:"categories"`        // Simple heuristic breakdown in bytes
	UsbInfo        UsbDevice         `json:"usbInfo,omitempty"` // USB-specific info, if available
	// NeedsRestart marks a plugged-in drive Quark sees but cannot mount until
	// it restarts: its /dev node is missing, as for a drive plugged into a
	// container after it started (#4018). See [ErrNeedsRestart].
	NeedsRestart bool `json:"needsRestart,omitempty"`
}

// ApplySimpleCategorization applies a simple heuristic categorization for UI display
// System volumes get a basic breakdown, external drives show as "other"
func (d *Device) ApplySimpleCategorization() {
	// Real categorization: traverse the mount point and sum file sizes by type
	d.Categories = make(map[string]uint64)

	// Define file extensions for categories
	docExts := map[string]struct{}{
		".pdf": {}, ".doc": {}, ".docx": {}, ".qdoc": {}, ".txt": {}, ".md": {}, ".xls": {}, ".xlsx": {}, ".ppt": {}, ".pptx": {}, ".csv": {},
	}
	mediaExts := map[string]struct{}{
		".jpg": {}, ".jpeg": {}, ".png": {}, ".gif": {}, ".bmp": {}, ".mp4": {}, ".mov": {}, ".avi": {}, ".mkv": {}, ".mp3": {}, ".wav": {}, ".flac": {}, ".aac": {}, ".ogg": {}, ".m4a": {},
	}
	backupExts := map[string]struct{}{
		".bak": {}, ".backup": {}, ".zip": {}, ".tar": {}, ".gz": {}, ".rar": {},
	}

	// Traverse the mount point
	filesDir, err := GetFilesDirForDevice(d.MountPoint)
	if err != nil {
		return
	}
	docBytes := uint64(0)
	mediaBytes := uint64(0)
	backupBytes := uint64(0)
	otherBytes := uint64(0)

	// The callback skips per-entry errors and always returns nil, so the walk
	// itself cannot fail; a partial tally is better than none.
	_ = filepath.Walk(filesDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip errors
		}
		if info.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(info.Name()))
		size := uint64(info.Size())
		if _, ok := docExts[ext]; ok {
			docBytes += size
		} else if _, ok := mediaExts[ext]; ok {
			mediaBytes += size
		} else if _, ok := backupExts[ext]; ok {
			backupBytes += size
		} else {
			otherBytes += size
		}
		return nil
	})

	// Add system category for system volumes: system = total - categorized - free
	categorized := docBytes + mediaBytes + backupBytes + otherBytes
	total := d.TotalBytes
	free := d.AvailableBytes
	systemBytes := uint64(0)
	if total > categorized+free {
		systemBytes = total - categorized - free
	}

	if docBytes > 0 {
		d.Categories["documents"] = docBytes
	}
	if mediaBytes > 0 {
		d.Categories["media"] = mediaBytes
	}
	if backupBytes > 0 {
		d.Categories["backups"] = backupBytes
	}
	if otherBytes > 0 {
		d.Categories["other"] = otherBytes
	}
	if systemBytes > 0 {
		d.Categories["system"] = systemBytes
	}
}

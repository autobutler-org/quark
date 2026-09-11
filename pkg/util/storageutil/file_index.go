package storageutil

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// IndexedFile is a lightweight record stored in the FileIndex.
type IndexedFile struct {
	Name         string // filename only (no directory)
	RelPath      string // relative path from FilesDir root (e.g. "docs/notes.txt")
	FilesDir     string // absolute path to the device's FilesDir
	DeviceSerial string // empty = internal
}

// FileIndex is a thread-safe in-memory index of all files across managed devices.
// It is built once at startup and updated incrementally via HandleEvent.
type FileIndex struct {
	mu    sync.RWMutex
	files map[string]IndexedFile // key: FilesDir + "\x00" + RelPath
}

// NewFileIndex creates and returns an empty FileIndex.
func NewFileIndex() *FileIndex {
	return &FileIndex{files: make(map[string]IndexedFile)}
}

// key returns the map key for a given filesDir + relPath.
func (idx *FileIndex) key(filesDir, relPath string) string {
	return filesDir + "\x00" + relPath
}

// Build walks all managed devices and populates the index.
func (idx *FileIndex) Build(devices []ManagedDevice) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.files = make(map[string]IndexedFile)
	for _, dev := range devices {
		serial := ""
		if dev.UsbInfo != nil {
			serial = dev.UsbInfo.GetSerial()
		}
		_ = filepath.WalkDir(dev.FilesDir, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if path != dev.FilesDir && IsInternalName(d.Name()) {
				if d.IsDir() {
					return fs.SkipDir
				}
				return nil
			}
			if d.IsDir() {
				return nil
			}
			rel, relErr := filepath.Rel(dev.FilesDir, path)
			if relErr != nil {
				return nil
			}
			rel = filepath.ToSlash(rel)
			f := IndexedFile{
				Name:         d.Name(),
				RelPath:      rel,
				FilesDir:     dev.FilesDir,
				DeviceSerial: serial,
			}
			idx.files[idx.key(dev.FilesDir, rel)] = f
			return nil
		})
	}
}

// Search returns all indexed files whose Name contains query (case-insensitive).
// If query is empty, returns all files.
// If serials is non-empty, only returns files from those devices.
func (idx *FileIndex) Search(query string, serials map[string]bool) []IndexedFile {
	lq := strings.ToLower(query)
	idx.mu.RLock()
	defer idx.mu.RUnlock()
	out := make([]IndexedFile, 0)
	for _, f := range idx.files {
		if len(serials) > 0 && !serials[f.DeviceSerial] {
			continue
		}
		if query == "" || strings.Contains(strings.ToLower(f.Name), lq) {
			out = append(out, f)
		}
	}
	return out
}

// HandleAdd adds or updates a file in the index.
func (idx *FileIndex) HandleAdd(filesDir, relPath, serial string) {
	name := filepath.Base(relPath)
	idx.mu.Lock()
	defer idx.mu.Unlock()
	idx.files[idx.key(filesDir, relPath)] = IndexedFile{
		Name:         name,
		RelPath:      relPath,
		FilesDir:     filesDir,
		DeviceSerial: serial,
	}
}

// HandleDelete removes a file from the index.
func (idx *FileIndex) HandleDelete(filesDir, relPath string) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	delete(idx.files, idx.key(filesDir, relPath))
}

// HandleMove renames a file in the index.
func (idx *FileIndex) HandleMove(filesDir, oldRelPath, newRelPath, serial string) {
	idx.mu.Lock()
	defer idx.mu.Unlock()
	delete(idx.files, idx.key(filesDir, oldRelPath))
	idx.files[idx.key(filesDir, newRelPath)] = IndexedFile{
		Name:         filepath.Base(newRelPath),
		RelPath:      newRelPath,
		FilesDir:     filesDir,
		DeviceSerial: serial,
	}
}

// GetManagedDevicesFunc is the signature of StorageService.GetManagedDevices,
// accepted by Watch so the index doesn't depend on StorageService directly.
type GetManagedDevicesFunc func() ([]ManagedDevice, error)

// BuildAndWatch builds the index from the current filesystem state, then
// starts a background goroutine that subscribes to the event bus and keeps
// the index current on upload/delete/move/new_folder events.
//
// Call this once at startup. The goroutine runs until the event bus channel
// is closed (i.e. when the bus is shut down).
func (idx *FileIndex) BuildAndWatch(bus *eventbus.Bus, getDevices GetManagedDevicesFunc) {
	if devices, err := getDevices(); err == nil {
		idx.Build(devices)
	}

	go func() {
		events, unsub := bus.Subscribe("file-index")
		defer unsub()
		for evt := range events {
			devices, err := getDevices()
			if err != nil {
				continue
			}
			filesDir, serial := resolveDevice(devices, evt.DeviceSerial)
			if filesDir == "" {
				continue
			}
			switch evt.Kind {
			case eventbus.EventUpload, eventbus.EventNewFolder:
				idx.HandleAdd(filesDir, evt.Path, serial)
			case eventbus.EventDelete:
				idx.HandleDelete(filesDir, evt.Path)
			case eventbus.EventMove:
				idx.HandleMove(filesDir, evt.Path, evt.NewPath, serial)
			}
		}
	}()
}

// resolveDevice finds the FilesDir and serial for the given sourceSerial.
// If sourceSerial is empty or no USB device matches, falls back to the
// internal (non-USB) device.
func resolveDevice(devices []ManagedDevice, sourceSerial string) (filesDir, serial string) {
	for _, d := range devices {
		s := ""
		if d.UsbInfo != nil {
			s = d.UsbInfo.GetSerial()
		}
		if s == sourceSerial && sourceSerial != "" {
			return d.FilesDir, s
		}
	}
	// Fall back to internal device
	for _, d := range devices {
		if d.UsbInfo == nil {
			return d.FilesDir, ""
		}
	}
	return "", ""
}

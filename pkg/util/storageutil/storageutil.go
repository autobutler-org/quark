package storageutil

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"

	"golang.org/x/sys/unix"
)

type FileType string

var ErrPathNotFound = errors.New("path not found")

const (
	FileTypeAudio     FileType = "audio"
	FileTypeDocx      FileType = "docx"
	FileTypeEpub      FileType = "epub"
	FileTypeFolder    FileType = "folder"
	FileTypeGeneric   FileType = "generic"
	FileTypeImage     FileType = "image"
	FileTypePDF       FileType = "pdf"
	FileTypeQdoc      FileType = "qdoc"
	FileTypeQsheet    FileType = "qsheet"
	FileTypeSlideshow FileType = "slideshow"
	FileTypeSvg       FileType = "svg"
	FileTypeVideo     FileType = "video"
	FileTypeXlsx      FileType = "xlsx"
	FileTypeSpacer    FileType = "spacer"
	FileTypeArchive   FileType = "archive"
	FileTypeText      FileType = "text"
	FileTypeCode      FileType = "code"
)

func ImageMIMETypeFromExtension(extension string) string {
	normalizedExt := strings.TrimSpace(strings.ToLower(extension))
	if normalizedExt == "" {
		return "application/octet-stream"
	}
	if !strings.HasPrefix(normalizedExt, ".") {
		normalizedExt = "." + normalizedExt
	}

	switch normalizedExt {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".svg":
		return "image/svg+xml"
	case ".bmp":
		return "image/bmp"
	case ".tiff", ".tif":
		return "image/tiff"
	case ".heic", ".heif":
		return "image/heic"
	case ".avif":
		return "image/avif"
	case ".cr2":
		return "image/x-canon-cr2"
	case ".cr3":
		return "image/x-canon-cr3"
	case ".nef":
		return "image/x-nikon-nef"
	case ".arw":
		return "image/x-sony-arw"
	case ".dng":
		return "image/x-adobe-dng"
	case ".orf":
		return "image/x-olympus-orf"
	case ".rw2":
		return "image/x-panasonic-rw2"
	case ".raw":
		return "image/x-raw"
	default:
		return "application/octet-stream"
	}
}

func IsRawImageExtension(extension string) bool {
	switch strings.TrimSpace(strings.ToLower(extension)) {
	case ".raw", ".cr2", ".cr3", ".nef", ".arw", ".dng", ".orf", ".rw2":
		return true
	default:
		return false
	}
}

func VideoMIMETypeFromExtension(extension string) string {
	normalizedExt := strings.TrimSpace(strings.ToLower(extension))
	if normalizedExt == "" {
		return "application/octet-stream"
	}
	if !strings.HasPrefix(normalizedExt, ".") {
		normalizedExt = "." + normalizedExt
	}

	switch normalizedExt {
	case ".mp4":
		return "video/mp4"
	case ".m4v":
		return "video/x-m4v"
	case ".webm":
		return "video/webm"
	case ".ogv":
		return "video/ogg"
	case ".avi":
		return "video/x-msvideo"
	case ".mov":
		return "video/quicktime"
	case ".mpeg", ".mpg":
		return "video/mpeg"
	case ".mkv":
		return "video/x-matroska"
	case ".3gp":
		return "video/3gpp"
	case ".3g2":
		return "video/3gpp2"
	case ".wmv":
		return "video/x-ms-wmv"
	case ".flv":
		return "video/x-flv"
	case ".ts":
		return "video/mp2t"
	default:
		return "application/octet-stream"
	}
}

func AudioMIMETypeFromExtension(extension string) string {
	normalizedExt := strings.TrimSpace(strings.ToLower(extension))
	if normalizedExt == "" {
		return "application/octet-stream"
	}
	if !strings.HasPrefix(normalizedExt, ".") {
		normalizedExt = "." + normalizedExt
	}

	switch normalizedExt {
	case ".mp3":
		return "audio/mpeg"
	case ".wav":
		return "audio/wav"
	case ".flac":
		return "audio/flac"
	case ".aac":
		return "audio/aac"
	case ".ogg":
		return "audio/ogg"
	case ".m4a":
		return "audio/mp4"
	case ".wma":
		return "audio/x-ms-wma"
	case ".opus":
		return "audio/opus"
	default:
		return "application/octet-stream"
	}
}

func DetermineFileTypeFromPath(filePath string) FileType {
	// Empty string or "/" represents a folder
	if filePath == "" || filePath == "/" {
		return FileTypeFolder
	}

	ext := strings.ToLower(filepath.Ext(filePath))
	switch ext {
	case ".pdf":
		return FileTypePDF
	case ".pptx", ".ppt":
		return FileTypeSlideshow
	// SVG is XML, not a raster codec: it cannot be decoded, resized into a
	// thumbnail, or converted to JPEG the way the formats below can, so it
	// gets its own type rather than reaching those paths and failing (#1806).
	case ".svg":
		return FileTypeSvg
	case ".png", ".jpg", ".jpeg", ".gif", ".heic", ".heif", ".webp", ".bmp", ".tiff", ".tif", ".avif",
		// Raw camera formats
		".raw", ".cr2", ".cr3", ".nef", ".nrw", ".arw", ".srf", ".sr2",
		".orf", ".rw2", ".pef", ".dng", ".raf", ".rwl", ".x3f":
		return FileTypeImage
	case ".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus":
		return FileTypeAudio
	case ".mp4", ".m4v", ".webm", ".ogv", ".avi", ".mov", ".mkv", ".wmv", ".flv", ".3gp", ".3g2", ".mpeg", ".mpg", ".ts":
		return FileTypeVideo
	case ".epub":
		return FileTypeEpub
	case ".qdoc":
		return FileTypeQdoc
	case ".qsheet":
		return FileTypeQsheet
	case ".docx":
		return FileTypeDocx
	// .xlsm is the same OOXML package as .xlsx with macros attached, so it
	// reads identically. .xls is deliberately absent: the legacy binary
	// format is not OOXML and needs a different parser entirely (#1741).
	case ".xlsx", ".xlsm":
		return FileTypeXlsx
	case ".zip", ".rar", ".tar", ".gz", ".tgz", ".7z":
		return FileTypeArchive
	case ".txt", ".md", ".markdown", ".rst", ".log", ".env":
		return FileTypeText
	case ".json", ".yaml", ".yml", ".toml", ".xml", ".ini", ".cfg", ".conf",
		// Web
		".html", ".htm", ".css", ".scss", ".sass", ".less",
		// JavaScript / TypeScript (.ts is MPEG transport stream — stays as video)
		".js", ".mjs", ".cjs", ".jsx", ".tsx",
		// Go
		".go",
		// Systems languages
		".c", ".h", ".cpp", ".cc", ".cxx", ".hpp", ".cs", ".rs", ".zig",
		// JVM
		".java", ".kt", ".kts", ".scala", ".groovy",
		// Scripting
		".py", ".rb", ".php", ".lua", ".perl", ".pl",
		// Shell
		".sh", ".bash", ".zsh", ".fish",
		// Mobile
		".swift", ".dart", ".m",
		// Data / query
		".sql", ".graphql", ".gql",
		// Config / infra
		".tf", ".hcl", ".dockerfile", ".makefile",
		// Lisp family
		".lisp", ".cl", ".scm", ".clj", ".cljs", ".ex", ".exs", ".erl", ".hrl":
		return FileTypeCode
	default:
		stat, err := os.Stat(filePath)
		if err == nil && stat != nil {
			if stat.IsDir() {
				return FileTypeFolder
			}
		}
		return FileTypeGeneric
	}
}

func DetermineFileType(rootDir string, file *DeviceFileInfo) FileType {
	if file == nil {
		return FileTypeSpacer
	}
	if file.IsDir() {
		return FileTypeFolder
	}
	filesDir, err := GetFilesDir()
	if err != nil {
		return FileTypeGeneric
	}
	stat, err := os.Stat(filepath.Join(filesDir, rootDir, file.Name()))
	if err != nil || stat == nil {
		return FileTypeGeneric // If we can't stat the file, treat it as generic
	}
	return DetermineFileTypeFromPath(file.Name())
}

func SizeBytesToString(size_bytes int64) string {
	if size_bytes < 1024 {
		return fmt.Sprintf("%d B", size_bytes)
	} else if size_bytes < 1024*1024 {
		return fmt.Sprintf("%.1f KB", float64(size_bytes)/1024)
	} else if size_bytes < 1024*1024*1024 {
		return fmt.Sprintf("%.1f MB", float64(size_bytes)/(1024*1024))
	} else if size_bytes < 1024*1024*1024*1024 {
		return fmt.Sprintf("%.1f GB", float64(size_bytes)/(1024*1024*1024))
	}
	return fmt.Sprintf("%.1f TB", float64(size_bytes)/(1024*1024*1024*1024))
}

func GetFolderSize(dir string) (int64, error) {
	var size int64
	err := filepath.Walk(dir, func(_ string, info fs.FileInfo, err error) error {
		if err != nil {
			return err // coverage: ignore - requires filesystem permission errors during walk
		}
		if !info.IsDir() {
			size += info.Size()
		}
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("error calculating folder size for %s: %w", dir, err) // coverage: ignore - requires filesystem permission errors during walk
	}
	return size, nil
}

func StatFilesInDir(dir string, deviceName string, devicePath string, deviceSerial string) ([]*DeviceFileInfo, error) {
	entries, err := os.ReadDir(dir)
	files := make([]*DeviceFileInfo, 0, len(entries))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("%w: %s", ErrPathNotFound, dir)
		}
		return nil, fmt.Errorf("error reading the directory %s: %w", dir, err) // coverage: ignore - requires filesystem permission errors
	}
	for _, entry := range entries {
		var fileInfo fs.FileInfo
		fullPath := filepath.Join(dir, entry.Name())
		if entry.IsDir() {
			folderSize, err := GetFolderSize(fullPath)
			if err != nil {
				return nil, fmt.Errorf("error getting size for folder %s: %w", entry.Name(), err) // coverage: ignore - requires filesystem errors during folder traversal
			}
			fileInfo = NewCustomFileInfo().WithName(entry.Name()).WithSize(folderSize)
		} else {
			info, err := entry.Info()
			if err != nil {
				return nil, fmt.Errorf("error getting info for file %s: %w", entry.Name(), err) // coverage: ignore - requires filesystem errors on stat
			}
			fileInfo = info
		}
		// Wrap in DeviceFileInfo with device info
		files = append(files, NewDeviceFileInfo(fileInfo, deviceName, devicePath, fullPath, deviceSerial))
	}
	// Sort files by directory first, then by name
	slices.SortFunc(files, func(a, b *DeviceFileInfo) int {
		if a.IsDir() && !b.IsDir() {
			return -1 // a is a directory, b is a file
		} else if !a.IsDir() && b.IsDir() {
			return 1 // coverage: ignore - a is a file, b is a directory
		}
		return strings.Compare(a.Name(), b.Name())
	})
	return files, nil
}

// WalkedFile is one entry produced by WalkFilesInDir: the entry itself plus
// its path relative to the directory the walk started from.
type WalkedFile struct {
	Info *DeviceFileInfo
	// RelPath is slash-separated and relative to the walk root, e.g.
	// "sub/deep.qdoc". StatFilesInDir's single-level listing only ever needs
	// a base name, which is why callers that walk need this instead.
	RelPath string
}

// WalkFilesInDir recursively walks dir and calls visit for every entry beneath
// it, in lexical order, parents before children. The root itself is not
// visited.
//
// visit may return fs.SkipDir to skip the current directory's contents or
// fs.SkipAll to stop the walk; both are reported as success. Any other error
// stops the walk and is returned.
//
// Symlinks are reported but never followed, so the walk cannot escape dir or
// loop — the same containment the single-level StatFilesInDir listing has.
//
// Directory entries carry the filesystem's own size rather than the size of
// their contents. StatFilesInDir computes subtree sizes with GetFolderSize,
// which is a full walk per directory and so quadratic when the caller is
// already walking; LocalVFS reports raw directory sizes for the same reason.
func WalkFilesInDir(
	ctx context.Context,
	dir string,
	deviceName string,
	devicePath string,
	deviceSerial string,
	visit func(WalkedFile) error,
) error {
	root := filepath.Clean(dir)
	if _, err := os.Stat(root); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("%w: %s", ErrPathNotFound, dir)
		}
		return fmt.Errorf("error reading the directory %s: %w", dir, err)
	}

	return filepath.WalkDir(root, func(fullPath string, entry fs.DirEntry, err error) error {
		if err != nil {
			// An unreadable subdirectory must not abort the whole listing —
			// skip it and keep walking the rest of the tree.
			if entry != nil && entry.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if ctx != nil && ctx.Err() != nil {
			return ctx.Err()
		}
		if fullPath == root {
			return nil
		}

		rel, relErr := filepath.Rel(root, fullPath)
		if relErr != nil {
			return nil // coverage: ignore - WalkDir only yields paths under root
		}
		rel = filepath.ToSlash(rel)

		info, infoErr := entry.Info()
		if infoErr != nil {
			// The entry vanished mid-walk; nothing to report for it.
			return nil // coverage: ignore - requires a concurrent delete
		}

		return visit(WalkedFile{
			Info:    NewDeviceFileInfo(info, deviceName, devicePath, fullPath, deviceSerial),
			RelPath: rel,
		})
	})
}

// GetNonConflictingPath returns a file path that doesn't conflict with existing files.
// If the target path already exists, it appends _(n) before the file extension,
// incrementing n until a non-existent path is found.
// For example: file.txt -> file_(1).txt -> file_(2).txt, etc.
func GetNonConflictingPath(targetPath string) string {
	if _, err := os.Stat(targetPath); os.IsNotExist(err) {
		// File doesn't exist, return the target path as-is
		return targetPath
	}

	// File exists, need to find a non-conflicting name
	ext := filepath.Ext(targetPath)
	nameWithoutExt := targetPath[:len(targetPath)-len(ext)]
	dir := filepath.Dir(targetPath)

	i := 1
	for {
		newPath := filepath.Join(dir, fmt.Sprintf("%s_(%d)%s", filepath.Base(nameWithoutExt), i, ext))
		if _, err := os.Stat(newPath); os.IsNotExist(err) {
			return newPath
		}
		i++
	}
}

// SetupFilesDir prepares the system storage root. Called once on startup.
func SetupFilesDir() error {
	return setupFilesDirIn(GetDataDir())
}

// GetDeviceInfoForPath returns the device name and device path for a given file path
// This is used to populate device info even for single-device scenarios
func GetDeviceInfoForPath(path string) (deviceName string, devicePath string) {
	// Get the absolute path
	absPath, err := filepath.Abs(path)
	if err != nil {
		return "", "" // coverage: ignore - requires filepath.Abs to fail
	}

	// Try to detect the device this path is on
	// This is a best-effort approach using the storage package
	// Import note: we can't import storage here due to circular dependency,
	// so we'll use a simple heuristic based on mount points

	// For now, use a simple approach: check if path starts with common mount points
	// This could be enhanced later to use actual device detection
	switch runtime.GOOS {
	case "darwin": // coverage: ignore - Not run in CI
		// On macOS, check if it's under /Volumes/
		if strings.HasPrefix(absPath, "/Volumes/") {
			parts := strings.Split(absPath, "/")
			if len(parts) >= 3 {
				deviceName = parts[2] // Volume name
				devicePath = filepath.Join("/Volumes", parts[2])
				return
			}
		}
		// Default to "Macintosh HD" for main drive
		deviceName = "Macintosh HD"
		devicePath = "/"
	case "linux": // coverage: ignore - Not run in mac dev environments
		// On Linux, check if it's under /media/ or /mnt/
		if strings.HasPrefix(absPath, "/media/") { // coverage: ignore
			parts := strings.Split(absPath, "/")
			if len(parts) >= 4 { // coverage: ignore
				deviceName = parts[3] // Device name
				devicePath = filepath.Join("/media", parts[2], parts[3])
				return
			}
		} else if strings.HasPrefix(absPath, "/mnt/") { // coverage: ignore
			parts := strings.Split(absPath, "/")
			if len(parts) >= 3 { // coverage: ignore
				deviceName = parts[2] // Mount point name
				devicePath = filepath.Join("/mnt", parts[2])
				return
			}
		}
		// Default to root filesystem
		deviceName = "Root" // coverage: ignore
		devicePath = "/"    // coverage: ignore
	default: // coverage: ignore - unsupported OS
		deviceName = "Default"
		devicePath = "/"
	}

	return
}

func GetAvailableSpaceInBytes(fileDir string) uint64 {
	var stat unix.Statfs_t
	if err := unix.Statfs(fileDir, &stat); err != nil {
		return 0
	}
	return stat.Bavail * uint64(stat.Bsize)
}

// StatFilesInMultipleDirs reads files from multiple directories and merges them
// into a unified view, preserving device information for each file
func StatFilesInMultipleDirs(dirsWithDeviceInfo []DirWithDevice) ([]*DeviceFileInfo, error) {
	// Map to merge files by name
	fileMap := make(map[string][]*DeviceFileInfo)

	// Read files from each device
	for _, dirInfo := range dirsWithDeviceInfo {
		entries, err := os.ReadDir(dirInfo.Dir)
		if err != nil {
			// Skip directories that don't exist or can't be read
			continue
		}

		for _, entry := range entries {
			var fileInfo fs.FileInfo
			fullPath := filepath.Join(dirInfo.Dir, entry.Name())

			if entry.IsDir() {
				folderSize, err := GetFolderSize(fullPath)
				if err != nil {
					continue // coverage: ignore - requires filesystem errors during folder size calculation
				}
				fileInfo = NewCustomFileInfo().WithName(entry.Name()).WithSize(folderSize)
			} else {
				info, err := entry.Info()
				if err != nil {
					continue // coverage: ignore - requires filesystem errors on stat
				}
				fileInfo = info
			}

			// Wrap with device information
			deviceFileInfo := NewDeviceFileInfo(fileInfo, dirInfo.DeviceName, dirInfo.DevicePath, fullPath, dirInfo.DeviceSerial)

			// Add to map (multiple devices may have same file name)
			fileMap[entry.Name()] = append(fileMap[entry.Name()], deviceFileInfo)
		}
	}

	// Flatten the map to a slice
	var files []*DeviceFileInfo
	for _, fileList := range fileMap {
		files = append(files, fileList...)
	}

	// Sort files by directory first, then by name
	slices.SortFunc(files, func(a, b *DeviceFileInfo) int {
		if a.IsDir() && !b.IsDir() {
			return -1 // coverage: ignore - a is a directory, b is a file
		} else if !a.IsDir() && b.IsDir() {
			return 1
		}
		return strings.Compare(a.Name(), b.Name())
	})

	return files, nil
}

// DirWithDevice associates a directory path with its device information
type DirWithDevice struct {
	Dir          string
	DeviceName   string
	DevicePath   string
	DeviceSerial string
}

// DoesFileExist checks if a file exists at the given path
// Returns true if the file exists, false otherwise
func DoesFileExist(fullPath string) bool {
	_, err := os.Stat(fullPath)
	return err == nil
}

// FindFileAcrossDevices searches for a file across multiple devices
// Returns the full path to the first matching file
func FindFileAcrossDevices(dirsWithDevice []DirWithDevice, relPath string) (string, error) {
	for _, dirInfo := range dirsWithDevice {
		fullPath := filepath.Join(dirInfo.Dir, relPath)
		if DoesFileExist(fullPath) {
			return fullPath, nil
		}
	}
	return "", fmt.Errorf("file not found: %s", relPath)
}

// InitializeDeviceDataDir creates the quark data directory structure on a device
func InitializeDeviceDataDir(mountPoint string) error {
	dataDir := GetDataDirForDevice(mountPoint)
	filesDir := ConstructFilesDir(dataDir)

	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return err // coverage: ignore - requires filesystem permission errors
	}

	return nil
}

func FindUsbDeviceBySerial(serial string) (UsbDevice, error) {
	usbDevices, err := ListUsbDevices(true)
	if err != nil {
		return nil, err
	}
	for _, device := range usbDevices {
		if device.GetSerial() == serial {
			return device, nil
		}
	}
	return nil, fmt.Errorf("USB device with serial %q not found", serial)
}

// SafeJoin joins base with the provided path segments and returns an error if
// the resulting path would escape the base directory (path traversal guard).
func SafeJoin(base string, parts ...string) (string, error) {
	return safeJoin(base, parts...)
}

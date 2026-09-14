package fileutil

import (
	"context"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const defaultRecentLimit = 20
const maxRecentLimit = 200

// ListFilesParams lists one directory level, merged across the devices the
// serials select.
type ListFilesParams struct {
	// Ctx bounds the VFS listing.
	Ctx context.Context
	// Registry serves the listing when it is present; nil walks the devices.
	Registry vfs.Registry
	// Storage enumerates the managed devices for the device walk.
	Storage *storageutil.StorageService
	// RootDir is the directory to list, empty for the storage root.
	RootDir string
	// Serials scopes the listing to those devices, empty for all of them.
	Serials []string
}

// ListFilesResult is one directory level.
type ListFilesResult struct {
	Files []FileNode
}

// ListFiles returns the direct children of RootDir.
func ListFiles(params ListFilesParams) (ListFilesResult, error) {
	// Use VFS when available — passes SerialFilter so the adapter handles device scoping.
	if params.Registry != nil {
		files, err := listFilesVFS(params.Ctx, params.Registry, params.RootDir, params.Serials)
		if err != nil {
			return ListFilesResult{}, err
		}
		return ListFilesResult{Files: files}, nil
	}

	devices, err := params.Storage.GetManagedDevices()
	if err != nil {
		return ListFilesResult{}, err
	}
	selectedDevices := SelectDevices(devices, params.Serials)
	if len(params.Serials) > 0 && len(selectedDevices) == 0 {
		return ListFilesResult{Files: []FileNode{}}, nil
	}
	files, err := listFilesOnDevices(params.RootDir, selectedDevices)
	if err != nil {
		return ListFilesResult{}, err
	}
	return ListFilesResult{Files: files}, nil
}

// listFilesVFS lists files via the VFS registry, optionally scoped to specific device serials.
func listFilesVFS(ctx context.Context, registry vfs.Registry, rootDir string, serials []string) ([]FileNode, error) {
	fsys, ok := registry.Get(filesNamespace)
	if !ok {
		return nil, ErrNoFilesNamespace
	}
	infos, err := fsys.List(ctx, rootDir, &vfs.ListFilter{Recursive: false, SerialFilter: serials})
	if err != nil {
		if err == vfs.ErrNotFound {
			return nil, notFoundf("folder not found: %s", rootDir)
		}
		return nil, err
	}
	result := make([]FileNode, len(infos))
	for i, fi := range infos {
		result[i] = FileNode{
			Name:         fi.Name,
			Size:         fi.Size,
			IsDir:        fi.IsDir,
			DeviceName:   fi.DeviceName,
			DevicePath:   fi.DevicePath,
			DirPath:      fi.Path,
			FullPath:     fi.Path,
			DeviceSerial: fi.DeviceSerial,
			FileType:     string(storageutil.DetermineFileTypeFromPath(fi.Path)),
		}
	}
	return result, nil
}

// listFilesOnDevices lists files across the given devices (serial-scoped fallback).
func listFilesOnDevices(rootDir string, devices []storageutil.ManagedDevice) ([]FileNode, error) {
	var allFiles []*storageutil.DeviceFileInfo
	sawListing := false
	sawNotFound := false
	for _, device := range devices {
		filesDir := device.FilesDir
		fullPathDir, err := storageutil.SafeJoin(filesDir, rootDir)
		if err != nil {
			return nil, err
		}
		files, err := storageutil.StatFilesInDir(fullPathDir, device.Name, device.DataDir, DeviceSerial(device))
		if err != nil {
			if rootDir != "" {
				sawNotFound = true
			}
			continue
		}
		sawListing = true
		allFiles = append(allFiles, files...)
	}
	if rootDir != "" && sawNotFound && !sawListing {
		return nil, notFoundf("folder not found: %s", rootDir)
	}
	// Only deduplicate folders (isDir), show all files across all devices
	seenFolders := make(map[string]bool)
	filteredFiles := make([]*storageutil.DeviceFileInfo, 0, len(allFiles))
	for _, file := range allFiles {
		name := file.FileInfo.Name()
		if file.IsDir() {
			if seenFolders[name] {
				continue
			}
			seenFolders[name] = true
		}
		filteredFiles = append(filteredFiles, file)
	}
	allFiles = filteredFiles
	result := make([]FileNode, len(allFiles))
	for i, file := range allFiles {
		result[i] = FileNode{
			Name:         file.Name(),
			Size:         file.Size(),
			IsDir:        file.IsDir(),
			DeviceName:   file.DeviceName,
			DevicePath:   file.DevicePath,
			DirPath:      filepath.Join(rootDir, file.Name()),
			FullPath:     file.FullPath,
			DeviceSerial: file.DeviceSerial,
			FileType:     string(storageutil.DetermineFileTypeFromPath(file.FullPath)),
		}
	}
	return result, nil
}

// ParseRecentLimit reads the ?limit= query parameter for the recent listing,
// falling back to the default for anything missing or unparseable and clamping
// the page size to the maximum.
func ParseRecentLimit(raw string) int {
	if raw == "" {
		raw = strconv.Itoa(defaultRecentLimit)
	}
	limit, err := strconv.Atoi(raw)
	if err != nil || limit <= 0 {
		limit = defaultRecentLimit
	}
	if limit > maxRecentLimit {
		limit = maxRecentLimit
	}
	return limit
}

// ListRecentParams describes the newest-first listing across every managed device.
type ListRecentParams struct {
	// Ctx bounds the VFS listing and the device walk.
	Ctx context.Context
	// Registry serves the listing when the files namespace is registered.
	Registry vfs.Registry
	// Storage enumerates the managed devices for the fallback walk.
	Storage *storageutil.StorageService
	// Serials scopes the listing to those devices, empty for all of them.
	Serials []string
	// Limit caps how many files come back.
	Limit int
}

// ListRecentResult is the newest-first page of files.
type ListRecentResult struct {
	Files []FileNodeWithTime
}

// ListRecent returns the most recently modified files, newest first.
func ListRecent(params ListRecentParams) (ListRecentResult, error) {
	var allFiles []FileNodeWithTime

	// VFS path: use recursive list when registry is available.
	if fsys := FilesVFS(params.Registry); fsys != nil {
		infos, err := fsys.List(params.Ctx, "", &vfs.ListFilter{Recursive: true, SerialFilter: params.Serials})
		if err != nil {
			return ListRecentResult{}, err
		}
		for _, fi := range infos {
			if fi.IsDir {
				continue
			}
			allFiles = append(allFiles, FileNodeWithTime{
				FileNode: FileNode{
					Name:         fi.Name,
					Size:         fi.Size,
					IsDir:        false,
					DeviceName:   fi.DeviceName,
					DevicePath:   fi.DevicePath,
					DirPath:      fi.Path,
					FullPath:     fi.Path,
					DeviceSerial: fi.DeviceSerial,
					FileType:     string(storageutil.DetermineFileTypeFromPath(fi.Path)),
				},
				ModifiedAt: fi.ModTime,
			})
		}
		return ListRecentResult{Files: sortNewestFirst(allFiles, params.Limit)}, nil
	}

	// Fallback: walk devices via StorageService.
	devices, err := params.Storage.GetManagedDevices()
	if err != nil {
		return ListRecentResult{}, err
	}

	for _, device := range SelectDevices(devices, params.Serials) {
		deviceSerial := DeviceSerial(device)
		// Walk all files recursively. This used to call StatFilesInDir, a
		// single-level read, so "recent files" could never surface anything
		// outside the storage root (#1605). WalkedFile.RelPath is the
		// API-relative path the client uses directly — the same shape
		// the file listing produces.
		walkErr := storageutil.WalkFilesInDir(
			params.Ctx, device.FilesDir, device.Name, device.DataDir, deviceSerial,
			func(f storageutil.WalkedFile) error {
				info := f.Info
				if info.IsDir() {
					return nil // only return files, not directories
				}
				allFiles = append(allFiles, FileNodeWithTime{
					FileNode: FileNode{
						Name:         info.Name(),
						Size:         info.FileInfo.Size(),
						IsDir:        false,
						DeviceName:   info.DeviceName,
						DevicePath:   info.DevicePath,
						DirPath:      f.RelPath,
						FullPath:     info.FullPath,
						DeviceSerial: deviceSerial,
					},
					ModifiedAt: info.ModTime(),
				})
				return nil
			},
		)
		if walkErr != nil {
			continue
		}
	}

	return ListRecentResult{Files: sortNewestFirst(allFiles, params.Limit)}, nil
}

// sortNewestFirst orders files by modification time descending and truncates
// to limit. A limit of zero or less leaves the listing whole.
func sortNewestFirst(files []FileNodeWithTime, limit int) []FileNodeWithTime {
	sort.Slice(files, func(i, j int) bool {
		return files[i].ModifiedAt.After(files[j].ModifiedAt)
	})
	if limit > 0 && limit < len(files) {
		return files[:limit]
	}
	return files
}

// ListByTypeParams describes the whole-library listing of one file type.
type ListByTypeParams struct {
	// Ctx bounds the VFS listing and the device walk.
	Ctx context.Context
	// Registry serves the listing when the files namespace is registered.
	Registry vfs.Registry
	// Storage enumerates the managed devices for the fallback walk.
	Storage *storageutil.StorageService
	// Serials scopes the listing to those devices, empty for all of them.
	Serials []string
	// FileType is the type every returned file matches.
	FileType storageutil.FileType
}

// ListByTypeResult is every file of the requested type, newest first.
type ListByTypeResult struct {
	Files []FileNodeWithTime
}

// ListByType returns every file whose type matches, sorted newest-first.
func ListByType(params ListByTypeParams) (ListByTypeResult, error) {
	devices, err := params.Storage.GetManagedDevices()
	if err != nil {
		return ListByTypeResult{}, err
	}
	selectedDevices := SelectDevices(devices, params.Serials)

	// Use make() instead of var to ensure JSON serialization produces []
	// instead of null when there are no files (nil slice encodes as null).
	allFiles := make([]FileNodeWithTime, 0)

	// VFS path: recursive list + type filter.
	if fsys := FilesVFS(params.Registry); fsys != nil {
		infos, listErr := fsys.List(params.Ctx, "", &vfs.ListFilter{Recursive: true, SerialFilter: params.Serials})
		if listErr != nil {
			return ListByTypeResult{}, listErr
		}
		for _, fi := range infos {
			if fi.IsDir {
				continue
			}
			if storageutil.DetermineFileTypeFromPath(fi.Path) != params.FileType {
				continue
			}
			allFiles = append(allFiles, FileNodeWithTime{
				FileNode: FileNode{
					Name:         fi.Name,
					Size:         fi.Size,
					IsDir:        false,
					DeviceName:   fi.DeviceName,
					DevicePath:   fi.DevicePath,
					DirPath:      fi.Path,
					FullPath:     fi.Path,
					DeviceSerial: fi.DeviceSerial,
					FileType:     string(params.FileType),
				},
				ModifiedAt: fi.ModTime,
			})
		}
		return ListByTypeResult{Files: sortNewestFirst(allFiles, 0)}, nil
	}

	for _, device := range selectedDevices {
		deviceSerial := DeviceSerial(device)

		// Walk the whole subtree. This used to call StatFilesInDir, a
		// single-level read, so the endpoint only ever returned files sitting
		// at the storage root despite promising a recursive walk (#1605).
		walkErr := storageutil.WalkFilesInDir(
			params.Ctx, device.FilesDir, device.Name, device.DataDir, deviceSerial,
			func(f storageutil.WalkedFile) error {
				info := f.Info
				if info.IsDir() {
					return nil
				}
				if storageutil.DetermineFileTypeFromPath(info.FullPath) != params.FileType {
					return nil
				}
				allFiles = append(allFiles, FileNodeWithTime{
					FileNode: FileNode{
						Name:         info.Name(),
						Size:         info.FileInfo.Size(),
						IsDir:        false,
						DeviceName:   info.DeviceName,
						DevicePath:   info.DevicePath,
						DirPath:      f.RelPath,
						FullPath:     info.FullPath,
						DeviceSerial: deviceSerial,
						FileType:     string(params.FileType),
					},
					ModifiedAt: info.ModTime(),
				})
				return nil
			},
		)
		if walkErr != nil {
			continue
		}
	}

	return ListByTypeResult{Files: sortNewestFirst(allFiles, 0)}, nil
}

// SearchFilesParams describes a filename search across the library.
type SearchFilesParams struct {
	// Ctx bounds the VFS listing and the device walk.
	Ctx context.Context
	// Index answers the search outright when one has been built.
	Index *storageutil.FileIndex
	// Registry serves the fallback listing when there is no index.
	Registry vfs.Registry
	// Storage enumerates the managed devices for the disk walk.
	Storage *storageutil.StorageService
	// Query is the substring a file name must contain, empty for everything.
	Query string
	// Serials scopes the search to those devices, empty for all of them.
	Serials []string
}

// SearchFilesResult is the set of matching files.
type SearchFilesResult struct {
	Files []FileNode
}

// SearchFiles finds files whose name contains the query.
func SearchFiles(params SearchFilesParams) (SearchFilesResult, error) {
	if params.Index == nil {
		// VFS fallback: recursive list then name-match (avoids disk-walk when VFS is registered).
		if params.Registry != nil {
			return searchFilesVFS(params)
		}
		return searchFilesDiskWalk(params)
	}

	serialSet := make(map[string]bool, len(params.Serials))
	for _, s := range params.Serials {
		serialSet[s] = true
	}

	// The index records only the device's files directory and serial, so the
	// name and path come from the managed device that owns that directory.
	devicesByFilesDir := make(map[string]storageutil.ManagedDevice)
	if params.Storage != nil {
		devices, err := params.Storage.GetManagedDevices()
		if err != nil {
			return SearchFilesResult{}, err
		}
		for _, device := range devices {
			devicesByFilesDir[device.FilesDir] = device
		}
	}

	matches := params.Index.Search(params.Query, serialSet)
	allFiles := make([]FileNode, 0, len(matches))
	for _, f := range matches {
		device := devicesByFilesDir[f.FilesDir]
		// DirPath must be the full relative path (e.g. "docs/notes.txt"), not
		// just the parent dir. The Flutter FileNode.apiPath getter uses
		// DirPath as the full API path, consistent with how the directory
		// listing populates it (filepath.Join(rootDir, file.Name())).
		allFiles = append(allFiles, FileNode{
			Name:         f.Name,
			DirPath:      f.RelPath,
			IsDir:        false,
			DeviceName:   device.Name,
			DevicePath:   device.DataDir,
			DeviceSerial: f.DeviceSerial,
			FileType:     string(storageutil.DetermineFileTypeFromPath(f.RelPath)),
		})
	}
	return SearchFilesResult{Files: allFiles}, nil
}

// searchFilesVFS uses VFS.List(Recursive: true) as the fallback when no file index is available.
func searchFilesVFS(params SearchFilesParams) (SearchFilesResult, error) {
	fsys, ok := params.Registry.Get(filesNamespace)
	if !ok {
		return SearchFilesResult{}, ErrNoFilesNamespace
	}
	all, err := fsys.List(params.Ctx, "", &vfs.ListFilter{Recursive: true, SerialFilter: params.Serials})
	if err != nil {
		return SearchFilesResult{}, err
	}
	result := make([]FileNode, 0, len(all))
	for _, fi := range all {
		if fi.IsDir {
			continue
		}
		if params.Query != "" && !strings.Contains(strings.ToLower(fi.Name), strings.ToLower(params.Query)) {
			continue
		}
		result = append(result, FileNode{
			Name:         fi.Name,
			DirPath:      fi.Path,
			FileType:     string(storageutil.DetermineFileTypeFromPath(fi.Path)),
			IsDir:        false,
			DeviceName:   fi.DeviceName,
			DevicePath:   fi.DevicePath,
			DeviceSerial: fi.DeviceSerial,
		})
	}
	return SearchFilesResult{Files: result}, nil
}

// searchFilesDiskWalk is the original BFS implementation used as fallback when the
// in-memory index is unavailable.
func searchFilesDiskWalk(params SearchFilesParams) (SearchFilesResult, error) {
	devices, err := params.Storage.GetManagedDevices()
	if err != nil {
		return SearchFilesResult{}, err
	}
	selectedDevices := SelectDevices(devices, params.Serials)
	if len(params.Serials) > 0 && len(selectedDevices) == 0 {
		return SearchFilesResult{Files: []FileNode{}}, nil
	}
	allFiles := make([]FileNode, 0)
	dirsToScan := []string{""}
	seenDirs := map[string]bool{"": true}

	for len(dirsToScan) > 0 {
		currentDir := dirsToScan[0]
		dirsToScan = dirsToScan[1:]

		entries, err := listFilesOnDevices(currentDir, selectedDevices)
		if err != nil {
			continue
		}

		for _, entry := range entries {
			if entry.IsDir {
				if !seenDirs[entry.DirPath] {
					seenDirs[entry.DirPath] = true
					dirsToScan = append(dirsToScan, entry.DirPath)
				}
				continue
			}

			if params.Query == "" || strings.Contains(strings.ToLower(entry.Name), strings.ToLower(params.Query)) {
				allFiles = append(allFiles, entry)
			}
		}
	}

	return SearchFilesResult{Files: allFiles}, nil
}

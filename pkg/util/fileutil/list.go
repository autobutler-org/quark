package fileutil

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
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
	// Access decides what the listing may show (#1903). The zero value shows
	// nothing.
	Access accessutil.Access
	// RootDir is the directory to list, empty for the storage root.
	RootDir string
	// Serials scopes the listing to those devices, empty for all of them.
	Serials []string
}

// ListFilesResult is one directory level.
type ListFilesResult struct {
	Files []FileNode
}

// ListFiles returns the direct children of RootDir that the caller may see:
// what they can read, and the folders on the way to something shared with
// them deeper down. A folder they can see none of is reported as not found,
// the same as one that does not exist.
func ListFiles(params ListFilesParams) (ListFilesResult, error) {
	if climbsOut(params.RootDir) {
		return ListFilesResult{}, invalidPath(params.RootDir)
	}
	if accessutil.Canonical(params.RootDir) != "" && !params.Access.VisibleOnAny(params.Serials, params.RootDir) {
		return ListFilesResult{}, notFoundf("folder not found: %s", params.RootDir)
	}

	// Use VFS when available — one namespace per device, fanned out over the
	// ones Serials selects.
	if params.Registry != nil {
		files, err := listFilesVFS(params.Ctx, params.Registry, params.RootDir, params.Serials)
		if err != nil {
			return ListFilesResult{}, err
		}
		return ListFilesResult{Files: visibleFiles(params.Access, files)}, nil
	}

	devices, err := params.Storage.GetManagedRoots()
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
	return ListFilesResult{Files: visibleFiles(params.Access, files)}, nil
}

// visibleFiles keeps the listed files the caller may see. DirPath is the
// files-relative path on both listing branches; FullPath is absolute on the
// device walk.
func visibleFiles(access accessutil.Access, files []FileNode) []FileNode {
	return accessutil.VisibleChildren(accessutil.VisibleChildrenParams[FileNode]{
		Access:   access,
		Children: files,
		Locate:   func(f FileNode) (string, string) { return f.DeviceSerial, f.DirPath },
	}).Children
}

// readable reports whether the caller can read a search match. Unlike a
// folder listing, a flat result across the tree has no breadcrumbs to keep
// (#1907).
func readable(access accessutil.Access, serial, relPath string) bool {
	return access.Check(serial, relPath, accessutil.Read).Readable
}

// listFilesVFS lists files via the VFS registry, optionally scoped to specific device serials.
func listFilesVFS(ctx context.Context, registry vfs.Registry, rootDir string, serials []string) ([]FileNode, error) {
	if _, ok := registry.Get(filesNamespace); !ok {
		return nil, ErrNoFilesNamespace
	}
	infos, err := vfs.ListDevices(vfs.ListDevicesParams{
		Ctx: ctx, Registry: registry, Path: rootDir,
		Filter: &vfs.ListFilter{Recursive: false, SerialFilter: serials},
	})
	if err != nil {
		if err == vfs.ErrNotFound {
			return nil, notFoundf("folder not found: %s", rootDir)
		}
		return nil, err
	}
	result := make([]FileNode, len(infos))
	for i, fi := range infos {
		result[i] = vfsFileNode(fi)
	}
	return result, nil
}

// vfsFileNode is a VFS entry as every listing reports it.
func vfsFileNode(fi vfs.FileInfo) FileNode {
	return FileNode{
		Name:         fi.Name,
		Size:         fi.Size,
		IsDir:        fi.IsDir,
		DeviceName:   fi.DeviceName,
		DevicePath:   fi.DevicePath,
		DirPath:      fi.Path,
		FullPath:     fi.Path,
		DeviceSerial: fi.DeviceSerial,
		FileType:     string(storageutil.DetermineFileTypeFromPath(fi.Path)),
		ModifiedAt:   fi.ModTime,
	}
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
			ModifiedAt:   file.ModTime(),
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
	// Access drops the files the caller cannot read, before the limit applies.
	Access accessutil.Access
	// Limit caps how many files come back.
	Limit int
}

// ListRecentResult is the newest-first page of files.
type ListRecentResult struct {
	Files []FileNode
}

// ListRecent returns the most recently modified files, newest first.
func ListRecent(params ListRecentParams) (ListRecentResult, error) {
	var allFiles []FileNode

	// VFS path: use recursive list when registry is available.
	if FilesVFS(params.Registry) != nil {
		infos, err := vfs.ListDevices(vfs.ListDevicesParams{
			Ctx: params.Ctx, Registry: params.Registry,
			Filter: &vfs.ListFilter{Recursive: true, SerialFilter: params.Serials},
		})
		if err != nil {
			return ListRecentResult{}, err
		}
		for _, fi := range infos {
			if fi.IsDir {
				continue
			}
			allFiles = append(allFiles, vfsFileNode(fi))
		}
		return ListRecentResult{Files: readableNewestFirst(params.Access, allFiles, params.Limit)}, nil
	}

	// Fallback: walk devices via StorageService.
	devices, err := params.Storage.GetManagedRoots()
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
				allFiles = append(allFiles, FileNode{
					Name:         info.Name(),
					Size:         info.FileInfo.Size(),
					IsDir:        false,
					DeviceName:   info.DeviceName,
					DevicePath:   info.DevicePath,
					DirPath:      f.RelPath,
					FullPath:     info.FullPath,
					DeviceSerial: deviceSerial,
					ModifiedAt:   info.ModTime(),
				})
				return nil
			},
		)
		if walkErr != nil {
			continue
		}
	}

	return ListRecentResult{Files: readableNewestFirst(params.Access, allFiles, params.Limit)}, nil
}

// readableNewestFirst drops the files the caller cannot read, orders the rest
// by modification time descending, and truncates to limit, in that order so a
// page of recent files stays full (#1907). A limit of zero or less leaves the
// listing whole.
func readableNewestFirst(access accessutil.Access, files []FileNode, limit int) []FileNode {
	files = slices.DeleteFunc(files, func(f FileNode) bool {
		return !access.Check(f.DeviceSerial, f.DirPath, accessutil.Read).Readable
	})
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
	// Access drops the files the caller cannot read.
	Access accessutil.Access
	// FileType is the type every returned file matches.
	FileType storageutil.FileType
	// Cache keeps the walk between requests. Nil walks every time.
	Cache *ByTypeCache
}

// ListByTypeResult is every file of the requested type, newest first.
type ListByTypeResult struct {
	Files []FileNode
}

// ListByType returns every file whose type matches, sorted newest-first. With a
// Cache, the walk is shared between requests until the file tree changes.
func ListByType(params ListByTypeParams) (ListByTypeResult, error) {
	devices, err := params.Storage.GetManagedRoots()
	if err != nil {
		return ListByTypeResult{}, err
	}
	selectedDevices := SelectDevices(devices, params.Serials)

	key := byTypeKey(params.FileType, params.Serials, selectedDevices)
	files, gen, ok := params.Cache.get(key)
	if !ok {
		files, err = walkByType(params, selectedDevices)
		if err != nil {
			return ListByTypeResult{}, err
		}
		params.Cache.put(key, gen, files)
	}
	// readableNewestFirst filters and sorts in place, so it gets a copy of
	// what the cache holds.
	files = append(make([]FileNode, 0, len(files)), files...)
	return ListByTypeResult{Files: readableNewestFirst(params.Access, files, 0)}, nil
}

// walkByType lists every file of the requested type on selectedDevices,
// unsorted and unfiltered by access.
func walkByType(params ListByTypeParams, selectedDevices []storageutil.ManagedDevice) ([]FileNode, error) {
	// Use make() instead of var to ensure JSON serialization produces []
	// instead of null when there are no files (nil slice encodes as null).
	allFiles := make([]FileNode, 0)

	// VFS path: recursive list + type filter.
	if FilesVFS(params.Registry) != nil {
		infos, listErr := vfs.ListDevices(vfs.ListDevicesParams{
			Ctx: params.Ctx, Registry: params.Registry,
			Filter: &vfs.ListFilter{Recursive: true, SerialFilter: params.Serials},
		})
		if listErr != nil {
			return nil, listErr
		}
		for _, fi := range infos {
			if fi.IsDir {
				continue
			}
			if storageutil.DetermineFileTypeFromPath(fi.Path) != params.FileType {
				continue
			}
			allFiles = append(allFiles, vfsFileNode(fi))
		}
		return allFiles, nil
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
				allFiles = append(allFiles, FileNode{
					Name:         info.Name(),
					Size:         info.FileInfo.Size(),
					IsDir:        false,
					DeviceName:   info.DeviceName,
					DevicePath:   info.DevicePath,
					DirPath:      f.RelPath,
					FullPath:     info.FullPath,
					DeviceSerial: deviceSerial,
					FileType:     string(params.FileType),
					ModifiedAt:   info.ModTime(),
				})
				return nil
			},
		)
		if walkErr != nil {
			continue
		}
	}

	return allFiles, nil
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
	// Query is the substring a file name must contain. An empty one, which
	// would match every file on the appliance, finds nothing.
	Query string
	// Serials scopes the search to those devices, empty for all of them.
	Serials []string
	// Access drops the matches the caller cannot read.
	Access accessutil.Access
}

// SearchFilesResult is the set of matching files.
type SearchFilesResult struct {
	Files []FileNode
}

// MaxSearchResults caps a name search, so a query matching most of the
// appliance costs a bounded amount of work and response (#2758).
const MaxSearchResults = 500

// statFile reads a match's size and modification time; a variable so a test can prove stat never
// runs on an unreadable match.
var statFile = os.Stat

// SearchFiles finds up to MaxSearchResults files whose name contains the
// query, keeping only the ones the caller can read (#1907): from the index
// when one has been built, from a VFS listing or a disk walk otherwise. The
// index stays appliance-wide; a match is checked against the caller's access before
// anything about it is read from disk, and the search stops at the cap
// (#2758).
func SearchFiles(params SearchFilesParams) (SearchFilesResult, error) {
	params.Query = strings.TrimSpace(params.Query)
	if params.Query == "" {
		return SearchFilesResult{Files: []FileNode{}}, nil
	}
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
		devices, err := params.Storage.GetManagedRoots()
		if err != nil {
			return SearchFilesResult{}, err
		}
		for _, device := range devices {
			devicesByFilesDir[device.FilesDir] = device
		}
	}

	// The grants alone decide the first cut, in memory and under the
	// index's lock, so a match the caller cannot read costs no disk access.
	var matches []storageutil.IndexedFile
	params.Index.SearchEach(params.Query, serialSet, func(f storageutil.IndexedFile) bool {
		if params.Access.Level(f.DeviceSerial, f.RelPath) < accessutil.Read {
			return true
		}
		matches = append(matches, f)
		return len(matches) < MaxSearchResults
	})
	allFiles := make([]FileNode, 0, len(matches))
	for _, f := range matches {
		// The full check also refuses a path that symlinks out of what the
		// grants cover; it runs before the stat, never after.
		if !readable(params.Access, f.DeviceSerial, f.RelPath) {
			continue
		}
		// The index holds no size or modification time, which would go stale on
		// every write, so stat at search time. A file deleted since it was indexed is skipped.
		info, err := statFile(filepath.Join(f.FilesDir, f.RelPath))
		if err != nil {
			continue
		}
		device := devicesByFilesDir[f.FilesDir]
		// DirPath must be the full relative path (e.g. "docs/notes.txt"), not
		// just the parent dir. The Flutter FileNode.apiPath getter uses
		// DirPath as the full API path, consistent with how the directory
		// listing populates it (filepath.Join(rootDir, file.Name())).
		allFiles = append(allFiles, FileNode{
			Name:         f.Name,
			Size:         info.Size(),
			DirPath:      f.RelPath,
			FullPath:     f.RelPath,
			IsDir:        false,
			DeviceName:   device.Name,
			DevicePath:   device.DataDir,
			DeviceSerial: f.DeviceSerial,
			FileType:     string(storageutil.DetermineFileTypeFromPath(f.RelPath)),
			ModifiedAt:   info.ModTime(),
		})
	}
	return SearchFilesResult{Files: allFiles}, nil
}

// searchFilesVFS uses VFS.List(Recursive: true) as the fallback when no file index is available.
func searchFilesVFS(params SearchFilesParams) (SearchFilesResult, error) {
	if _, ok := params.Registry.Get(filesNamespace); !ok {
		return SearchFilesResult{}, ErrNoFilesNamespace
	}
	all, err := vfs.ListDevices(vfs.ListDevicesParams{
		Ctx: params.Ctx, Registry: params.Registry,
		Filter: &vfs.ListFilter{Recursive: true, SerialFilter: params.Serials},
	})
	if err != nil {
		return SearchFilesResult{}, err
	}
	result := make([]FileNode, 0, len(all))
	for _, fi := range all {
		if fi.IsDir {
			continue
		}
		if !strings.Contains(strings.ToLower(fi.Name), strings.ToLower(params.Query)) ||
			!readable(params.Access, fi.DeviceSerial, fi.Path) {
			continue
		}
		result = append(result, vfsFileNode(fi))
		if len(result) == MaxSearchResults {
			break
		}
	}
	return SearchFilesResult{Files: result}, nil
}

// searchFilesDiskWalk is the original BFS implementation used as fallback when the
// in-memory index is unavailable.
func searchFilesDiskWalk(params SearchFilesParams) (SearchFilesResult, error) {
	devices, err := params.Storage.GetManagedRoots()
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

	for len(dirsToScan) > 0 && len(allFiles) < MaxSearchResults {
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

			if len(allFiles) < MaxSearchResults &&
				strings.Contains(strings.ToLower(entry.Name), strings.ToLower(params.Query)) &&
				readable(params.Access, entry.DeviceSerial, entry.DirPath) {
				allFiles = append(allFiles, entry)
			}
		}
	}

	return SearchFilesResult{Files: allFiles}, nil
}

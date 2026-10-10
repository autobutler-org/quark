package fileutil

import (
	"context"
	"errors"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/indexutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const defaultRecentLimit = 20
const maxRecentLimit = 200

// ListFilesParams lists one directory level, merged across the devices the
// serials select.
type ListFilesParams struct {
	// Ctx bounds the listing.
	Ctx context.Context
	// Registry holds a files namespace per device; the listing fans out over
	// the ones Serials selects.
	Registry vfs.Registry
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

	files, err := listFilesVFS(params.Ctx, params.Registry, params.RootDir, params.Serials)
	if err != nil {
		return ListFilesResult{}, err
	}
	return ListFilesResult{Files: visibleFiles(params.Access, files)}, nil
}

// visibleFiles keeps the listed files the caller may see, located by their
// files-relative DirPath.
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
	if _, err := FilesVFS(registry, ""); err != nil {
		return nil, err
	}
	infos, err := vfs.ListDevices(vfs.ListDevicesParams{
		Ctx: ctx, Registry: registry, Path: rootDir,
		Filter: &vfs.ListFilter{Recursive: false, SerialFilter: serials},
	})
	if err != nil {
		if errors.Is(err, vfs.ErrNotFound) {
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
	// Ctx bounds the listing.
	Ctx context.Context
	// Registry holds a files namespace per device.
	Registry vfs.Registry
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
	files, err := listAllFiles(params.Ctx, params.Registry, params.Serials, func(vfs.FileInfo) bool { return true })
	if err != nil {
		return ListRecentResult{}, err
	}
	return ListRecentResult{Files: readableNewestFirst(params.Access, files, params.Limit)}, nil
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
	// Ctx bounds the listing.
	Ctx context.Context
	// Registry holds a files namespace per device.
	Registry vfs.Registry
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
	key := byTypeKey(params.FileType, params.Serials, params.Registry)
	files, gen, ok := params.Cache.get(key)
	if !ok {
		var err error
		files, err = listAllFiles(params.Ctx, params.Registry, params.Serials, func(fi vfs.FileInfo) bool {
			return storageutil.DetermineFileTypeFromPath(fi.Path) == params.FileType
		})
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

// listAllFiles walks every device Serials selects and returns the files keep
// accepts, unsorted and unfiltered by access. Folders are left out.
func listAllFiles(ctx context.Context, registry vfs.Registry, serials []string, keep func(vfs.FileInfo) bool) ([]FileNode, error) {
	if _, err := FilesVFS(registry, ""); err != nil {
		return nil, err
	}
	infos, err := vfs.ListDevices(vfs.ListDevicesParams{
		Ctx: ctx, Registry: registry,
		Filter: &vfs.ListFilter{Recursive: true, SerialFilter: serials},
	})
	if err != nil {
		return nil, err
	}
	// make() rather than var, so an empty listing encodes as [] and not null.
	files := make([]FileNode, 0)
	for _, fi := range infos {
		if !fi.IsDir && keep(fi) {
			files = append(files, vfsFileNode(fi))
		}
	}
	return files, nil
}

// SearchFilesParams describes a filename search across the library.
type SearchFilesParams struct {
	// Ctx bounds the listing and the stats.
	Ctx context.Context
	// Index answers the search outright when one has been built.
	Index *indexutil.FileIndex
	// Registry stats each index hit on its device's namespace, and serves the
	// listing the search falls back to when there is no index.
	Registry vfs.Registry
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
var statFile = func(ctx context.Context, fsys vfs.VFS, p string) (vfs.FileInfo, error) {
	return fsys.Stat(ctx, p)
}

// SearchFiles finds up to MaxSearchResults files whose name contains the
// query, keeping only the ones the caller can read (#1907): from the index
// when one has been built, from a VFS listing otherwise. The
// index stays appliance-wide; a match is checked against the caller's access before
// anything about it is read from disk, and the search stops at the cap
// (#2758).
func SearchFiles(params SearchFilesParams) (SearchFilesResult, error) {
	params.Query = strings.TrimSpace(params.Query)
	if params.Query == "" {
		return SearchFilesResult{Files: []FileNode{}}, nil
	}
	if params.Index == nil {
		return searchFilesVFS(params)
	}

	serialSet := make(map[string]bool, len(params.Serials))
	for _, s := range params.Serials {
		serialSet[s] = true
	}

	// The grants alone decide the first cut, in memory and under the
	// index's lock, so a match the caller cannot read costs no disk access.
	var matches []indexutil.IndexedFile
	params.Index.SearchEach(params.Query, serialSet, func(f indexutil.IndexedFile) bool {
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
		// every write, so stat at search time, on the namespace of the device
		// the hit is on. A file deleted since it was indexed, or on a device
		// since detached, is skipped.
		fsys, err := FilesVFS(params.Registry, f.DeviceSerial)
		if err != nil {
			continue
		}
		info, err := statFile(params.Ctx, fsys, f.RelPath)
		if err != nil {
			continue
		}
		// DirPath must be the full relative path (e.g. "docs/notes.txt"), not
		// just the parent dir. The Flutter FileNode.apiPath getter uses
		// DirPath as the full API path, consistent with how the directory
		// listing populates it (filepath.Join(rootDir, file.Name())).
		allFiles = append(allFiles, FileNode{
			Name:         f.Name,
			Size:         info.Size,
			DirPath:      f.RelPath,
			FullPath:     f.RelPath,
			IsDir:        false,
			DeviceName:   info.DeviceName,
			DevicePath:   info.DevicePath,
			DeviceSerial: f.DeviceSerial,
			FileType:     string(storageutil.DetermineFileTypeFromPath(f.RelPath)),
			ModifiedAt:   info.ModTime,
		})
	}
	return SearchFilesResult{Files: allFiles}, nil
}

// searchFilesVFS uses VFS.List(Recursive: true) as the fallback when no file index is available.
func searchFilesVFS(params SearchFilesParams) (SearchFilesResult, error) {
	if _, err := FilesVFS(params.Registry, ""); err != nil {
		return SearchFilesResult{}, err
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

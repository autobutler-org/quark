package storageutil

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// TrashDir is the directory inside each device's FilesDir where trashed files live.
const TrashDir = ".trash"

// TrashRetentionDays is how long items stay in the trash before auto-expiry.
const TrashRetentionDays = 30

// trashMetaSuffix ends the name of the JSON sidecar written beside each
// trashed item.
const trashMetaSuffix = ".meta.json"

// trashStampLayout is the UTC timestamp every trash name starts with.
const trashStampLayout = "20060102T150405Z"

// maxTrashNameBytes keeps a trash name and its sidecar under the 255-byte file
// name limit every filesystem Quark runs on shares.
const maxTrashNameBytes = 255 - len(trashMetaSuffix)

var (
	// ErrDeviceNotFound reports a serial no managed device answers to.
	ErrDeviceNotFound = errors.New("device not found")
	// ErrInvalidTrashName reports a trash name that could point outside the
	// trash: empty, "." or "..", or carrying a path separator.
	ErrInvalidTrashName = errors.New("invalid trash name")
	// ErrInvalidTrashPath reports a path inside a trashed item that could
	// point outside it: absolute, climbing out with "..", or through a
	// symlink.
	ErrInvalidTrashPath = errors.New("invalid path inside trash item")
	// ErrTrashItemNotFound reports a well-formed trash name, or a path inside
	// a trashed item, with nothing in the trash under it.
	ErrTrashItemNotFound = errors.New("trash item not found")
	// ErrNotATrashFolder reports a contents listing of something that is not
	// a folder.
	ErrNotATrashFolder = errors.New("not a folder")
	// ErrRestoreConflict reports a trash item that cannot go back where it
	// came from: something else now occupies that path, or the item's
	// original location is unknown.
	ErrRestoreConflict = errors.New("cannot restore")
)

// TrashEntry is the metadata stored alongside each trashed item.
type TrashEntry struct {
	OriginalPath string    `json:"originalPath"` // relative to FilesDir
	TrashedAt    time.Time `json:"trashedAt"`
}

// trashMetaFile returns the path of the JSON metadata sidecar for a trashed item.
func trashMetaFile(trashItemPath string) string {
	return trashItemPath + trashMetaSuffix
}

// IsTrashPath reports whether a path relative to a FilesDir is the trash or
// something inside it.
func IsTrashPath(relPath string) bool {
	clean := filepath.ToSlash(filepath.Clean(relPath))
	return clean == TrashDir || strings.HasPrefix(clean, TrashDir+"/")
}

// trashFilesDir resolves the FilesDir whose trash a request addresses. The
// empty serial is the internal device, falling back to the default files
// directory the same way every other StorageService operation does; any other
// serial has to match a managed device, so a request for an unplugged drive
// never lands on the internal trash.
func (s *StorageService) trashFilesDir(serial string) (string, error) {
	device, err := s.FindManagedDeviceBySerial(serial)
	if err != nil {
		return "", err // coverage: ignore - requires device detection failure
	}
	if device != nil {
		return device.FilesDir, nil
	}
	if serial != "" {
		return "", fmt.Errorf("%w: %s", ErrDeviceNotFound, serial)
	}
	return GetFilesDir()
}

// publishTrashChanged tells open Trash pages to refresh. A nil bus is a caller
// that does not care.
func publishTrashChanged(bus *eventbus.Bus, serial string) {
	if bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventTrashChanged, DeviceSerial: serial})
	}
}

// newTrashName builds a trash name that cannot collide with another item
// trashed in the same second: a timestamp, a random suffix, and the original
// base name, which is truncated if the three would overflow a file name.
func newTrashName(base string, now time.Time) (string, error) {
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", fmt.Errorf("failed to generate trash name: %w", err) // coverage: ignore - crypto/rand does not fail on supported platforms
	}
	prefix := now.UTC().Format(trashStampLayout) + "_" + hex.EncodeToString(random[:]) + "_"
	if room := maxTrashNameBytes - len(prefix); len(base) > room {
		base = strings.ToValidUTF8(base[:room], "")
	}
	return prefix + base, nil
}

// TrashFilesParams mirrors DeleteFilesParams but moves to .trash instead of removing.
type TrashFilesParams struct {
	RootDir      string
	FilePaths    []string
	DeviceSerial string
}

// TrashFilesResult is returned on success.
type TrashFilesResult struct {
	RootDir string
}

// TrashFiles moves files/directories into the .trash folder under the device's FilesDir.
func (s *StorageService) TrashFiles(params TrashFilesParams) (*TrashFilesResult, error) {
	filesDir, err := s.trashFilesDir(params.DeviceSerial)
	if err != nil {
		return nil, err
	}
	return TrashFilesImpl(params, filesDir)
}

// TrashFilesImpl is the testable core of TrashFiles. A path that no longer
// exists is skipped, so a repeated delete succeeds the way it did when deletes
// were permanent.
func TrashFilesImpl(params TrashFilesParams, filesDir string) (*TrashFilesResult, error) {
	trashRoot := filepath.Join(filesDir, TrashDir)
	if err := os.MkdirAll(trashRoot, 0o700); err != nil {
		return nil, fmt.Errorf("failed to create trash directory: %w", err)
	}

	for _, filePath := range params.FilePaths {
		fullPath, err := safeJoin(filesDir, params.RootDir, filePath)
		if err != nil {
			return nil, fmt.Errorf("invalid file path: %w", err)
		}
		relOriginal, err := filepath.Rel(filepath.Clean(filesDir), fullPath)
		if err != nil || relOriginal == "." || IsTrashPath(relOriginal) {
			return nil, fmt.Errorf("invalid file path: %s", filePath)
		}
		if _, err := os.Lstat(fullPath); os.IsNotExist(err) {
			continue
		}

		now := time.Now().UTC()
		trashName, err := newTrashName(filepath.Base(fullPath), now)
		if err != nil {
			return nil, err // coverage: ignore - crypto/rand does not fail on supported platforms
		}
		trashDest := filepath.Join(trashRoot, trashName)

		if err := os.Rename(fullPath, trashDest); err != nil {
			return nil, fmt.Errorf("failed to move %s to trash: %w", filePath, err)
		}

		// The sidecar is the only record of where the item came from. Without
		// it the item could never be restored, so put the item back rather
		// than leave it stranded in the trash.
		metaBytes, _ := json.Marshal(TrashEntry{
			OriginalPath: filepath.ToSlash(relOriginal),
			TrashedAt:    now,
		})
		if err := os.WriteFile(trashMetaFile(trashDest), metaBytes, 0o600); err != nil {
			_ = os.Rename(trashDest, fullPath)
			return nil, fmt.Errorf("failed to record trash metadata for %s: %w", filePath, err)
		}
	}

	return &TrashFilesResult{RootDir: params.RootDir}, nil
}

// TrashItem describes one item in the trash.
type TrashItem struct {
	// TrashName addresses the item in restore and delete requests.
	TrashName string `json:"trashName"`
	// Name is the item's base name as it was before it was trashed.
	Name string `json:"name"`
	// OriginalPath is where a restore puts the item back, relative to the
	// device's files directory. Empty when its metadata is missing.
	OriginalPath string    `json:"originalPath"`
	IsDir        bool      `json:"isDir"`
	Size         int64     `json:"size"`
	TrashedAt    time.Time `json:"trashedAt"`
	// ExpiresAt is when the hourly purge deletes the item for good.
	ExpiresAt time.Time `json:"expiresAt"`
}

// ListTrashParams lists what is in the trash for a given device.
type ListTrashParams struct {
	DeviceSerial string
}

// ListTrashResult is the device's trash, most recently trashed first.
type ListTrashResult struct {
	Items []TrashItem
}

// ListTrash returns all items currently in the device's trash.
func (s *StorageService) ListTrash(params ListTrashParams) (ListTrashResult, error) {
	filesDir, err := s.trashFilesDir(params.DeviceSerial)
	if err != nil {
		return ListTrashResult{}, err
	}
	items, err := ListTrashImpl(filesDir)
	return ListTrashResult{Items: items}, err
}

// ListTrashImpl is the testable core of ListTrash. It never returns a nil
// slice, so an empty trash serializes as [].
func ListTrashImpl(filesDir string) ([]TrashItem, error) {
	trashRoot := filepath.Join(filesDir, TrashDir)
	entries, err := os.ReadDir(trashRoot)
	items := make([]TrashItem, 0, len(entries))
	if os.IsNotExist(err) {
		return items, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read trash directory: %w", err)
	}

	names := make(map[string]bool, len(entries))
	for _, entry := range entries {
		names[entry.Name()] = true
	}

	for _, entry := range entries {
		name := entry.Name()
		if isTrashSidecar(name, names) {
			continue
		}
		fullPath := filepath.Join(trashRoot, name)
		info, err := entry.Info()
		if err != nil {
			continue // coverage: ignore - requires a concurrent purge
		}

		item := TrashItem{TrashName: name, Name: name, IsDir: entry.IsDir(), Size: info.Size()}
		if item.IsDir {
			// The trash only holds what users deleted, so walking a trashed
			// folder is bounded by that; a folder that cannot be walked reports 0.
			item.Size, _ = GetFolderSize(fullPath)
		}
		meta, metaErr := readTrashEntry(fullPath)
		if metaErr == nil {
			item.OriginalPath = meta.OriginalPath
			item.Name = filepath.Base(meta.OriginalPath)
		}
		item.TrashedAt = trashedAt(name, meta, info.ModTime())
		item.ExpiresAt = item.TrashedAt.AddDate(0, 0, TrashRetentionDays)
		items = append(items, item)
	}

	slices.SortFunc(items, func(a, b TrashItem) int {
		if c := b.TrashedAt.Compare(a.TrashedAt); c != 0 {
			return c
		}
		return strings.Compare(a.TrashName, b.TrashName)
	})
	return items, nil
}

// isTrashSidecar reports whether a trash entry is the metadata of another
// entry. Checking the suffix alone would hide a trashed file the user named
// "report.json" or even "x.meta.json"; a sidecar also has its item beside it.
func isTrashSidecar(name string, names map[string]bool) bool {
	item, ok := strings.CutSuffix(name, trashMetaSuffix)
	return ok && names[item]
}

// readTrashEntry reads the sidecar of the trashed item at itemPath.
func readTrashEntry(itemPath string) (TrashEntry, error) {
	var meta TrashEntry
	metaBytes, err := os.ReadFile(trashMetaFile(itemPath))
	if err != nil {
		return meta, err
	}
	if err := json.Unmarshal(metaBytes, &meta); err != nil {
		return meta, fmt.Errorf("corrupt trash metadata: %w", err)
	}
	return meta, nil
}

// trashedAt reports when an item was trashed: from its sidecar, else from the
// timestamp its trash name starts with, else from its modification time. A
// rename keeps a file's own mtime, so mtime is the last resort — it can make
// a long-unedited file look long-trashed.
func trashedAt(trashName string, meta TrashEntry, modTime time.Time) time.Time {
	if !meta.TrashedAt.IsZero() {
		return meta.TrashedAt
	}
	if len(trashName) >= len(trashStampLayout) {
		if t, err := time.Parse(trashStampLayout, trashName[:len(trashStampLayout)]); err == nil {
			return t
		}
	}
	return modTime.UTC()
}

// resolveTrashItem validates a trash name from a request and returns the path
// of the item it names. The name crosses a trust boundary, so it must be a
// single path element that exists in the trash and is not a sidecar.
func resolveTrashItem(trashRoot, name string) (string, error) {
	if name == "" || name == "." || name == ".." ||
		strings.ContainsRune(name, '/') || strings.ContainsRune(name, filepath.Separator) {
		return "", fmt.Errorf("%w: %q", ErrInvalidTrashName, name)
	}
	itemPath := filepath.Join(trashRoot, name)
	if _, err := os.Lstat(itemPath); err != nil {
		return "", fmt.Errorf("%w: %s", ErrTrashItemNotFound, name)
	}
	if item, ok := strings.CutSuffix(name, trashMetaSuffix); ok {
		if _, err := os.Lstat(filepath.Join(trashRoot, item)); err == nil {
			return "", fmt.Errorf("%w: %s", ErrTrashItemNotFound, name)
		}
	}
	return itemPath, nil
}

// TrashRef addresses a trashed item, or something inside a trashed folder.
type TrashRef struct {
	TrashName string `json:"trashName"`
	// Path is relative to the trashed item, slash-separated; empty is the
	// item itself.
	Path string `json:"path"`
}

// resolvedTrashRef is a TrashRef checked against the disk.
type resolvedTrashRef struct {
	// itemPath is the trashed item on disk.
	itemPath string
	// target is what the reference names: itemPath, or a path inside it.
	target string
	// rel is the reference's path, cleaned and slash-separated; empty for
	// the item itself.
	rel string
}

// resolveTrashRef validates a reference from a request. Its path crosses a
// trust boundary like its name does, so it must stay inside the trashed item:
// no absolute path, no "..", and no symlink on the way that leads out.
func resolveTrashRef(trashRoot string, ref TrashRef) (resolvedTrashRef, error) {
	itemPath, err := resolveTrashItem(trashRoot, ref.TrashName)
	if err != nil {
		return resolvedTrashRef{}, err
	}
	resolved := resolvedTrashRef{itemPath: itemPath, target: itemPath}
	if ref.Path == "" {
		return resolved, nil
	}
	rel := filepath.Clean(filepath.FromSlash(ref.Path))
	if !filepath.IsLocal(rel) {
		return resolvedTrashRef{}, fmt.Errorf("%w: %q", ErrInvalidTrashPath, ref.Path)
	}
	if rel == "." {
		return resolved, nil
	}
	// Only a real folder has anything inside it. Lstat, so a trashed symlink
	// to a folder elsewhere is not followed.
	if info, err := os.Lstat(itemPath); err != nil || !info.IsDir() {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s/%s", ErrTrashItemNotFound, ref.TrashName, ref.Path)
	}
	target := filepath.Join(itemPath, rel)
	realItem, err := filepath.EvalSymlinks(itemPath)
	if err != nil {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s", ErrTrashItemNotFound, ref.TrashName) // coverage: ignore - requires a concurrent purge
	}
	realParent, err := filepath.EvalSymlinks(filepath.Dir(target))
	if err != nil {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s/%s", ErrTrashItemNotFound, ref.TrashName, ref.Path)
	}
	if !isWithin(realItem, realParent) {
		return resolvedTrashRef{}, fmt.Errorf("%w: %q", ErrInvalidTrashPath, ref.Path)
	}
	if _, err := os.Lstat(target); err != nil {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s/%s", ErrTrashItemNotFound, ref.TrashName, ref.Path)
	}
	resolved.target = target
	resolved.rel = filepath.ToSlash(rel)
	return resolved, nil
}

// isWithin reports whether path is dir or somewhere inside it. Both must be
// clean.
func isWithin(dir, path string) bool {
	return path == dir || strings.HasPrefix(path, dir+string(filepath.Separator))
}

// TrashContentsItem is one entry inside a trashed folder.
type TrashContentsItem struct {
	Name string `json:"name"`
	// Path is relative to the trashed item, and is what a contents listing,
	// a restore or a delete takes to address this entry.
	Path       string    `json:"path"`
	IsDir      bool      `json:"isDir"`
	Size       int64     `json:"size"`
	ModifiedAt time.Time `json:"modifiedAt"`
}

// ListTrashContentsParams names a folder in the trash: a trashed folder, or a
// folder inside one.
type ListTrashContentsParams struct {
	DeviceSerial string
	TrashName    string
	// Path is relative to the trashed item; empty lists the item itself.
	Path string
}

// ListTrashContentsResult is what the folder holds, sorted by name.
type ListTrashContentsResult struct {
	Items []TrashContentsItem
	// OriginalPath is where the folder would be restored to, relative to the
	// device's files directory. Empty when the item's metadata is missing.
	OriginalPath string
	// ExpiresAt is when the hourly purge deletes the trashed item, and
	// everything in it, for good.
	ExpiresAt time.Time
}

// ListTrashContents lists a folder in the device's trash.
func (s *StorageService) ListTrashContents(params ListTrashContentsParams) (ListTrashContentsResult, error) {
	filesDir, err := s.trashFilesDir(params.DeviceSerial)
	if err != nil {
		return ListTrashContentsResult{}, err
	}
	return ListTrashContentsImpl(params, filesDir)
}

// ListTrashContentsImpl is the testable core of ListTrashContents. It never
// returns a nil slice, so an empty folder serializes as [].
func ListTrashContentsImpl(params ListTrashContentsParams, filesDir string) (ListTrashContentsResult, error) {
	ref, err := resolveTrashRef(filepath.Join(filesDir, TrashDir), TrashRef{TrashName: params.TrashName, Path: params.Path})
	if err != nil {
		return ListTrashContentsResult{}, err
	}
	itemInfo, err := os.Lstat(ref.itemPath)
	if err != nil {
		return ListTrashContentsResult{}, fmt.Errorf("%w: %s", ErrTrashItemNotFound, params.TrashName) // coverage: ignore - requires a concurrent purge
	}
	if info, err := os.Lstat(ref.target); err != nil || !info.IsDir() {
		return ListTrashContentsResult{}, fmt.Errorf("%w: %s/%s", ErrNotATrashFolder, params.TrashName, params.Path)
	}
	entries, err := os.ReadDir(ref.target)
	if err != nil {
		return ListTrashContentsResult{}, fmt.Errorf("failed to read trashed folder: %w", err) // coverage: ignore - requires filesystem permission errors
	}

	result := ListTrashContentsResult{Items: make([]TrashContentsItem, 0, len(entries))}
	meta, metaErr := readTrashEntry(ref.itemPath)
	if metaErr == nil {
		result.OriginalPath = path.Join(meta.OriginalPath, ref.rel)
	}
	result.ExpiresAt = trashedAt(params.TrashName, meta, itemInfo.ModTime()).AddDate(0, 0, TrashRetentionDays)

	for _, entry := range entries {
		if IsInternalName(entry.Name()) {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue // coverage: ignore - requires a concurrent purge
		}
		child := TrashContentsItem{
			Name:       entry.Name(),
			Path:       path.Join(ref.rel, entry.Name()),
			IsDir:      entry.IsDir(),
			Size:       info.Size(),
			ModifiedAt: info.ModTime().UTC(),
		}
		if child.IsDir {
			// Bounded by what users deleted, like the trash listing; a folder
			// that cannot be walked reports 0.
			child.Size, _ = GetFolderSize(filepath.Join(ref.target, entry.Name()))
		}
		result.Items = append(result.Items, child)
	}
	return result, nil
}

// RestoreTrashParams names the trashed items, or things inside trashed
// folders, to put back.
type RestoreTrashParams struct {
	DeviceSerial string
	Items        []TrashRef
	// EventBus hears upload (a file) or new_folder (a folder) for each
	// restored item, then trash_changed. Nil skips them.
	EventBus *eventbus.Bus
}

// RestoredItem is one item back at its original location.
type RestoredItem struct {
	// Path is relative to the device's files directory.
	Path  string
	IsDir bool
}

// RestoreTrashResult lists what was restored. When RestoreTrash fails partway
// through, it still lists the items that made it back before the failure.
type RestoreTrashResult struct {
	Restored []RestoredItem
}

// RestoreTrash moves trashed items back to their original locations.
func (s *StorageService) RestoreTrash(params RestoreTrashParams) (RestoreTrashResult, error) {
	filesDir, err := s.trashFilesDir(params.DeviceSerial)
	if err != nil {
		return RestoreTrashResult{}, err
	}
	result, err := RestoreTrashImpl(params, filesDir)
	if params.EventBus != nil {
		// A restored item reappears the way an uploaded file or a new folder
		// does, so open file lists, the file index and the content indexer
		// all pick it up without learning a new event kind.
		for _, item := range result.Restored {
			kind := eventbus.EventUpload
			if item.IsDir {
				kind = eventbus.EventNewFolder
			}
			params.EventBus.Publish(eventbus.Event{Kind: kind, Path: item.Path, DeviceSerial: params.DeviceSerial})
		}
	}
	if len(result.Restored) > 0 {
		publishTrashChanged(params.EventBus, params.DeviceSerial)
	}
	return result, err
}

// RestoreTrashImpl is the testable core of RestoreTrash. Every item is checked
// before any is moved, so a batch that would conflict or names something
// unknown changes nothing. It never overwrites: an occupied original path, or
// two items in the batch landing on the same path or one inside the other, is
// an ErrRestoreConflict.
//
// Something inside a trashed folder goes back to the folder's original path
// joined with its path inside it, and the folder stays in the trash with the
// rest of its contents.
func RestoreTrashImpl(params RestoreTrashParams, filesDir string) (RestoreTrashResult, error) {
	trashRoot := filepath.Join(filesDir, TrashDir)

	type move struct {
		from, to, rel string
		// whole is true when the move takes the trashed item itself, and
		// with it the sidecar's reason to exist.
		whole bool
	}
	moves := make([]move, 0, len(params.Items))
	for _, item := range params.Items {
		ref, err := resolveTrashRef(trashRoot, item)
		if err != nil {
			return RestoreTrashResult{}, err
		}
		meta, err := readTrashEntry(ref.itemPath)
		if err != nil {
			return RestoreTrashResult{}, fmt.Errorf("%w: the original location of %s is unknown", ErrRestoreConflict, item.TrashName)
		}
		restoreTo, err := safeJoin(filesDir, meta.OriginalPath)
		if err != nil || restoreTo == filepath.Clean(filesDir) || IsTrashPath(meta.OriginalPath) {
			return RestoreTrashResult{}, fmt.Errorf("%w: %s has an invalid original location", ErrRestoreConflict, item.TrashName)
		}
		rel := path.Join(meta.OriginalPath, ref.rel)
		restoreTo = filepath.Join(restoreTo, filepath.FromSlash(ref.rel))
		if _, err := os.Lstat(restoreTo); err == nil {
			return RestoreTrashResult{}, fmt.Errorf("%w: %s already exists", ErrRestoreConflict, rel)
		}
		if err := checkRestoreParent(filesDir, restoreTo); err != nil {
			return RestoreTrashResult{}, err
		}
		for _, m := range moves {
			if isWithin(m.to, restoreTo) || isWithin(restoreTo, m.to) {
				return RestoreTrashResult{}, fmt.Errorf("%w: %s and %s overlap", ErrRestoreConflict, m.rel, rel)
			}
		}
		moves = append(moves, move{from: ref.target, to: restoreTo, rel: rel, whole: ref.rel == ""})
	}

	var result RestoreTrashResult
	for _, m := range moves {
		if err := os.MkdirAll(filepath.Dir(m.to), 0o700); err != nil {
			return result, fmt.Errorf("failed to recreate the folder for %s: %w", m.rel, err)
		}
		// os.Rename replaces an existing file, so check again right before
		// it. A write landing between this Lstat and the rename can still be
		// overwritten; closing that needs renameat2(RENAME_NOREPLACE) on Linux
		// and renamex_np(RENAME_EXCL) on darwin behind build tags.
		if _, err := os.Lstat(m.to); err == nil {
			return result, fmt.Errorf("%w: %s already exists", ErrRestoreConflict, m.rel)
		}
		info, err := os.Lstat(m.from)
		if err != nil {
			return result, fmt.Errorf("%w: %s", ErrTrashItemNotFound, filepath.Base(m.from))
		}
		if err := os.Rename(m.from, m.to); err != nil {
			return result, fmt.Errorf("failed to restore %s: %w", m.rel, err)
		}
		if m.whole {
			_ = os.Remove(trashMetaFile(m.from))
		}
		result.Restored = append(result.Restored, RestoredItem{Path: m.rel, IsDir: info.IsDir()})
	}
	return result, nil
}

// checkRestoreParent refuses a restore whose missing parent folders could not
// be recreated because a file now sits where one of them was.
func checkRestoreParent(filesDir, restoreTo string) error {
	root := filepath.Clean(filesDir)
	for dir := filepath.Dir(restoreTo); dir != root && isWithin(root, dir); dir = filepath.Dir(dir) {
		info, err := os.Stat(dir)
		if err != nil {
			continue // missing; the restore recreates it
		}
		if !info.IsDir() {
			rel, _ := filepath.Rel(root, dir)
			return fmt.Errorf("%w: %s is not a folder", ErrRestoreConflict, filepath.ToSlash(rel))
		}
		return nil
	}
	return nil
}

// DeleteTrashParams names trashed items, or things inside trashed folders, to
// delete for good.
type DeleteTrashParams struct {
	DeviceSerial string
	Items        []TrashRef
	// EventBus hears trash_changed once anything is deleted. Nil skips it.
	EventBus *eventbus.Bus
}

// DeleteTrashResult counts the items deleted.
type DeleteTrashResult struct {
	Deleted int
}

// DeleteTrash permanently deletes the named items from the device's trash.
func (s *StorageService) DeleteTrash(params DeleteTrashParams) (DeleteTrashResult, error) {
	filesDir, err := s.trashFilesDir(params.DeviceSerial)
	if err != nil {
		return DeleteTrashResult{}, err
	}
	result, err := DeleteTrashImpl(params, filesDir)
	if result.Deleted > 0 {
		publishTrashChanged(params.EventBus, params.DeviceSerial)
	}
	return result, err
}

// DeleteTrashImpl is the testable core of DeleteTrash. Every reference is
// validated before anything is deleted. Something inside a trashed folder is
// deleted on its own; the folder stays in the trash.
func DeleteTrashImpl(params DeleteTrashParams, filesDir string) (DeleteTrashResult, error) {
	trashRoot := filepath.Join(filesDir, TrashDir)
	refs := make([]resolvedTrashRef, 0, len(params.Items))
	for _, item := range params.Items {
		ref, err := resolveTrashRef(trashRoot, item)
		if err != nil {
			return DeleteTrashResult{}, err
		}
		refs = append(refs, ref)
	}

	var result DeleteTrashResult
	for _, ref := range refs {
		if ref.rel == "" {
			if err := removeTrashItem(ref.itemPath); err != nil {
				return result, err
			}
		} else if err := os.RemoveAll(ref.target); err != nil {
			return result, fmt.Errorf("failed to delete %s: %w", ref.rel, err)
		}
		result.Deleted++
	}
	return result, nil
}

// removeTrashItem deletes a trashed item and its sidecar.
func removeTrashItem(itemPath string) error {
	if err := os.RemoveAll(itemPath); err != nil {
		return fmt.Errorf("failed to delete %s: %w", filepath.Base(itemPath), err)
	}
	_ = os.Remove(trashMetaFile(itemPath))
	return nil
}

// EmptyTrashParams names the device whose trash to empty.
type EmptyTrashParams struct {
	DeviceSerial string
	// EventBus hears trash_changed once anything is deleted. Nil skips it.
	EventBus *eventbus.Bus
}

// EmptyTrashResult counts the items deleted.
type EmptyTrashResult struct {
	Deleted int
}

// EmptyTrash permanently deletes everything in the device's trash.
func (s *StorageService) EmptyTrash(params EmptyTrashParams) (EmptyTrashResult, error) {
	filesDir, err := s.trashFilesDir(params.DeviceSerial)
	if err != nil {
		return EmptyTrashResult{}, err
	}
	deleted, err := EmptyTrashImpl(filesDir)
	if deleted > 0 {
		publishTrashChanged(params.EventBus, params.DeviceSerial)
	}
	return EmptyTrashResult{Deleted: deleted}, err
}

// EmptyTrashImpl is the testable core of EmptyTrash.
func EmptyTrashImpl(filesDir string) (int, error) {
	return removeTrashItems(filesDir, func(TrashItem) bool { return true })
}

// PurgeExpiredTrashImpl deletes the items in filesDir's trash that were
// trashed more than TrashRetentionDays before now, returning how many it
// deleted.
func PurgeExpiredTrashImpl(filesDir string, now time.Time) (int, error) {
	return removeTrashItems(filesDir, func(item TrashItem) bool {
		return !item.ExpiresAt.After(now)
	})
}

// removeTrashItems deletes every listed trash item doom picks.
func removeTrashItems(filesDir string, doom func(TrashItem) bool) (int, error) {
	items, err := ListTrashImpl(filesDir)
	if err != nil {
		return 0, err
	}
	trashRoot := filepath.Join(filesDir, TrashDir)
	deleted := 0
	for _, item := range items {
		if !doom(item) {
			continue
		}
		if err := removeTrashItem(filepath.Join(trashRoot, item.TrashName)); err != nil {
			return deleted, err
		}
		deleted++
	}
	return deleted, nil
}

// PurgeExpiredTrashParams configures a sweep of every device's trash.
type PurgeExpiredTrashParams struct {
	// EventBus hears trash_changed for each device that lost an item. Nil skips it.
	EventBus *eventbus.Bus
}

// PurgeExpiredTrashResult counts the items the sweep deleted.
type PurgeExpiredTrashResult struct {
	Purged int
}

// PurgeExpiredTrash deletes expired items from the trash of every managed
// device and of the default files directory. A device that fails does not stop
// the sweep; its error is joined into the one returned.
func (s *StorageService) PurgeExpiredTrash(params PurgeExpiredTrashParams) (PurgeExpiredTrashResult, error) {
	devices, err := s.GetManagedDevices()
	if err != nil {
		return PurgeExpiredTrashResult{}, err // coverage: ignore - requires device detection failure
	}
	serials := make(map[string]string, len(devices)+1) // filesDir → serial
	for _, d := range devices {
		serial := ""
		if d.UsbInfo != nil {
			serial = d.UsbInfo.GetSerial()
		}
		serials[d.FilesDir] = serial
	}
	if defaultDir, err := GetFilesDir(); err == nil {
		if _, seen := serials[defaultDir]; !seen {
			serials[defaultDir] = ""
		}
	}

	var result PurgeExpiredTrashResult
	var errs []error
	now := time.Now().UTC()
	for filesDir, serial := range serials {
		n, err := PurgeExpiredTrashImpl(filesDir, now)
		result.Purged += n
		if n > 0 {
			publishTrashChanged(params.EventBus, serial)
		}
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", filesDir, err))
		}
	}
	return result, errors.Join(errs...)
}

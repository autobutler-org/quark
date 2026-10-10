package storageutil

import (
	"errors"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// TrashDir is the directory where a device's trashed files live: a visible
// sibling of its FilesDir, next to files/ and tmp/ in the data directory, so
// trashing and restoring stay renames on one filesystem (#2173).
const TrashDir = "trash"

// TrashPathPrefix is where trashed items sit in the files-relative path
// space. Access rows, search rows and thumbnail requests name a trashed item
// by its TrashPath, which starts here. It is where the trash lived on disk
// before #2173, kept so none of those needed rewriting, and FilesDir still
// reserves the name (IsInternalName).
const TrashPathPrefix = ".trash"

// TrashRetentionDays is how long items stay in the trash before auto-expiry.
const TrashRetentionDays = 30

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
	// TrashedBy is the user who trashed the item. It is zero on sidecars
	// written before the trash was per user, which only admins see (#1905).
	TrashedBy int64 `json:"trashedBy,omitempty"`
}

// IsTrashPath reports whether a path relative to a FilesDir is the trash or
// something inside it.
func IsTrashPath(relPath string) bool {
	clean := filepath.ToSlash(filepath.Clean(relPath))
	return clean == TrashPathPrefix || strings.HasPrefix(clean, TrashPathPrefix+"/")
}

// TrashedItem is one file or folder a trash call moved into the trash.
type TrashedItem struct {
	// OriginalPath is where it was, relative to the device's files directory.
	OriginalPath string
	// TrashName addresses it in the trash.
	TrashName string
}

// TrashRoot is the trash directory of the device whose files directory is
// filesDir: <dataDir>/trash, beside it.
func TrashRoot(filesDir string) string {
	return filepath.Join(filepath.Dir(filepath.Clean(filesDir)), TrashDir)
}

// TrashPath is the files-relative path of a trashed item, or of something
// inside a trashed folder when rel is set. An item's access rows live there
// while it is in the trash (#1905).
func TrashPath(trashName, rel string) string {
	return path.Join(TrashPathPrefix, trashName, rel)
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
	// TrashedBy is who trashed the item. It decides who sees the item, and
	// stays out of the response.
	TrashedBy int64 `json:"-"`
}

// TrashRef addresses a trashed item, or something inside a trashed folder.
type TrashRef struct {
	TrashName string `json:"trashName"`
	// Path is relative to the trashed item, slash-separated; empty is the
	// item itself.
	Path string `json:"path"`
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

// RestoredItem is one item back at its original location.
type RestoredItem struct {
	// Path is relative to the device's files directory.
	Path  string
	IsDir bool
	// Source is where the item was in the trash, as a TrashPath.
	Source string
}

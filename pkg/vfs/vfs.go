// Package vfs provides the virtual filesystem layer: a common file interface
// over local disk, in-memory, database-backed and storage-service namespaces,
// a registry that maps namespaces to implementations, and per-path metadata.
package vfs

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// VFS is the host-side interface backing a namespace.
type VFS interface {
	List(ctx context.Context, path string, filter *ListFilter) ([]FileInfo, error)
	Stat(ctx context.Context, path string) (FileInfo, error)
	Open(ctx context.Context, path string) (File, error)
	Write(ctx context.Context, path string, r io.Reader, opts WriteOptions) error
	Delete(ctx context.Context, path string, opts DeleteOptions) error
	MkdirAll(ctx context.Context, path string) error
	Move(ctx context.Context, src, dst string) error
	// Copy copies the file at src to dst within the namespace. It streams
	// through Write, so a copy is never visible under dst half-written, and
	// honors opts.IfNoneMatch as Write does. A directory is [ErrIsDirectory].
	Copy(ctx context.Context, src, dst string, opts CopyOptions) error
	Watch(ctx context.Context, path string) (<-chan WatchEvent, error)
}

// File is an open file in a namespace. Every implementation can seek and read
// at an offset, so a caller that needs random access — http.ServeContent, a zip
// central directory, an image decoder rereading EXIF — takes it directly rather
// than type-asserting the reader or buffering a stream to get it (#2640). The
// disk-backed namespaces return an *os.File; MemVFS and DBVFS, which hold
// bounded content in memory, return a reader over it.
type File interface {
	io.ReadCloser
	io.Seeker
	io.ReaderAt
}

// HostPather is implemented by namespaces backed by a host directory. It
// exists for two uses only: handing a path to an external process (dcraw,
// exiftool, ffmpeg) and symlink resolution in accessutil. A caller never passes
// the result to os.Open; that is what [VFS.Open] is for.
type HostPather interface {
	// HostPath returns the absolute host path of path, which need not exist.
	// A path that escapes the namespace is [ErrPermissionDenied].
	HostPath(ctx context.Context, path string) (string, error)
}

// FileMover is implemented by namespaces backed by a host directory. A caller
// already holding the finished file on disk — a completed chunked upload —
// hands it over instead of copying it, so a 4 GiB file is not written twice
// and never sits half-copied in the tree (#1828).
type FileMover interface {
	// MoveFileIn places the host file at srcAbs at path, honoring
	// opts.IfNoneMatch as Write does. On success srcAbs is gone.
	MoveFileIn(ctx context.Context, srcAbs string, path string, opts WriteOptions) error
}

// Trasher is implemented by namespaces with a trash: a user delete moves an
// item there, where it can be listed, restored or deleted for good, and
// [VFS.Delete] stays the permanent removal (#2641). A trashed item keeps an
// address in the namespace's path space, ".trash/<trash name>/...", and Stat,
// Open and HostPath resolve that form into the trash.
//
// Every batch is checked whole before anything changes, and an operation that
// fails partway still reports what it did before it stopped.
type Trasher interface {
	// Trash moves paths, relative to opts.RootDir, into the trash. A path that
	// no longer exists is skipped.
	Trash(ctx context.Context, paths []string, opts TrashOptions) ([]TrashedItem, error)
	// ListTrash lists the trash, most recently trashed first.
	ListTrash(ctx context.Context) ([]TrashItem, error)
	// ReadTrashEntry returns what the trash recorded about one item: the zero
	// entry when its record is missing.
	ReadTrashEntry(ctx context.Context, trashName string) (TrashEntry, error)
	// ListTrashContents lists a trashed folder, or a folder inside one.
	ListTrashContents(ctx context.Context, ref TrashRef) (TrashContents, error)
	// RestoreTrash puts items back where they came from, never overwriting.
	RestoreTrash(ctx context.Context, refs []TrashRef) ([]RestoredItem, error)
	// DeleteTrash deletes items for good, returning each as a trash path.
	DeleteTrash(ctx context.Context, refs []TrashRef) ([]string, error)
	// EmptyTrash deletes everything in the trash, returning each item as a
	// trash path.
	EmptyTrash(ctx context.Context) ([]string, error)
	// PurgeExpiredTrash deletes the items whose retention ran out by now,
	// returning each as a trash path.
	PurgeExpiredTrash(ctx context.Context, now time.Time) ([]string, error)
}

// TrashOptions controls [Trasher.Trash].
type TrashOptions struct {
	// RootDir is the directory the trashed paths are relative to.
	RootDir string
	// TrashedBy is the user trashing the items, recorded so the trash shows
	// each item to the people it concerns (#1905).
	TrashedBy int64
}

// The trash's records are storageutil's, so the JSON the trash API answers
// with is the one it always has.
type (
	// TrashedItem is one item [Trasher.Trash] moved into the trash.
	TrashedItem = storageutil.TrashedItem
	// TrashItem is one item in the trash.
	TrashItem = storageutil.TrashItem
	// TrashEntry is what the trash recorded about an item.
	TrashEntry = storageutil.TrashEntry
	// TrashRef addresses a trashed item, or something inside a trashed folder.
	TrashRef = storageutil.TrashRef
	// TrashContents is what a folder in the trash holds.
	TrashContents = storageutil.ListTrashContentsResult
	// RestoredItem is one item [Trasher.RestoreTrash] put back.
	RestoredItem = storageutil.RestoredItem
)

type FileInfo struct {
	Name        string    `json:"name"`
	Path        string    `json:"path"`
	Size        int64     `json:"size"`
	IsDir       bool      `json:"is_dir"`
	MimeType    string    `json:"mime_type"`
	ModTime     time.Time `json:"mod_time"`
	ContentHash string    `json:"content_hash"`
	Namespace   string    `json:"namespace"`
	// Device fields are set only by namespaces that span storage devices.
	DeviceSerial string `json:"device_serial,omitempty"`
	DeviceName   string `json:"device_name,omitempty"`
	DevicePath   string `json:"device_path,omitempty"`
}

type Namespace struct {
	ID          string `json:"id"`
	PluginID    string `json:"plugin_id"`
	MountPath   string `json:"mount_path"`
	Description string `json:"description"`
}

type ListFilter struct {
	MimePrefix   string
	Recursive    bool
	MaxResults   int
	AfterPath    string
	SerialFilter []string // if non-empty, restrict to devices with these serials
}

type WriteOptions struct {
	ContentType  string
	IfNoneMatch  string
	ExpectedSize int64
}

// CopyOptions controls [VFS.Copy] and [CopyBetween].
type CopyOptions struct {
	// IfNoneMatch "*" refuses a dst that already exists with [ErrConflict].
	IfNoneMatch string
}

type DeleteOptions struct {
	Recursive bool
}

type WatchEvent struct {
	Op   WatchOp  `json:"op"`
	Path string   `json:"path"`
	Info FileInfo `json:"info"`
}

type WatchOp string

const (
	WatchOpCreated  WatchOp = "created"
	WatchOpModified WatchOp = "modified"
	WatchOpDeleted  WatchOp = "deleted"
	WatchOpRenamed  WatchOp = "renamed"
)

var (
	ErrNotFound          = errors.New("vfs: not found")
	ErrNotEmpty          = errors.New("vfs: directory not empty")
	ErrPermissionDenied  = errors.New("vfs: permission denied")
	ErrWatchNotSupported = errors.New("vfs: watch not supported by this implementation")
	ErrNamespaceConflict = errors.New("vfs: namespace already registered")
	ErrConflict          = errors.New("vfs: conflict")
	// ErrIsDirectory reports a file operation, such as Copy, on a directory.
	ErrIsDirectory = errors.New("vfs: is a directory")
	// ErrTooLarge reports a write over [MaxInMemoryWriteBytes] into a namespace
	// that holds content in memory.
	ErrTooLarge = errors.New("vfs: content too large for an in-memory namespace")
)

// MaxInMemoryWriteBytes caps a write into a namespace that keeps content in
// memory: DBVFS (a SQLite BLOB) and MemVFS (a map). Neither can stream, and
// that is deliberate — they are small-object stores, not file stores. What was
// missing is the bound: without it an oversized write is an OOM with nothing
// to diagnose it by, so the limit is enforced and reported instead (#1723).
//
// The `files` namespace is backed by StorageServiceVFS (see
// deputil.DefaultDependencies), which streams to disk, so no user upload is
// subject to this today. The cap exists so that stays true if a namespace is
// ever re-pointed.
const MaxInMemoryWriteBytes int64 = 64 * 1024 * 1024

type Registry interface {
	Register(ns Namespace, impl VFS) error
	Get(namespaceID string) (VFS, bool)
	List(callerNamespace string) []Namespace
	Unregister(namespaceID string)
}

// NewRegistry returns the default in-process registry.
func NewRegistry() Registry {
	return &memRegistry{
		namespaces: make(map[string]Namespace),
		impls:      make(map[string]VFS),
	}
}

// MetadataStore stores arbitrary JSON key-value pairs keyed by (namespace, path).
// Permission enforcement (key prefix ownership) is the caller's responsibility.
type MetadataStore interface {
	// Get returns all metadata for (namespace, path).
	// Returns an empty map (not an error) if no metadata is set.
	Get(ctx context.Context, namespace, path string) (map[string]json.RawMessage, error)

	// Set merges kv into existing metadata for (namespace, path).
	// Keys in kv overwrite existing values; absent keys are unchanged.
	Set(ctx context.Context, namespace, path string, kv map[string]json.RawMessage) error

	// DeleteKeys removes specific keys from metadata for (namespace, path).
	// Deleting a non-existent key is a no-op.
	DeleteKeys(ctx context.Context, namespace, path string, keys []string) error

	// Query returns all (namespace, path) entries where the given key equals value.
	// Pass value=nil to match any entry that has the key set (existence check).
	Query(ctx context.Context, namespace, key string, value json.RawMessage) ([]MetaEntry, error)
}

// MetaEntry is a single result row from MetadataStore.Query.
type MetaEntry struct {
	Namespace string                     `json:"namespace"`
	Path      string                     `json:"path"`
	Meta      map[string]json.RawMessage `json:"meta"`
}

// SQLiteMetadataStore implements MetadataStore using raw SQL against the vfs_metadata table.
type SQLiteMetadataStore struct {
	db *sql.DB
}

// NewSQLiteMetadataStore returns a MetadataStore backed by the given *sql.DB.
func NewSQLiteMetadataStore(db *sql.DB) *SQLiteMetadataStore {
	return &SQLiteMetadataStore{db: db}
}

// LocalVFS is a VFS backed by a directory on the host filesystem.
type LocalVFS struct {
	root        string
	namespaceID string
}

// NewLocalVFS creates a LocalVFS rooted at the given directory.
// The root directory is created if it does not exist.
func NewLocalVFS(root string, namespaceID string) (*LocalVFS, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(abs, 0o755); err != nil {
		return nil, err
	}
	return &LocalVFS{root: abs, namespaceID: namespaceID}, nil
}

// MemVFS is an in-memory VFS implementation for testing.
type MemVFS struct {
	mu          sync.RWMutex
	files       map[string]memEntry // path -> entry (files only)
	dirs        map[string]bool     // path -> true (directories)
	namespaceID string
}

// NewMemVFS creates a new MemVFS with the given namespace ID.
func NewMemVFS(namespaceID string) *MemVFS {
	m := &MemVFS{
		files:       make(map[string]memEntry),
		dirs:        make(map[string]bool),
		namespaceID: namespaceID,
	}
	// Root directory always exists
	m.dirs[""] = true
	return m
}

// DBVFS implements VFS backed by the vfs_db_entries SQLite table.
// Used for namespaces whose data is virtual (no physical disk backing),
// such as the photos namespace (albums, playlists).
type DBVFS struct {
	db          *sql.DB
	namespaceID string
}

// NewDBVFS returns a DBVFS for the given namespace backed by db.
func NewDBVFS(db *sql.DB, namespaceID string) *DBVFS {
	return &DBVFS{db: db, namespaceID: namespaceID}
}

// StorageServiceVFS adapts storageutil.StorageService to the VFS interface
// for one managed device. The internal drive is the "files" namespace; every
// other device is registered as its own namespace, named by [FilesNamespace]
// (#2639). Every operation is scoped to that device: a namespace whose device
// has gone away answers [ErrNotFound], never the internal drive.
type StorageServiceVFS struct {
	svc         *storageutil.StorageService
	namespaceID string
	// serial is the USB serial of the device this namespace addresses, empty
	// for the internal drive.
	serial string
}

// NewStorageServiceVFS creates a StorageServiceVFS for the internal drive,
// registered under namespaceID.
func NewStorageServiceVFS(svc *storageutil.StorageService, namespaceID string) *StorageServiceVFS {
	return &StorageServiceVFS{svc: svc, namespaceID: namespaceID}
}

// NewDeviceStorageServiceVFS creates a StorageServiceVFS for the managed device
// with the given serial, named [FilesNamespace](serial). The empty serial is
// the internal drive.
func NewDeviceStorageServiceVFS(svc *storageutil.StorageService, serial string) *StorageServiceVFS {
	return &StorageServiceVFS{svc: svc, namespaceID: FilesNamespace(serial), serial: serial}
}

// FilesNamespace is the ID of the namespace holding a managed device's files:
// "files" for the internal drive (the empty serial) and "files:<serial>" for
// any other device. It is the only place that spelling lives.
func FilesNamespace(serial string) string {
	if serial == "" {
		return filesNamespacePrefix
	}
	return filesNamespacePrefix + ":" + serial
}

// FilesNamespaceSerial reports the serial of the device whose files a
// namespace holds — the empty serial for the internal drive's "files" — and
// false for any namespace that is not a [FilesNamespace].
func FilesNamespaceSerial(namespaceID string) (string, bool) {
	if namespaceID == filesNamespacePrefix {
		return "", true
	}
	if serial, ok := deviceNamespaceSerial(namespaceID); ok {
		return serial, true
	}
	return "", false
}

// SyncDeviceNamespacesParams names the registry to reconcile and the storage
// service whose managed devices it should hold.
type SyncDeviceNamespacesParams struct {
	Registry Registry
	Storage  *storageutil.StorageService
}

// SyncDeviceNamespacesResult reports which device namespaces a sync changed.
type SyncDeviceNamespacesResult struct {
	Registered   []string
	Unregistered []string
}

// SyncDeviceNamespaces makes the registry hold one [StorageServiceVFS]
// namespace per attached managed device with a serial, registering the
// devices that appeared and unregistering the ones that went away. The
// internal drive's "files" namespace is not touched. It runs at startup and
// again whenever the device set changes.
func SyncDeviceNamespaces(params SyncDeviceNamespacesParams) (SyncDeviceNamespacesResult, error) {
	return syncDeviceNamespaces(params)
}

// ListDevicesParams describes a listing across every managed device.
type ListDevicesParams struct {
	Ctx      context.Context
	Registry Registry
	Path     string
	// Filter applies to every device. Its SerialFilter, when non-empty,
	// restricts the listing to the devices with those serials, "" being the
	// internal drive.
	Filter *ListFilter
}

// ListDevices lists Path on every managed device by fanning out over the
// device namespaces in the registry: the internal drive's first, then the
// others in namespace order. Folders present on several devices appear once,
// as the first device reports them; every file is kept. A serial with no
// registered namespace contributes nothing. A non-root Path that no device has
// is [ErrNotFound].
func ListDevices(params ListDevicesParams) ([]FileInfo, error) {
	return listDevices(params)
}

// CopyBetween copies the file at srcPath in src to dstPath in dst, which may be
// another namespace — a copy or a move from one device to another. Like
// [VFS.Copy], it streams through dst's Write, so the copy is never visible
// half-written, and it honors opts.IfNoneMatch.
func CopyBetween(ctx context.Context, src VFS, srcPath string, dst VFS, dstPath string, opts CopyOptions) error {
	return copyFile(ctx, src, srcPath, dst, dstPath, opts)
}

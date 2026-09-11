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
	Open(ctx context.Context, path string) (io.ReadCloser, error)
	Write(ctx context.Context, path string, r io.Reader, opts WriteOptions) error
	Delete(ctx context.Context, path string, opts DeleteOptions) error
	MkdirAll(ctx context.Context, path string) error
	Move(ctx context.Context, src, dst string) error
	Watch(ctx context.Context, path string) (<-chan WatchEvent, error)
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

type FileInfo struct {
	Name        string    `json:"name"`
	Path        string    `json:"path"`
	Size        int64     `json:"size"`
	IsDir       bool      `json:"is_dir"`
	MimeType    string    `json:"mime_type"`
	ModTime     time.Time `json:"mod_time"`
	ContentHash string    `json:"content_hash"`
	Namespace   string    `json:"namespace"`
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

// StorageServiceVFS adapts storageutil.StorageService to the VFS interface.
// It is registered as the "files" namespace and backs the /api/v0/files
// handlers during the Phase 1 migration, with no behavior change.
type StorageServiceVFS struct {
	svc         *storageutil.StorageService
	namespaceID string
}

// NewStorageServiceVFS creates a StorageServiceVFS for the given namespace.
func NewStorageServiceVFS(svc *storageutil.StorageService, namespaceID string) *StorageServiceVFS {
	return &StorageServiceVFS{svc: svc, namespaceID: namespaceID}
}

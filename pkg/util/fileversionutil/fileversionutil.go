// Package fileversionutil keeps a file's version history (#1173): earlier
// copies of a file, stored as files in a hidden store beside it
// (storageutil.VersionsDirName), with a small JSON index. It snapshots, lists,
// streams, restores, deletes and prunes those copies, and moves a store along
// with its file. Every byte goes through pkg/vfs and is streamed, never held
// whole. docs/architecture/versions.md is the design.
package fileversionutil

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"path"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// Kind says how a snapshot came to be.
type Kind string

const (
	// KindAuto is a snapshot taken on the user's behalf: before a save, or
	// before a restore. Retention prunes these.
	KindAuto Kind = "auto"
	// KindNamed is a snapshot the user asked for and labeled. Retention keeps
	// these until the user deletes them.
	KindNamed Kind = "named"
)

// Retention and pacing. They live here, together, so the whole policy reads
// in one place.
const (
	// AutoSnapshotInterval is the least time between two auto snapshots of
	// one file. Editors save every few seconds; a history entry per save
	// would bury the ones worth going back to.
	AutoSnapshotInterval = 10 * time.Minute
	// MaxAutoVersions is how many auto snapshots a file keeps.
	MaxAutoVersions = 50
	// MaxAutoAge is how long an auto snapshot is kept.
	MaxAutoAge = 90 * 24 * time.Hour
	// MaxStoreBytes bounds one file's store. Auto snapshots are pruned,
	// oldest first, to stay under it; a named snapshot that cannot fit is
	// refused, and so is a file larger than it.
	MaxStoreBytes int64 = 256 << 20
	// MaxLabelLength bounds a named snapshot's label, in characters.
	MaxLabelLength = 100
	// BeforeRestoreLabel labels the snapshot a restore takes of what it
	// replaces, which is what makes a restore undoable.
	BeforeRestoreLabel = "Before restore"
)

var (
	// ErrInvalidPath reports a path that names no file a store can sit beside:
	// empty, the files root, or inside Quark's own bookkeeping.
	ErrInvalidPath = errors.New("fileversionutil: invalid path")
	// ErrInvalidID reports a version id not in the shape the store mints.
	ErrInvalidID = errors.New("fileversionutil: invalid version id")
	// ErrInvalidLabel reports a label that is too long or carries control
	// characters, or a named snapshot without one.
	ErrInvalidLabel = errors.New("fileversionutil: invalid label")
	// ErrInvalidKind reports a kind that is neither auto nor named.
	ErrInvalidKind = errors.New("fileversionutil: invalid kind")
	// ErrNotFound reports a file, or a version of it, that does not exist.
	ErrNotFound = errors.New("fileversionutil: not found")
	// ErrNotAFile reports a path that is a folder.
	ErrNotAFile = errors.New("fileversionutil: not a file")
	// ErrNotNamed reports a delete of an auto snapshot; retention owns those.
	ErrNotNamed = errors.New("fileversionutil: only named versions can be deleted")
	// ErrTooLarge reports a snapshot that cannot fit in the store: a file
	// over MaxStoreBytes, or a named snapshot the named ones already fill.
	ErrTooLarge = errors.New("fileversionutil: version history is full")
)

// Version is one snapshot of a file.
type Version struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
	Size      int64     `json:"size"`
	SHA256    string    `json:"sha256"`
	Kind      Kind      `json:"kind"`
	Label     string    `json:"label,omitempty"`
	// AuthorID is the account that took the snapshot, zero for the system.
	AuthorID int64 `json:"authorId,omitempty"`
}

// Store serializes the work on each file's history. One Store serves the
// whole server, from deputil.Dependencies.
type Store struct {
	now   func() time.Time
	locks [lockStripes]sync.Mutex
	// pending holds the folders a file was trashed from since startup, the
	// only places a later permanent delete can orphan a store.
	pendingMu sync.Mutex
	pending   map[string]bool
}

// NewStoreParams builds a Store.
type NewStoreParams struct {
	// Now is the clock. Nil is time.Now.
	Now func() time.Time
}

// NewStore returns an empty Store. It starts nothing; Watch does.
func NewStore(params NewStoreParams) *Store {
	now := params.Now
	if now == nil {
		now = time.Now
	}
	return &Store{now: now, pending: make(map[string]bool)}
}

// IsVersioned reports whether saving over the file at p snapshots it first:
// the documents Quark's own editors save, .qslide, .qsheet and .qdoc.
func IsVersioned(p string) bool {
	switch strings.ToLower(path.Ext(p)) {
	case ".qslide", ".qsheet", ".qdoc":
		return true
	}
	return false
}

// SnapshotParams snapshots one file.
type SnapshotParams struct {
	Ctx context.Context
	// FS is the namespace the file is in.
	FS vfs.VFS
	// Path is the file, namespace-relative.
	Path string
	// Kind is auto or named. An auto snapshot within AutoSnapshotInterval of
	// the last one is skipped.
	Kind Kind
	// Label names a named snapshot, and is required for one.
	Label string
	// AuthorID is who asked.
	AuthorID int64
}

// SnapshotResult reports a snapshot.
type SnapshotResult struct {
	// Version is the snapshot that holds the file's content: the new one, or
	// when nothing was copied, the existing one that already stands for it.
	Version Version
	// Created is false when nothing was copied: the content matched the
	// newest snapshot, or an auto snapshot was too soon after the last.
	Created bool
}

// Snapshot copies the file's current content into its store, then prunes.
func (s *Store) Snapshot(params SnapshotParams) (SnapshotResult, error) {
	p, err := cleanPath(params.Path)
	if err != nil {
		return SnapshotResult{}, err
	}
	label, err := checkSnapshotRequest(params.Kind, params.Label)
	if err != nil {
		return SnapshotResult{}, err
	}
	unlock := s.lock(p)
	defer unlock()
	return s.snapshotLocked(snapshotRequest{
		ctx: params.Ctx, fsys: params.FS, path: p, kind: params.Kind, label: label, authorID: params.AuthorID,
	})
}

// ListParams lists a file's versions.
type ListParams struct {
	Ctx  context.Context
	FS   vfs.VFS
	Path string
}

// ListResult is a file's versions, newest first. A file with no history has
// none.
type ListResult struct {
	Versions []Version
}

// List returns a file's versions.
func (s *Store) List(params ListParams) (ListResult, error) {
	p, err := cleanPath(params.Path)
	if err != nil {
		return ListResult{}, err
	}
	versions, err := readIndex(params.Ctx, params.FS, storeDir(p))
	return ListResult{Versions: versions}, err
}

// OpenParams opens one version's content.
type OpenParams struct {
	Ctx  context.Context
	FS   vfs.VFS
	Path string
	ID   string
}

// OpenResult streams a version's content. The caller closes Reader.
type OpenResult struct {
	Reader  io.ReadCloser
	Version Version
}

// Open returns a reader over a version's content.
func (s *Store) Open(params OpenParams) (OpenResult, error) {
	p, err := cleanPath(params.Path)
	if err != nil {
		return OpenResult{}, err
	}
	if !validID(params.ID) {
		return OpenResult{}, ErrInvalidID
	}
	dir := storeDir(p)
	version, err := findVersion(params.Ctx, params.FS, dir, params.ID)
	if err != nil {
		return OpenResult{}, err
	}
	snap := snapPath(dir, version.ID)
	// The size a download announces is the snapshot's own, not what the
	// index claims.
	info, err := params.FS.Stat(params.Ctx, snap)
	if err != nil {
		return OpenResult{}, notFound(err)
	}
	version.Size = info.Size
	rc, err := params.FS.Open(params.Ctx, snap)
	if err != nil {
		return OpenResult{}, notFound(err)
	}
	return OpenResult{Reader: rc, Version: version}, nil
}

// RestoreParams puts a version back.
type RestoreParams struct {
	Ctx context.Context
	FS  vfs.VFS
	// EventBus is told the file changed. Nil tells nobody.
	EventBus *eventbus.Bus
	Path     string
	ID       string
	AuthorID int64
}

// RestoreResult reports a restore.
type RestoreResult struct {
	// Restored is the version now in the file.
	Restored Version
	// Backup holds what the file held before; restoring it undoes this.
	Backup Version
}

// Restore snapshots the file's current content, then replaces the file with
// the version, atomically, through the namespace's write.
func (s *Store) Restore(params RestoreParams) (RestoreResult, error) {
	p, err := cleanPath(params.Path)
	if err != nil {
		return RestoreResult{}, err
	}
	if !validID(params.ID) {
		return RestoreResult{}, ErrInvalidID
	}
	unlock := s.lock(p)
	defer unlock()

	dir := storeDir(p)
	target, err := findVersion(params.Ctx, params.FS, dir, params.ID)
	if err != nil {
		return RestoreResult{}, err
	}
	backup, err := s.snapshotLocked(snapshotRequest{
		ctx: params.Ctx, fsys: params.FS, path: p, kind: KindAuto, label: BeforeRestoreLabel,
		authorID: params.AuthorID, force: true, pinned: target.ID,
	})
	if err != nil {
		return RestoreResult{}, err
	}
	rc, err := params.FS.Open(params.Ctx, snapPath(dir, target.ID))
	if err != nil {
		return RestoreResult{}, notFound(err)
	}
	defer func() { _ = rc.Close() }()
	if err := params.FS.Write(params.Ctx, p, rc, vfs.WriteOptions{}); err != nil {
		return RestoreResult{}, err
	}
	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: p})
	}
	return RestoreResult{Restored: target, Backup: backup.Version}, nil
}

// DeleteParams deletes one named version.
type DeleteParams struct {
	Ctx  context.Context
	FS   vfs.VFS
	Path string
	ID   string
}

// DeleteResult reports a delete.
type DeleteResult struct{}

// Delete removes a named version. Auto versions are retention's to remove.
func (s *Store) Delete(params DeleteParams) (DeleteResult, error) {
	p, err := cleanPath(params.Path)
	if err != nil {
		return DeleteResult{}, err
	}
	if !validID(params.ID) {
		return DeleteResult{}, ErrInvalidID
	}
	unlock := s.lock(p)
	defer unlock()

	dir := storeDir(p)
	versions, err := readIndex(params.Ctx, params.FS, dir)
	if err != nil {
		return DeleteResult{}, err
	}
	i := indexOf(versions, params.ID)
	if i < 0 {
		return DeleteResult{}, ErrNotFound
	}
	if versions[i].Kind != KindNamed {
		return DeleteResult{}, ErrNotNamed
	}
	removed := versions[i]
	versions = append(versions[:i], versions[i+1:]...)
	return DeleteResult{}, commit(params.Ctx, params.FS, dir, versions, []Version{removed})
}

// PruneParams applies retention to one file's store.
type PruneParams struct {
	Ctx  context.Context
	FS   vfs.VFS
	Path string
}

// PruneResult lists the versions retention removed.
type PruneResult struct {
	Removed []Version
}

// Prune removes the auto snapshots retention no longer keeps, and any
// snapshot file the index does not list. Snapshot runs it after every copy.
func (s *Store) Prune(params PruneParams) (PruneResult, error) {
	p, err := cleanPath(params.Path)
	if err != nil {
		return PruneResult{}, err
	}
	unlock := s.lock(p)
	defer unlock()
	dir := storeDir(p)
	versions, err := readIndex(params.Ctx, params.FS, dir)
	if err != nil {
		return PruneResult{}, err
	}
	kept, removed := prune(versions, s.now(), "")
	return PruneResult{Removed: removed}, commit(params.Ctx, params.FS, dir, kept, removed)
}

// FollowParams carries a store along with a file that moved.
type FollowParams struct {
	Ctx     context.Context
	FS      vfs.VFS
	OldPath string
	NewPath string
}

// FollowResult reports whether a store moved.
type FollowResult struct {
	Moved bool
}

// Follow moves the store of the file that was at OldPath to sit beside it at
// NewPath. It moves nothing unless the file really left OldPath for NewPath:
// a store at OldPath whose file is still there belongs to that file. A store
// already at NewPath belonged to the file the move replaced, and goes.
func (s *Store) Follow(params FollowParams) (FollowResult, error) {
	oldPath, err := cleanPath(params.OldPath)
	if err != nil {
		return FollowResult{}, err
	}
	newPath, err := cleanPath(params.NewPath)
	if err != nil {
		return FollowResult{}, err
	}
	if oldPath == newPath {
		return FollowResult{}, nil
	}
	unlock := s.lock(oldPath, newPath)
	defer unlock()

	ctx, fsys := params.Ctx, params.FS
	oldStore, newStore := storeDir(oldPath), storeDir(newPath)
	if !exists(ctx, fsys, oldStore) || exists(ctx, fsys, oldPath) {
		return FollowResult{}, nil
	}
	if info, err := fsys.Stat(ctx, newPath); err != nil || info.IsDir {
		return FollowResult{}, nil
	}
	if err := removeAll(ctx, fsys, newStore); err != nil {
		return FollowResult{}, err
	}
	if err := fsys.Move(ctx, oldStore, newStore); err != nil {
		return FollowResult{}, err
	}
	removeIfEmpty(ctx, fsys, path.Dir(oldStore))
	return FollowResult{Moved: true}, nil
}

// SweepParams removes the stores in one folder whose file is gone for good.
type SweepParams struct {
	Ctx context.Context
	FS  vfs.VFS
	// Dir is the folder, namespace-relative; "" is the root.
	Dir string
	// Restorable reports whether the trash holds an item that would restore
	// to a path. A store whose file is in the trash is kept for its return.
	Restorable func(p string) bool
}

// SweepResult lists the files whose stores were removed.
type SweepResult struct {
	Removed []string
}

// Sweep removes every store in Dir whose file neither exists nor waits in
// the trash.
func (s *Store) Sweep(params SweepParams) (SweepResult, error) {
	var result SweepResult
	ctx, fsys := params.Ctx, params.FS
	versionsDir := path.Join(cleanDir(params.Dir), storageutil.VersionsDirName)
	entries, err := fsys.List(ctx, versionsDir, nil)
	if err != nil {
		if errors.Is(err, vfs.ErrNotFound) {
			return result, nil
		}
		return result, err
	}
	for _, entry := range entries {
		file := path.Join(cleanDir(params.Dir), entry.Name)
		if _, err := cleanPath(file); err != nil {
			continue
		}
		unlock := s.lock(file)
		gone := !exists(ctx, fsys, file) && (params.Restorable == nil || !params.Restorable(file))
		var removeErr error
		if gone {
			removeErr = removeAll(ctx, fsys, storeDir(file))
		}
		unlock()
		if removeErr != nil {
			return result, removeErr
		}
		if gone {
			result.Removed = append(result.Removed, file)
		}
	}
	removeIfEmpty(ctx, fsys, versionsDir)
	return result, nil
}

// BeforeSaveParams builds the hook an upload calls before it overwrites a
// file.
type BeforeSaveParams struct {
	Ctx      context.Context
	FS       vfs.VFS
	AuthorID int64
}

// BeforeSave returns the hook an upload runs before it saves over the file at
// a path: an auto snapshot of the old content, for the documents IsVersioned
// names. A failure is logged and never fails the save.
func (s *Store) BeforeSave(params BeforeSaveParams) func(p string) {
	return func(p string) {
		if !IsVersioned(p) {
			return
		}
		if _, err := s.Snapshot(SnapshotParams{
			Ctx: params.Ctx, FS: params.FS, Path: p, Kind: KindAuto, AuthorID: params.AuthorID,
		}); err != nil {
			slog.Warn("versions: could not snapshot before a save", "path", p, "err", err)
		}
	}
}

// WatchParams keeps stores beside their files.
type WatchParams struct {
	Bus *eventbus.Bus
	// Registry holds the files namespace the stores are in.
	Registry vfs.Registry
}

// Watch subscribes to the bus and follows the internal device's files: a
// moved file's store moves with it, and once something leaves the trash for
// good, the folders a file was trashed from are swept. The subscription is
// made before Watch returns, so no event published afterwards is missed.
func (s *Store) Watch(params WatchParams) {
	if s == nil || params.Bus == nil {
		return
	}
	events, _ := params.Bus.Subscribe("file-versions")
	go func() {
		for evt := range events {
			s.handleEvent(params, evt)
		}
	}()
}

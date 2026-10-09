package fileversionutil

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"hash/fnv"
	"io"
	"log/slog"
	"path"
	"regexp"
	"slices"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// idPattern is the only shape a version id takes. An id is checked against it
// before it reaches a path, so no id can name anything outside its store.
var idPattern = regexp.MustCompile(`^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$`)

func validID(id string) bool {
	return idPattern.MatchString(id)
}

// newID mints an id: the time, which sorts, and 32 random bits, which keep two
// snapshots in one second apart.
func newID(now time.Time) (string, error) {
	var suffix [4]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		return "", err
	}
	return now.UTC().Format(idStampLayout) + "-" + hex.EncodeToString(suffix[:]), nil
}

// cleanDir spells a folder one way: slash-separated, no leading slash, and ""
// for the root.
func cleanDir(p string) string {
	return strings.TrimPrefix(path.Clean("/"+strings.ReplaceAll(p, "\\", "/")), "/")
}

// cleanPath is cleanDir for a file a store can sit beside. The root, and
// anything inside Quark's own bookkeeping (the trash, a store), is refused.
func cleanPath(p string) (string, error) {
	clean := cleanDir(p)
	if clean == "" || slices.ContainsFunc(strings.Split(clean, "/"), storageutil.IsInternalName) {
		return "", ErrInvalidPath
	}
	return clean, nil
}

// storeDir is where the file at p keeps its versions.
func storeDir(p string) string {
	return path.Join(path.Dir(p), storageutil.VersionsDirName, path.Base(p))
}

func snapPath(dir, id string) string {
	return path.Join(dir, id+snapExt)
}

// checkSnapshotRequest validates a kind and its label, and returns the label
// trimmed.
func checkSnapshotRequest(kind Kind, label string) (string, error) {
	if kind != KindAuto && kind != KindNamed {
		return "", ErrInvalidKind
	}
	label = strings.TrimSpace(label)
	if kind == KindNamed && label == "" {
		return "", ErrInvalidLabel
	}
	if utf8.RuneCountInString(label) > MaxLabelLength || !utf8.ValidString(label) ||
		strings.ContainsFunc(label, unicode.IsControl) {
		return "", ErrInvalidLabel
	}
	return label, nil
}

// lock takes the stripes the given files map to, in order, and returns the
// unlock.
func (s *Store) lock(files ...string) func() {
	stripes := make([]int, 0, len(files))
	for _, f := range files {
		h := fnv.New32a()
		_, _ = h.Write([]byte(storeDir(f)))
		stripes = append(stripes, int(h.Sum32()%lockStripes))
	}
	slices.Sort(stripes)
	stripes = slices.Compact(stripes)
	for _, i := range stripes {
		s.locks[i].Lock()
	}
	return func() {
		for _, i := range slices.Backward(stripes) {
			s.locks[i].Unlock()
		}
	}
}

// snapshotLocked is Snapshot with the file's lock held.
func (s *Store) snapshotLocked(req snapshotRequest) (SnapshotResult, error) {
	ctx, fsys, p := req.ctx, req.fsys, req.path
	info, err := fsys.Stat(ctx, p)
	if err != nil {
		return SnapshotResult{}, notFound(err)
	}
	if info.IsDir {
		return SnapshotResult{}, ErrNotAFile
	}
	if info.Size > MaxStoreBytes {
		return SnapshotResult{}, ErrTooLarge
	}
	dir := storeDir(p)
	versions, err := readIndex(ctx, fsys, dir)
	if err != nil {
		return SnapshotResult{}, err
	}
	now := s.now().UTC()
	if req.kind == KindAuto && !req.force {
		if i := slices.IndexFunc(versions, isAuto); i >= 0 && now.Sub(versions[i].CreatedAt) < AutoSnapshotInterval {
			return SnapshotResult{Version: versions[i]}, nil
		}
	}

	sum, err := hashFile(ctx, fsys, p)
	if err != nil {
		return SnapshotResult{}, err
	}
	if len(versions) > 0 && versions[0].SHA256 == sum {
		// Nothing new to copy. A name given to content the newest auto
		// snapshot already holds is put on that snapshot.
		if req.kind == KindNamed && versions[0].Kind == KindAuto {
			versions[0].Kind, versions[0].Label, versions[0].AuthorID = KindNamed, req.label, req.authorID
			if err := commit(ctx, fsys, dir, versions, nil); err != nil {
				return SnapshotResult{}, err
			}
		}
		return SnapshotResult{Version: versions[0]}, nil
	}
	if req.kind == KindNamed && namedBytes(versions)+info.Size > MaxStoreBytes {
		return SnapshotResult{}, ErrTooLarge
	}

	version, err := copySnapshot(req, dir, now)
	if err != nil {
		return SnapshotResult{}, err
	}
	versions = append([]Version{version}, versions...)
	kept, removed := prune(versions, now, req.pinned)
	if err := commit(ctx, fsys, dir, kept, removed); err != nil {
		return SnapshotResult{}, err
	}
	return SnapshotResult{Version: version, Created: true}, nil
}

// copySnapshot streams the file into a new snapshot and describes it. The
// hash and size are of the bytes copied, whatever the file held before.
func copySnapshot(req snapshotRequest, dir string, now time.Time) (Version, error) {
	ctx, fsys := req.ctx, req.fsys
	id, err := newID(now)
	if err != nil {
		return Version{}, err
	}
	rc, err := fsys.Open(ctx, req.path)
	if err != nil {
		return Version{}, notFound(err)
	}
	defer func() { _ = rc.Close() }()
	h := sha256.New()
	var counted countingWriter
	// One byte over the bound says the file grew past it after the Stat.
	body := io.TeeReader(io.LimitReader(rc, MaxStoreBytes+1), io.MultiWriter(h, &counted))
	target := snapPath(dir, id)
	if err := fsys.Write(ctx, target, body, vfs.WriteOptions{}); err != nil {
		return Version{}, err
	}
	if counted.n > MaxStoreBytes {
		_ = fsys.Delete(ctx, target, vfs.DeleteOptions{})
		return Version{}, ErrTooLarge
	}
	return Version{
		ID: id, CreatedAt: now, Size: counted.n, SHA256: hex.EncodeToString(h.Sum(nil)),
		Kind: req.kind, Label: req.label, AuthorID: req.authorID,
	}, nil
}

func isAuto(v Version) bool { return v.Kind == KindAuto }

func namedBytes(versions []Version) int64 {
	var n int64
	for _, v := range versions {
		if v.Kind == KindNamed {
			n += v.Size
		}
	}
	return n
}

// prune applies retention to versions, newest first, and returns what it
// keeps and what it removes. Named versions, the newest version and the
// pinned one are always kept; auto versions go when they are past
// MaxAutoVersions or MaxAutoAge, and then oldest first while the store is over
// MaxStoreBytes.
func prune(versions []Version, now time.Time, pinned string) (kept, removed []Version) {
	autos := 0
	var total int64
	for i, v := range versions {
		keep := v.Kind == KindNamed || i == 0 || v.ID == pinned ||
			(autos < MaxAutoVersions && now.Sub(v.CreatedAt) <= MaxAutoAge)
		if !keep {
			removed = append(removed, v)
			continue
		}
		if v.Kind == KindAuto {
			autos++
		}
		total += v.Size
		kept = append(kept, v)
	}
	for i := len(kept) - 1; i > 0 && total > MaxStoreBytes; i-- {
		if v := kept[i]; v.Kind == KindAuto && v.ID != pinned {
			total -= v.Size
			removed = append(removed, v)
			kept = slices.Delete(kept, i, i+1)
		}
	}
	return kept, removed
}

// readIndex reads a store's index, newest first. A missing store has no
// versions. An index that will not parse is rebuilt from the snapshots in the
// store, so a damaged index loses labels, never content. Entries with an id
// the store would not mint are dropped.
func readIndex(ctx context.Context, fsys vfs.VFS, dir string) ([]Version, error) {
	rc, err := fsys.Open(ctx, path.Join(dir, indexName))
	if err != nil {
		if errors.Is(err, vfs.ErrNotFound) {
			return nil, nil
		}
		return nil, err
	}
	defer func() { _ = rc.Close() }()
	var buf bytes.Buffer
	n, err := io.Copy(&buf, io.LimitReader(rc, maxIndexBytes+1))
	if err != nil {
		return nil, err
	}
	var index indexFile
	if n > maxIndexBytes || json.Unmarshal(buf.Bytes(), &index) != nil {
		slog.Warn("versions: rebuilding an unreadable index", "store", dir)
		return rebuildIndex(ctx, fsys, dir)
	}
	return slices.DeleteFunc(index.Versions, func(v Version) bool {
		return !validID(v.ID) || (v.Kind != KindAuto && v.Kind != KindNamed)
	}), nil
}

// rebuildIndex lists the snapshots in a store as auto versions, newest first,
// dated by their ids.
func rebuildIndex(ctx context.Context, fsys vfs.VFS, dir string) ([]Version, error) {
	entries, err := fsys.List(ctx, dir, nil)
	if err != nil {
		return nil, err
	}
	var versions []Version
	for _, entry := range entries {
		id := strings.TrimSuffix(entry.Name, snapExt)
		if entry.IsDir || !strings.HasSuffix(entry.Name, snapExt) || !validID(id) {
			continue
		}
		created, err := time.Parse(idStampLayout, id[:len(idStampLayout)])
		if err != nil {
			continue
		}
		versions = append(versions, Version{ID: id, CreatedAt: created, Size: entry.Size, Kind: KindAuto})
	}
	slices.SortFunc(versions, func(a, b Version) int { return strings.Compare(b.ID, a.ID) })
	return versions, nil
}

func indexOf(versions []Version, id string) int {
	return slices.IndexFunc(versions, func(v Version) bool { return v.ID == id })
}

func findVersion(ctx context.Context, fsys vfs.VFS, dir, id string) (Version, error) {
	versions, err := readIndex(ctx, fsys, dir)
	if err != nil {
		return Version{}, err
	}
	i := indexOf(versions, id)
	if i < 0 {
		return Version{}, ErrNotFound
	}
	return versions[i], nil
}

// commit writes a store's index, then deletes the snapshots it no longer
// lists: removed, and any stray a crash left between those two steps. The
// index goes first, so it never lists a snapshot that is gone. A store left
// with no versions is removed whole.
func commit(ctx context.Context, fsys vfs.VFS, dir string, versions, removed []Version) error {
	if len(versions) == 0 {
		if err := removeAll(ctx, fsys, dir); err != nil {
			return err
		}
		removeIfEmpty(ctx, fsys, path.Dir(dir))
		return nil
	}
	body, err := json.Marshal(indexFile{Versions: versions})
	if err != nil {
		return err
	}
	if err := fsys.Write(ctx, path.Join(dir, indexName), bytes.NewReader(body), vfs.WriteOptions{}); err != nil {
		return err
	}
	for _, v := range removed {
		if err := fsys.Delete(ctx, snapPath(dir, v.ID), vfs.DeleteOptions{}); err != nil && !errors.Is(err, vfs.ErrNotFound) {
			return err
		}
	}
	entries, err := fsys.List(ctx, dir, nil)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.Name == indexName || indexOf(versions, strings.TrimSuffix(entry.Name, snapExt)) >= 0 {
			continue
		}
		if err := removeAll(ctx, fsys, path.Join(dir, entry.Name)); err != nil {
			return err
		}
	}
	return nil
}

// hashFile is the SHA-256 of a file's content, streamed.
func hashFile(ctx context.Context, fsys vfs.VFS, p string) (string, error) {
	rc, err := fsys.Open(ctx, p)
	if err != nil {
		return "", notFound(err)
	}
	defer func() { _ = rc.Close() }()
	h := sha256.New()
	if _, err := io.Copy(h, rc); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func exists(ctx context.Context, fsys vfs.VFS, p string) bool {
	_, err := fsys.Stat(ctx, p)
	return err == nil
}

func removeAll(ctx context.Context, fsys vfs.VFS, p string) error {
	if err := fsys.Delete(ctx, p, vfs.DeleteOptions{Recursive: true}); err != nil && !errors.Is(err, vfs.ErrNotFound) {
		return err
	}
	return nil
}

// removeIfEmpty removes a folder with nothing in it, so a file whose last
// store went does not leave an empty .quark-versions behind.
func removeIfEmpty(ctx context.Context, fsys vfs.VFS, dir string) {
	if entries, err := fsys.List(ctx, dir, nil); err == nil && len(entries) == 0 {
		_ = fsys.Delete(ctx, dir, vfs.DeleteOptions{Recursive: true})
	}
}

// notFound turns the namespace's not-found into this package's, and leaves
// every other error as it is.
func notFound(err error) error {
	if errors.Is(err, vfs.ErrNotFound) {
		return ErrNotFound
	}
	return err
}

// handleEvent is Watch's reaction to one event on the internal device.
func (s *Store) handleEvent(params WatchParams, evt eventbus.Event) {
	if evt.DeviceSerial != "" {
		return
	}
	fsys, err := fileutil.FilesVFS(params.Registry, "")
	if err != nil {
		return
	}
	ctx := context.Background()
	switch evt.Kind {
	case eventbus.EventMove:
		if _, err := s.Follow(FollowParams{Ctx: ctx, FS: fsys, OldPath: evt.Path, NewPath: evt.NewPath}); err != nil &&
			!errors.Is(err, ErrInvalidPath) {
			slog.Warn("versions: could not move a store with its file", "from", evt.Path, "to", evt.NewPath, "err", err)
		}
	case eventbus.EventDelete:
		if p, err := cleanPath(evt.Path); err == nil {
			s.pendingMu.Lock()
			s.pending[cleanDir(path.Dir(p))] = true
			s.pendingMu.Unlock()
		}
	case eventbus.EventTrashChanged:
		s.sweepPending(ctx, fsys)
	}
}

// sweepPending sweeps every folder a file was trashed from, checking the
// trash once for all of them. A folder is forgotten once it has no stores.
func (s *Store) sweepPending(ctx context.Context, fsys vfs.VFS) {
	trasher, ok := fsys.(vfs.Trasher)
	if !ok {
		return
	}
	s.pendingMu.Lock()
	dirs := make([]string, 0, len(s.pending))
	for dir := range s.pending {
		dirs = append(dirs, dir)
	}
	s.pendingMu.Unlock()
	if len(dirs) == 0 {
		return
	}
	items, err := trasher.ListTrash(ctx)
	if err != nil {
		slog.Warn("versions: could not list the trash", "err", err)
		return
	}
	restorable := make(map[string]bool, len(items))
	for _, item := range items {
		restorable[cleanDir(item.OriginalPath)] = true
	}
	for _, dir := range dirs {
		if _, err := s.Sweep(SweepParams{
			Ctx: ctx, FS: fsys, Dir: dir, Restorable: func(p string) bool { return restorable[p] },
		}); err != nil {
			slog.Warn("versions: could not sweep a folder", "dir", dir, "err", err)
			continue
		}
		if !exists(ctx, fsys, path.Join(dir, storageutil.VersionsDirName)) {
			s.pendingMu.Lock()
			delete(s.pending, dir)
			s.pendingMu.Unlock()
		}
	}
}

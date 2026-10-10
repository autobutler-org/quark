package fileversionutil

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/trashutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

type fakeDetector struct{ mountPoint string }

func (d fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Disk", MountPoint: d.mountPoint, IsInternal: true}}, nil
}

// fixture is a Store over the production StorageService-backed files
// namespace, on a real directory, with a clock the test moves.
type fixture struct {
	store    *Store
	fs       vfs.VFS
	svc      *storageutil.StorageService
	registry vfs.Registry
	filesDir string
	now      time.Time
	ctx      context.Context
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(fakeDetector{mountPoint: mountPoint})
	fsys := vfs.NewStorageServiceVFS(svc, "files")
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, fsys); err != nil {
		t.Fatal(err)
	}
	f := &fixture{
		fs: fsys, svc: svc, registry: registry, filesDir: filesDir, ctx: context.Background(),
		now: time.Date(2026, 10, 5, 10, 0, 0, 0, time.UTC),
	}
	f.store = NewStore(NewStoreParams{Now: func() time.Time { return f.now }})
	return f
}

func (f *fixture) write(t *testing.T, rel, content string) {
	t.Helper()
	full := filepath.Join(f.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) read(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(f.filesDir, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func (f *fixture) exists(rel string) bool {
	_, err := os.Stat(filepath.Join(f.filesDir, filepath.FromSlash(rel)))
	return err == nil
}

func (f *fixture) snapshot(t *testing.T, p string, kind Kind, label string) SnapshotResult {
	t.Helper()
	res, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: p, Kind: kind, Label: label, AuthorID: 7})
	if err != nil {
		t.Fatalf("Snapshot(%s, %s): %v", p, kind, err)
	}
	return res
}

func (f *fixture) list(t *testing.T, p string) []Version {
	t.Helper()
	res, err := f.store.List(ListParams{Ctx: f.ctx, FS: f.fs, Path: p})
	if err != nil {
		t.Fatalf("List(%s): %v", p, err)
	}
	return res.Versions
}

func (f *fixture) content(t *testing.T, p, id string) string {
	t.Helper()
	res, err := f.store.Open(OpenParams{Ctx: f.ctx, FS: f.fs, Path: p, ID: id})
	if err != nil {
		t.Fatalf("Open(%s, %s): %v", p, id, err)
	}
	defer func() { _ = res.Reader.Close() }()
	b, err := io.ReadAll(res.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestSnapshot_CopiesTheFileAndListsIt(t *testing.T) {
	f := newFixture(t)
	f.write(t, "docs/pitch.qslide", "one")

	res := f.snapshot(t, "docs/pitch.qslide", KindNamed, "  Draft  ")
	if !res.Created || res.Version.Label != "Draft" || res.Version.Size != 3 || res.Version.AuthorID != 7 {
		t.Fatalf("snapshot = %+v, want a created 3-byte version labeled Draft by 7", res)
	}
	versions := f.list(t, "/docs/pitch.qslide")
	if len(versions) != 1 || versions[0].ID != res.Version.ID || versions[0].Kind != KindNamed {
		t.Fatalf("versions = %+v, want the one snapshot", versions)
	}
	if got := f.content(t, "docs/pitch.qslide", res.Version.ID); got != "one" {
		t.Errorf("content = %q, want %q", got, "one")
	}
	if !f.exists("docs/" + storageutil.VersionsDirName + "/pitch.qslide/" + res.Version.ID + snapExt) {
		t.Error("snapshot is not stored beside the file")
	}
}

func TestSnapshot_IdenticalContentIsNotCopiedAgain(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "same")
	first := f.snapshot(t, "a.qdoc", KindAuto, "")

	f.now = f.now.Add(time.Hour)
	again := f.snapshot(t, "a.qdoc", KindAuto, "")
	if again.Created || again.Version.ID != first.Version.ID {
		t.Fatalf("auto over identical content = %+v, want the first version back uncreated", again)
	}
	// Naming content the newest auto snapshot already holds names that one.
	named := f.snapshot(t, "a.qdoc", KindNamed, "Final")
	if named.Created || named.Version.ID != first.Version.ID || named.Version.Kind != KindNamed {
		t.Fatalf("named over identical content = %+v, want the auto version promoted", named)
	}
	if versions := f.list(t, "a.qdoc"); len(versions) != 1 || versions[0].Label != "Final" {
		t.Fatalf("versions = %+v, want one version labeled Final", versions)
	}
}

func TestSnapshot_AutoIsRateLimitedPerFile(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qsheet", "v1")
	f.write(t, "b.qsheet", "v1")
	first := f.snapshot(t, "a.qsheet", KindAuto, "")

	f.write(t, "a.qsheet", "v2")
	f.now = f.now.Add(AutoSnapshotInterval - time.Second)
	if res := f.snapshot(t, "a.qsheet", KindAuto, ""); res.Created || res.Version.ID != first.Version.ID {
		t.Fatalf("auto inside the interval = %+v, want it skipped", res)
	}
	if res := f.snapshot(t, "b.qsheet", KindAuto, ""); !res.Created {
		t.Fatal("another file's auto snapshot was held back by this one's limit")
	}
	if res := f.snapshot(t, "a.qsheet", KindNamed, "Mine"); !res.Created {
		t.Fatal("a named snapshot was held back by the auto limit")
	}
	f.write(t, "a.qsheet", "v3")
	f.now = f.now.Add(2 * time.Second)
	if res := f.snapshot(t, "a.qsheet", KindAuto, ""); !res.Created {
		t.Fatal("auto after the interval was skipped")
	}
	if n := len(f.list(t, "a.qsheet")); n != 3 {
		t.Errorf("a.qsheet has %d versions, want 3", n)
	}
}

func TestRestore_IsUndoableAndARestoreCanBeRestored(t *testing.T) {
	f := newFixture(t)
	bus := eventbus.New()
	events, cancel := bus.Subscribe("test")
	defer cancel()

	f.write(t, "deck.qslide", "A")
	a := f.snapshot(t, "deck.qslide", KindNamed, "A")
	f.write(t, "deck.qslide", "B")

	restore := func(id string) RestoreResult {
		t.Helper()
		res, err := f.store.Restore(RestoreParams{Ctx: f.ctx, FS: f.fs, EventBus: bus, Path: "deck.qslide", ID: id})
		if err != nil {
			t.Fatalf("Restore(%s): %v", id, err)
		}
		return res
	}
	first := restore(a.Version.ID)
	if got := f.read(t, "deck.qslide"); got != "A" {
		t.Fatalf("after restore the file holds %q, want A", got)
	}
	if first.Backup.Label != BeforeRestoreLabel || f.content(t, "deck.qslide", first.Backup.ID) != "B" {
		t.Fatalf("backup = %+v, want B kept under %q", first.Backup, BeforeRestoreLabel)
	}
	select {
	case evt := <-events:
		if evt.Kind != eventbus.EventUpload || evt.Path != "deck.qslide" {
			t.Errorf("event = %+v, want an upload of deck.qslide", evt)
		}
	case <-time.After(time.Second):
		t.Error("restore published no event")
	}

	// Undo the restore by restoring its backup; that restore backs up A.
	second := restore(first.Backup.ID)
	if got := f.read(t, "deck.qslide"); got != "B" {
		t.Fatalf("after undoing the restore the file holds %q, want B", got)
	}
	if f.content(t, "deck.qslide", second.Backup.ID) != "A" {
		t.Errorf("undo's backup does not hold A")
	}
}

func TestRestore_RefusesAnUnknownVersionAndLeavesTheFile(t *testing.T) {
	f := newFixture(t)
	f.write(t, "deck.qslide", "A")
	_, err := f.store.Restore(RestoreParams{Ctx: f.ctx, FS: f.fs, Path: "deck.qslide", ID: "20261005T101530Z-3f9a0c1d"})
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
	if f.read(t, "deck.qslide") != "A" || f.exists(storageutil.VersionsDirName) {
		t.Error("a refused restore changed the file or made a store")
	}
}

func TestRetention_KeepsTheNewestAutosAndEveryNamed(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "named")
	named := f.snapshot(t, "a.qdoc", KindNamed, "Keep")
	for i := range MaxAutoVersions + 5 {
		f.now = f.now.Add(AutoSnapshotInterval)
		f.write(t, "a.qdoc", strings.Repeat("x", i+1))
		f.snapshot(t, "a.qdoc", KindAuto, "")
	}
	versions := f.list(t, "a.qdoc")
	autos := 0
	for _, v := range versions {
		if v.Kind == KindAuto {
			autos++
		}
	}
	if autos != MaxAutoVersions || indexOf(versions, named.Version.ID) < 0 {
		t.Fatalf("kept %d autos and named=%v, want %d and true", autos, indexOf(versions, named.Version.ID) >= 0, MaxAutoVersions)
	}
	entries, err := os.ReadDir(filepath.Join(f.filesDir, storageutil.VersionsDirName, "a.qdoc"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != len(versions)+1 {
		t.Errorf("store holds %d files, want %d snapshots and the index", len(entries), len(versions))
	}

	// Past MaxAutoAge every auto goes but the newest; the named one stays.
	f.now = f.now.Add(MaxAutoAge + time.Hour)
	if _, err := f.store.Prune(PruneParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc"}); err != nil {
		t.Fatal(err)
	}
	if versions := f.list(t, "a.qdoc"); len(versions) != 2 {
		t.Errorf("after MaxAutoAge %d versions remain, want the newest and the named", len(versions))
	}
}

func TestPrune_ByteBudgetDropsOldestAutosOnly(t *testing.T) {
	now := time.Date(2026, 10, 5, 0, 0, 0, 0, time.UTC)
	half := MaxStoreBytes / 2
	versions := []Version{
		{ID: "newest", Kind: KindAuto, Size: half, CreatedAt: now},
		{ID: "named", Kind: KindNamed, Size: half, CreatedAt: now},
		{ID: "pinned", Kind: KindAuto, Size: half, CreatedAt: now},
		{ID: "old", Kind: KindAuto, Size: half, CreatedAt: now},
	}
	kept, removed := prune(versions, now, "pinned")
	if len(removed) != 1 || removed[0].ID != "old" {
		t.Fatalf("removed = %+v, want only the oldest unpinned auto", removed)
	}
	if len(kept) != 3 {
		t.Errorf("kept = %+v", kept)
	}
}

func TestSnapshot_NamedThatCannotFitIsRefused(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "one")
	// A hand-built index claiming the named versions already fill the store.
	f.write(t, storageutil.VersionsDirName+"/a.qdoc/index.json",
		`{"versions":[{"id":"20261001T000000Z-00000000","kind":"named","label":"big","size":268435456,"sha256":"x"}]}`)
	_, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc", Kind: KindNamed, Label: "more"})
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
}

func TestDelete_RemovesNamedVersionsOnly(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "one")
	auto := f.snapshot(t, "a.qdoc", KindAuto, "")
	f.write(t, "a.qdoc", "two")
	named := f.snapshot(t, "a.qdoc", KindNamed, "Two")

	del := func(id string) error {
		_, err := f.store.Delete(DeleteParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc", ID: id})
		return err
	}
	if err := del(auto.Version.ID); !errors.Is(err, ErrNotNamed) {
		t.Fatalf("delete auto: err = %v, want ErrNotNamed", err)
	}
	if err := del(named.Version.ID); err != nil {
		t.Fatal(err)
	}
	if err := del(named.Version.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("delete again: err = %v, want ErrNotFound", err)
	}
	if versions := f.list(t, "a.qdoc"); len(versions) != 1 || versions[0].ID != auto.Version.ID {
		t.Fatalf("versions = %+v, want the auto one", versions)
	}
	if f.exists(storageutil.VersionsDirName + "/a.qdoc/" + named.Version.ID + snapExt) {
		t.Error("the deleted version's snapshot is still on disk")
	}
}

func TestHostileIDsAndPathsAreRefused(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "one")
	f.write(t, "secret.txt", "secret")
	f.snapshot(t, "a.qdoc", KindNamed, "One")

	for _, id := range []string{
		"", "..", "../../secret.txt", "20261005T101530Z-3f9a0c1d/../../x", "20261005T101530Z-3F9A0C1D",
		"%2e%2e", "index", "20261005T101530Z-3f9a0c1d.snap",
	} {
		if _, err := f.store.Open(OpenParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc", ID: id}); !errors.Is(err, ErrInvalidID) {
			t.Errorf("Open id %q: err = %v, want ErrInvalidID", id, err)
		}
		if _, err := f.store.Restore(RestoreParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc", ID: id}); !errors.Is(err, ErrInvalidID) {
			t.Errorf("Restore id %q: err = %v, want ErrInvalidID", id, err)
		}
	}
	for _, p := range []string{
		"", "/", ".", "..", ".trash/a.qdoc", storageutil.VersionsDirName + "/a.qdoc/index.json",
		"docs/" + storageutil.VersionsDirName + "/x", ".vfs-write-123",
	} {
		if _, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: p, Kind: KindAuto}); !errors.Is(err, ErrInvalidPath) {
			t.Errorf("Snapshot path %q: err = %v, want ErrInvalidPath", p, err)
		}
	}
	// A path climbing out is clamped to the files root, never outside it.
	if _, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: "../../a.qdoc", Kind: KindAuto}); err != nil {
		t.Errorf("Snapshot ../../a.qdoc: %v, want it read as a.qdoc", err)
	}
	for _, label := range []string{strings.Repeat("x", MaxLabelLength+1), "bad\nlabel", "   "} {
		if _, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc", Kind: KindNamed, Label: label}); !errors.Is(err, ErrInvalidLabel) {
			t.Errorf("label %q: err = %v, want ErrInvalidLabel", label, err)
		}
	}
	if _, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: "a.qdoc", Kind: "weird"}); !errors.Is(err, ErrInvalidKind) {
		t.Errorf("kind weird: err = %v, want ErrInvalidKind", err)
	}
}

func TestIndex_HostileEntriesAreDroppedAndCorruptionRebuilds(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "one")
	good := f.snapshot(t, "a.qdoc", KindNamed, "One")
	store := storageutil.VersionsDirName + "/a.qdoc/"

	f.write(t, store+"index.json", `{"versions":[{"id":"../../secret","kind":"named"},`+
		`{"id":"`+good.Version.ID+`","kind":"named","label":"One"}]}`)
	if versions := f.list(t, "a.qdoc"); len(versions) != 1 || versions[0].ID != good.Version.ID {
		t.Fatalf("versions = %+v, want only the well-formed entry", versions)
	}

	f.write(t, store+"index.json", "{not json")
	versions := f.list(t, "a.qdoc")
	if len(versions) != 1 || versions[0].ID != good.Version.ID || versions[0].Kind != KindAuto {
		t.Fatalf("rebuilt versions = %+v, want the snapshot back as auto", versions)
	}
	if got := f.content(t, "a.qdoc", good.Version.ID); got != "one" {
		t.Errorf("rebuilt content = %q", got)
	}
}

func TestSnapshot_StraySnapshotsAreRemoved(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a.qdoc", "one")
	f.snapshot(t, "a.qdoc", KindNamed, "One")
	stray := storageutil.VersionsDirName + "/a.qdoc/20200101T000000Z-deadbeef" + snapExt
	f.write(t, stray, "left by a crash")

	f.write(t, "a.qdoc", "two")
	f.snapshot(t, "a.qdoc", KindNamed, "Two")
	if f.exists(stray) {
		t.Error("a snapshot the index does not list survived the next commit")
	}
}

func TestSnapshot_RefusesAFolderAndAMissingFile(t *testing.T) {
	f := newFixture(t)
	f.write(t, "dir/x.txt", "x")
	if _, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: "dir", Kind: KindAuto}); !errors.Is(err, ErrNotAFile) {
		t.Errorf("folder: err = %v, want ErrNotAFile", err)
	}
	if _, err := f.store.Snapshot(SnapshotParams{Ctx: f.ctx, FS: f.fs, Path: "nope.qdoc", Kind: KindAuto}); !errors.Is(err, ErrNotFound) {
		t.Errorf("missing: err = %v, want ErrNotFound", err)
	}
}

func TestFollow_MovesTheStoreWithItsFile(t *testing.T) {
	f := newFixture(t)
	f.write(t, "a/deck.qslide", "A")
	v := f.snapshot(t, "a/deck.qslide", KindNamed, "A")
	f.write(t, "b/other.qslide", "old")
	f.snapshot(t, "b/other.qslide", KindNamed, "Old")

	// Not moved while the file is still where it was.
	if res, err := f.store.Follow(FollowParams{Ctx: f.ctx, FS: f.fs, OldPath: "a/deck.qslide", NewPath: "b/other.qslide"}); err != nil || res.Moved {
		t.Fatalf("follow before the move = %+v, %v; want nothing moved", res, err)
	}
	// The file moves over b/other.qslide, replacing it.
	if err := f.fs.Delete(f.ctx, "b/other.qslide", vfs.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := f.fs.Move(f.ctx, "a/deck.qslide", "b/other.qslide"); err != nil {
		t.Fatal(err)
	}
	res, err := f.store.Follow(FollowParams{Ctx: f.ctx, FS: f.fs, OldPath: "a/deck.qslide", NewPath: "b/other.qslide"})
	if err != nil || !res.Moved {
		t.Fatalf("follow = %+v, %v; want moved", res, err)
	}
	versions := f.list(t, "b/other.qslide")
	if len(versions) != 1 || versions[0].ID != v.Version.ID {
		t.Fatalf("versions at the new path = %+v, want the moved file's", versions)
	}
	if f.exists("a/" + storageutil.VersionsDirName) {
		t.Error("an empty version folder was left behind")
	}
}

func TestSweep_RemovesStoresOfFilesGoneForGood(t *testing.T) {
	f := newFixture(t)
	for _, name := range []string{"kept.qdoc", "trashed.qdoc", "gone.qdoc"} {
		f.write(t, "d/"+name, name)
		f.snapshot(t, "d/"+name, KindNamed, "v")
	}
	for _, name := range []string{"trashed.qdoc", "gone.qdoc"} {
		if err := os.Remove(filepath.Join(f.filesDir, "d", name)); err != nil {
			t.Fatal(err)
		}
	}
	res, err := f.store.Sweep(SweepParams{
		Ctx: f.ctx, FS: f.fs, Dir: "d", Restorable: func(p string) bool { return p == "d/trashed.qdoc" },
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Removed) != 1 || res.Removed[0] != "d/gone.qdoc" {
		t.Fatalf("removed = %v, want only d/gone.qdoc", res.Removed)
	}
	if len(f.list(t, "d/kept.qdoc")) != 1 || len(f.list(t, "d/trashed.qdoc")) != 1 {
		t.Error("a store whose file exists or waits in the trash was removed")
	}
}

// Watch subscribes and moves a store when its file moves.
func TestWatch_FollowsAMove(t *testing.T) {
	f := newFixture(t)
	bus := eventbus.New()
	f.store.Watch(WatchParams{Bus: bus, Registry: f.registry})

	f.write(t, "a.qslide", "A")
	f.snapshot(t, "a.qslide", KindNamed, "A")
	if err := f.fs.Move(f.ctx, "a.qslide", "dir/b.qslide"); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventMove, Path: "a.qslide", NewPath: "dir/b.qslide"})
	deadline := time.Now().Add(5 * time.Second)
	for len(f.list(t, "dir/b.qslide")) != 1 {
		if time.Now().After(deadline) {
			t.Fatal("the store did not follow the move")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// The real delete path, in the order DeleteFiles publishes it: trashing keeps
// the history for a restore, and the store goes once the trash is emptied.
// Events are handed over directly so each step can be checked after it.
func TestWatch_KeepsHistoryInTheTrashAndDropsItAfter(t *testing.T) {
	f := newFixture(t)
	params := WatchParams{Registry: f.registry}
	handle := func(evt eventbus.Event) { f.store.handleEvent(params, evt) }

	f.write(t, "dir/b.qslide", "B")
	f.write(t, "dir/kept.qslide", "K")
	f.snapshot(t, "dir/b.qslide", KindNamed, "B")
	f.snapshot(t, "dir/kept.qslide", KindNamed, "K")

	if _, err := f.fs.(vfs.Trasher).Trash(f.ctx, []string{"dir/b.qslide"}, vfs.TrashOptions{}); err != nil {
		t.Fatal(err)
	}
	handle(eventbus.Event{Kind: eventbus.EventTrashChanged})
	handle(eventbus.Event{Kind: eventbus.EventDelete, Path: "dir/b.qslide"})
	handle(eventbus.Event{Kind: eventbus.EventTrashChanged})
	if len(f.list(t, "dir/b.qslide")) != 1 {
		t.Fatal("trashing the file removed its history")
	}

	if _, err := trashutil.Empty(trashutil.EmptyParams{Device: trashutil.Device{Registry: f.registry}}); err != nil {
		t.Fatal(err)
	}
	handle(eventbus.Event{Kind: eventbus.EventTrashChanged})
	if len(f.list(t, "dir/b.qslide")) != 0 {
		t.Error("the store outlived its file leaving the trash")
	}
	if len(f.list(t, "dir/kept.qslide")) != 1 {
		t.Error("a sweep removed the history of a file that still exists")
	}
}

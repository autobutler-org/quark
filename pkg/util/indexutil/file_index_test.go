package indexutil

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func TestBuildPopulatesIndex(t *testing.T) {
	internal := newMount(t, "")
	makeFile(t, internal.filesDir, "notes.txt")
	makeFile(t, makeDir(t, internal.filesDir, "docs"), "report.pdf")
	// Neither an old hidden trash, not yet moved out, the trash beside the
	// files directory, nor version history is searchable.
	makeFile(t, makeDir(t, internal.filesDir, ".trash"), "20240101T000000Z_abcd_old.txt")
	makeFile(t, makeDir(t, storageutil.TrashRoot(internal.filesDir), "x"), "trashed.txt")
	makeFile(t, makeDir(t, internal.filesDir, storageutil.VersionsDirName), "v1.txt")

	idx := NewFileIndex()
	idx.Build(context.Background(), newDevices(t, internal).registry)

	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, []string{"docs/report.pdf", "notes.txt"}) {
		t.Fatalf("index holds %v, want [docs/report.pdf notes.txt]", got)
	}
}

// An unreadable folder is skipped, not fatal: the rest of the device is indexed.
func TestBuildSkipsUnreadableSubtree(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads every folder")
	}
	internal := newMount(t, "")
	makeFile(t, internal.filesDir, "a.txt")
	locked := makeDir(t, internal.filesDir, "locked")
	makeFile(t, locked, "hidden.txt")
	makeFile(t, makeDir(t, internal.filesDir, "z"), "b.txt")
	if err := os.Chmod(locked, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })

	idx := NewFileIndex()
	idx.Build(context.Background(), newDevices(t, internal).registry)

	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, []string{"a.txt", "z/b.txt"}) {
		t.Errorf("index holds %v, want [a.txt z/b.txt]", got)
	}
}

// Any namespace walks the same, an in-memory one included.
func TestBuildFromMemVFS(t *testing.T) {
	ctx := context.Background()
	mem := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for _, p := range []string{"b.txt", "a/c.txt", "a/.trash/old.txt"} {
		if err := mem.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, mem); err != nil {
		t.Fatal(err)
	}
	idx := NewFileIndex()
	idx.Build(ctx, registry)
	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, []string{"a/c.txt", "b.txt"}) {
		t.Errorf("index holds %v, want [a/c.txt b.txt]", got)
	}
}

func TestSearchByQuery(t *testing.T) {
	internal := newMount(t, "")
	makeFile(t, internal.filesDir, "hello.txt")
	makeFile(t, internal.filesDir, "world.md")
	makeFile(t, internal.filesDir, "hello_world.go")

	idx := NewFileIndex()
	idx.Build(context.Background(), newDevices(t, internal).registry)

	if results := idx.Search("hello", nil); len(results) != 2 {
		t.Fatalf("expected 2 results for 'hello', got %d: %v", len(results), results)
	}
	if results := idx.Search("WORLD", nil); len(results) != 2 {
		t.Fatalf("expected 2 results for 'WORLD' (case-insensitive), got %d", len(results))
	}
	if results := idx.Search("", nil); len(results) != 3 {
		t.Fatalf("expected 3 results for empty query, got %d", len(results))
	}
}

func TestSearchBySerial(t *testing.T) {
	internal, usb := newMount(t, ""), newMount(t, "USB1")
	makeFile(t, internal.filesDir, "file_a.txt")
	makeFile(t, usb.filesDir, "file_b.txt")

	idx := NewFileIndex()
	idx.Build(context.Background(), newDevices(t, internal, usb).registry)

	all := idx.Search("", nil)
	if len(all) != 2 {
		t.Fatalf("expected 2 files across 2 devices, got %d", len(all))
	}
	results := idx.Search("", map[string]bool{"USB1": true})
	if len(results) != 1 || results[0].RelPath != "file_b.txt" || results[0].DeviceSerial != "USB1" {
		t.Fatalf("USB1 results = %+v, want file_b.txt on USB1", results)
	}
	results = idx.Search("", map[string]bool{"": true})
	if len(results) != 1 || results[0].RelPath != "file_a.txt" || results[0].DeviceSerial != "" {
		t.Fatalf("internal results = %+v, want file_a.txt on the internal drive", results)
	}
	if results := idx.Search("", map[string]bool{"NONEXISTENT": true}); len(results) != 0 {
		t.Fatalf("expected 0 results for non-existent serial, got %d", len(results))
	}
}

func TestHandleAdd(t *testing.T) {
	idx := NewFileIndex()
	idx.HandleAdd("", "newfile.txt")

	results := idx.Search("newfile", nil)
	if len(results) != 1 {
		t.Fatalf("expected 1 result after HandleAdd, got %d", len(results))
	}
	if results[0].Name != "newfile.txt" || results[0].RelPath != "newfile.txt" {
		t.Errorf("result = %+v, want newfile.txt", results[0])
	}
}

func TestHandleDelete(t *testing.T) {
	idx := NewFileIndex()
	idx.HandleAdd("", "todelete.txt")
	idx.HandleDelete("", "todelete.txt")

	if results := idx.Search("todelete", nil); len(results) != 0 {
		t.Fatalf("expected 0 results after HandleDelete, got %d", len(results))
	}
}

func TestHandleMove(t *testing.T) {
	idx := NewFileIndex()
	idx.HandleAdd("ABC", "old_name.txt")

	idx.HandleMove(context.Background(), vfs.NewMemVFS("files:ABC"), "ABC", "old_name.txt", "new_name.txt")

	if results := idx.Search("old_name", nil); len(results) != 0 {
		t.Fatalf("expected 0 results for old name after move, got %d", len(results))
	}
	results := idx.Search("new_name", nil)
	if len(results) != 1 || results[0].Name != "new_name.txt" || results[0].DeviceSerial != "ABC" {
		t.Fatalf("results = %+v, want new_name.txt on ABC", results)
	}
}

func TestConcurrentAccess(t *testing.T) {
	idx := NewFileIndex()
	done := make(chan struct{})

	go func() {
		for range 100 {
			idx.HandleAdd("", "concurrent.txt")
		}
		close(done)
	}()

	for range 100 {
		_ = idx.Search("concurrent", nil)
	}
	<-done
}

// buildTree indexes a fresh internal drive holding the given files.
func buildTree(t *testing.T, rels ...string) *FileIndex {
	t.Helper()
	internal := newMount(t, "")
	for _, rel := range rels {
		full := filepath.Join(internal.filesDir, filepath.FromSlash(rel))
		makeFile(t, makeDir(t, filepath.Dir(full), ""), filepath.Base(full))
	}
	idx := NewFileIndex()
	idx.Build(context.Background(), newDevices(t, internal).registry)
	return idx
}

// A folder delete publishes one event for the folder; everything under it
// leaves the index, and a sibling sharing the name as a prefix stays (#2754).
func TestHandleDeleteFolderDropsDescendants(t *testing.T) {
	idx := buildTree(t, "a/b.txt", "a/c/d.txt", "ab.txt")

	idx.HandleDelete("", "a")

	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, []string{"ab.txt"}) {
		t.Errorf("after deleting a: %v, want [ab.txt]", got)
	}
}

// A folder move publishes one event for the folder; its contents move with it
// (#2754).
func TestHandleMoveFolderRewritesDescendants(t *testing.T) {
	idx := buildTree(t, "a/b.txt", "a/c/d.txt", "ab.txt")

	idx.HandleMove(context.Background(), vfs.NewMemVFS("files"), "", "a", "x/c")

	want := []string{"ab.txt", "x/c/b.txt", "x/c/c/d.txt"}
	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, want) {
		t.Errorf("after moving a to x/c: %v, want %v", got, want)
	}
}

// Search visits each folder's files in name order, then its folders in name
// order, and devices in serial order, the internal drive first.
func TestFileIndexSearchOrder(t *testing.T) {
	idx := NewFileIndex()
	for _, rel := range []string{"b/z.txt", "c.txt", "a/y.txt", "B.txt", "a/x.txt"} {
		idx.HandleAdd("S", rel)
		idx.HandleAdd("", rel)
	}
	var got []string
	for _, f := range idx.Search("", nil) {
		got = append(got, f.DeviceSerial+":"+f.RelPath)
	}
	want := []string{
		":B.txt", ":c.txt", ":a/x.txt", ":a/y.txt", ":b/z.txt",
		"S:B.txt", "S:c.txt", "S:a/x.txt", "S:a/y.txt", "S:b/z.txt",
	}
	if !slices.Equal(got, want) {
		t.Errorf("order: %v, want %v", got, want)
	}
}

// The events the file tree publishes name a folder as often as a file: an
// upload names the folder it landed in, a new or restored folder names
// itself, and a delete or move into the trash names whatever was selected.
// The watcher keeps the index matching the disk through all of them (#2754).
func TestBuildAndWatchFollowsFolderEvents(t *testing.T) {
	internal := newMount(t, "")
	root := internal.filesDir
	makeFile(t, makeDir(t, root, "a/c"), "d.txt")
	makeFile(t, filepath.Join(root, "a"), "b.txt")
	bus := eventbus.New()
	idx := NewFileIndex()
	idx.BuildAndWatch(BuildAndWatchParams{Bus: bus, Registry: newDevices(t, internal).registry})

	expect := func(step string, want ...string) {
		t.Helper()
		slices.Sort(want)
		waitFor(t, func() bool { return slices.Equal(relPaths(idx.Search("", nil)), want) },
			step+": want "+strings.Join(want, ", "))
	}

	// Into the trash: fileutil.DeleteFiles publishes delete for the folder.
	trashed := filepath.Join(t.TempDir(), "a")
	if err := os.Rename(filepath.Join(root, "a"), trashed); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventDelete, Path: "a"})
	expect("trash a")

	// Back out: RestoreTrash publishes new_folder for a restored folder.
	if err := os.Rename(trashed, filepath.Join(root, "a")); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: "a"})
	expect("restore a", "a/b.txt", "a/c/d.txt")

	// An upload publishes the folder the files landed in, not the files.
	makeFile(t, filepath.Join(root, "a"), "new.txt")
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "a"})
	expect("upload into a", "a/b.txt", "a/c/d.txt", "a/new.txt")

	// A move publishes the folder's old and new paths.
	if err := os.Rename(filepath.Join(root, "a"), filepath.Join(root, "z")); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventMove, Path: "a", NewPath: "z"})
	expect("move a to z", "z/b.txt", "z/c/d.txt", "z/new.txt")

	// An empty new folder adds nothing, and is never indexed as a file.
	makeDir(t, root, "empty")
	bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: "empty"})
	if err := os.RemoveAll(filepath.Join(root, "z", "c")); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventDelete, Path: "z/c"})
	expect("delete z/c", "z/b.txt", "z/new.txt")

	// An upload at the root reads the root again.
	makeFile(t, root, "top.txt")
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: ""})
	expect("upload at the root", "top.txt", "z/b.txt", "z/new.txt")

	// A subscriber that fell too far behind gets one resync in place of what
	// it missed, and rebuilds from the disk (#2753).
	makeFile(t, filepath.Join(root, "empty"), "missed.txt")
	bus.Publish(eventbus.Event{Kind: eventbus.EventResync, Data: eventbus.Resync{Dropped: 1}})
	expect("resync", "empty/missed.txt", "top.txt", "z/b.txt", "z/new.txt")
}

// An event names its device by serial and lands on that device's namespace
// only. One for a device with no namespace used to fall back to the internal
// drive; now it is dropped.
func TestBuildAndWatchRoutesEventsBySerial(t *testing.T) {
	internal, usb := newMount(t, ""), newMount(t, "USB1")
	bus := eventbus.New()
	idx := NewFileIndex()
	idx.BuildAndWatch(BuildAndWatchParams{Bus: bus, Registry: newDevices(t, internal, usb).registry})

	makeFile(t, usb.filesDir, "on-usb.txt")
	makeFile(t, internal.filesDir, "on-usb.txt")
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "on-usb.txt", DeviceSerial: "GONE"})
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "on-usb.txt", DeviceSerial: "USB1"})

	waitFor(t, func() bool { return len(idx.Search("", nil)) > 0 }, "the upload to be indexed")
	got := idx.Search("", nil)
	if len(got) != 1 || got[0].DeviceSerial != "USB1" {
		t.Errorf("index holds %+v, want on-usb.txt on USB1 only", got)
	}
}

// A device plugged in after startup is indexed once its namespace is
// registered, and dropped when it is unplugged.
func TestBuildAndWatchFollowsDevices(t *testing.T) {
	internal, usb := newMount(t, ""), newMount(t, "USB1")
	makeFile(t, internal.filesDir, "inside.txt")
	makeFile(t, makeDir(t, usb.filesDir, "trip"), "photo.jpg")
	devs := newDevices(t, internal)
	idx := NewFileIndex()
	idx.BuildAndWatch(BuildAndWatchParams{Bus: eventbus.New(), Registry: devs.registry, Storage: devs.svc})

	serials := func() []string {
		var out []string
		for _, f := range idx.Search("", nil) {
			out = append(out, f.DeviceSerial+":"+f.RelPath)
		}
		return out
	}
	if got := serials(); !slices.Equal(got, []string{":inside.txt"}) {
		t.Fatalf("before the plug: %v", got)
	}

	devs.detector.set(internal, usb)
	devs.svc.InvalidateDeviceCache()
	waitFor(t, func() bool { return slices.Equal(serials(), []string{":inside.txt", "USB1:trip/photo.jpg"}) },
		"the plugged-in device to be indexed")

	devs.detector.set(internal)
	devs.svc.InvalidateDeviceCache()
	waitFor(t, func() bool { return slices.Equal(serials(), []string{":inside.txt"}) },
		"the unplugged device to be dropped")
}

package storageutil

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// makeDir creates a directory and returns the path.
func makeDir(t *testing.T, parent, name string) string {
	t.Helper()
	path := filepath.Join(parent, name)
	if err := os.MkdirAll(path, 0755); err != nil {
		t.Fatalf("makeDir: %v", err)
	}
	return path
}

// makeFile creates a file with empty contents and returns its path.
func makeFile(t *testing.T, dir, name string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(""), 0644); err != nil {
		t.Fatalf("makeFile: %v", err)
	}
	return path
}

func TestBuildPopulatesIndex(t *testing.T) {
	root := t.TempDir()
	subDir := makeDir(t, root, "docs")
	makeFile(t, root, "notes.txt")
	makeFile(t, subDir, "report.pdf")
	// Files in an old hidden trash, not yet moved out, are not searchable.
	makeFile(t, makeDir(t, root, trashPathPrefix), "20240101T000000Z_abcd_old.txt")

	dev := ManagedDevice{
		Device:   Device{},
		FilesDir: root,
	}

	idx := NewFileIndex()
	idx.Build([]ManagedDevice{dev})

	results := idx.Search("", nil)
	if len(results) != 2 {
		t.Fatalf("expected 2 files, got %d", len(results))
	}
}

func TestSearchByQuery(t *testing.T) {
	root := t.TempDir()
	makeFile(t, root, "hello.txt")
	makeFile(t, root, "world.md")
	makeFile(t, root, "hello_world.go")

	dev := ManagedDevice{FilesDir: root}
	idx := NewFileIndex()
	idx.Build([]ManagedDevice{dev})

	results := idx.Search("hello", nil)
	if len(results) != 2 {
		t.Fatalf("expected 2 results for 'hello', got %d: %v", len(results), results)
	}

	results = idx.Search("WORLD", nil)
	if len(results) != 2 {
		t.Fatalf("expected 2 results for 'WORLD' (case-insensitive), got %d", len(results))
	}

	results = idx.Search("", nil)
	if len(results) != 3 {
		t.Fatalf("expected 3 results for empty query, got %d", len(results))
	}
}

func TestSearchBySerial(t *testing.T) {
	rootA := t.TempDir()
	rootB := t.TempDir()
	makeFile(t, rootA, "file_a.txt")
	makeFile(t, rootB, "file_b.txt")

	devA := ManagedDevice{FilesDir: rootA}
	devB := ManagedDevice{FilesDir: rootB}

	idx := NewFileIndex()
	idx.Build([]ManagedDevice{devA, devB})

	// both devices have empty serial (internal), filter by empty serial
	results := idx.Search("", map[string]bool{"": true})
	if len(results) != 2 {
		t.Fatalf("expected 2 results filtering by empty serial, got %d", len(results))
	}

	// filter by a non-existent serial
	results = idx.Search("", map[string]bool{"NONEXISTENT": true})
	if len(results) != 0 {
		t.Fatalf("expected 0 results for non-existent serial, got %d", len(results))
	}
}

func TestHandleAdd(t *testing.T) {
	idx := NewFileIndex()
	idx.HandleAdd("/files", "newfile.txt", "")

	results := idx.Search("newfile", nil)
	if len(results) != 1 {
		t.Fatalf("expected 1 result after HandleAdd, got %d", len(results))
	}
	if results[0].Name != "newfile.txt" {
		t.Errorf("expected name 'newfile.txt', got '%s'", results[0].Name)
	}
	if results[0].RelPath != "newfile.txt" {
		t.Errorf("expected relPath 'newfile.txt', got '%s'", results[0].RelPath)
	}
}

func TestHandleDelete(t *testing.T) {
	idx := NewFileIndex()
	idx.HandleAdd("/files", "todelete.txt", "")

	results := idx.Search("todelete", nil)
	if len(results) != 1 {
		t.Fatalf("expected 1 result before delete, got %d", len(results))
	}

	idx.HandleDelete("/files", "todelete.txt")

	results = idx.Search("todelete", nil)
	if len(results) != 0 {
		t.Fatalf("expected 0 results after HandleDelete, got %d", len(results))
	}
}

func TestHandleMove(t *testing.T) {
	idx := NewFileIndex()
	idx.HandleAdd("/files", "old_name.txt", "ABC")

	idx.HandleMove("/files", "old_name.txt", "new_name.txt", "ABC")

	results := idx.Search("old_name", nil)
	if len(results) != 0 {
		t.Fatalf("expected 0 results for old name after move, got %d", len(results))
	}

	results = idx.Search("new_name", nil)
	if len(results) != 1 {
		t.Fatalf("expected 1 result for new name after move, got %d", len(results))
	}
	if results[0].Name != "new_name.txt" {
		t.Errorf("expected name 'new_name.txt', got '%s'", results[0].Name)
	}
	if results[0].DeviceSerial != "ABC" {
		t.Errorf("expected serial 'ABC', got '%s'", results[0].DeviceSerial)
	}
}

func TestBuildMultipleDevices(t *testing.T) {
	rootA := t.TempDir()
	rootB := t.TempDir()
	makeFile(t, rootA, "alpha.txt")
	makeFile(t, rootB, "beta.txt")

	devA := ManagedDevice{FilesDir: rootA}
	devB := ManagedDevice{FilesDir: rootB}

	idx := NewFileIndex()
	idx.Build([]ManagedDevice{devA, devB})

	all := idx.Search("", nil)
	if len(all) != 2 {
		t.Fatalf("expected 2 files across 2 devices, got %d", len(all))
	}
}

func TestConcurrentAccess(t *testing.T) {
	idx := NewFileIndex()
	done := make(chan struct{})

	go func() {
		for i := 0; i < 100; i++ {
			idx.HandleAdd("/files", "concurrent.txt", "")
		}
		close(done)
	}()

	for i := 0; i < 100; i++ {
		_ = idx.Search("concurrent", nil)
	}
	<-done
}

// relPaths is the sorted relative paths of a search result.
func relPaths(files []IndexedFile) []string {
	out := make([]string, len(files))
	for i, f := range files {
		out[i] = f.RelPath
	}
	slices.Sort(out)
	return out
}

// buildTree indexes a fresh directory holding the given files.
func buildTree(t *testing.T, rels ...string) (*FileIndex, string) {
	t.Helper()
	root := t.TempDir()
	for _, rel := range rels {
		full := filepath.Join(root, filepath.FromSlash(rel))
		makeFile(t, makeDir(t, filepath.Dir(full), ""), filepath.Base(full))
	}
	idx := NewFileIndex()
	idx.Build([]ManagedDevice{{FilesDir: root}})
	return idx, root
}

// A folder delete publishes one event for the folder; everything under it
// leaves the index, and a sibling sharing the name as a prefix stays (#2754).
func TestHandleDeleteFolderDropsDescendants(t *testing.T) {
	idx, root := buildTree(t, "a/b.txt", "a/c/d.txt", "ab.txt")

	idx.HandleDelete(root, "a")

	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, []string{"ab.txt"}) {
		t.Errorf("after deleting a: %v, want [ab.txt]", got)
	}
}

// A folder move publishes one event for the folder; its contents move with it
// (#2754).
func TestHandleMoveFolderRewritesDescendants(t *testing.T) {
	idx, root := buildTree(t, "a/b.txt", "a/c/d.txt", "ab.txt")

	idx.HandleMove(root, "a", "x/c", "")

	want := []string{"ab.txt", "x/c/b.txt", "x/c/c/d.txt"}
	if got := relPaths(idx.Search("", nil)); !slices.Equal(got, want) {
		t.Errorf("after moving a to x/c: %v, want %v", got, want)
	}
}

// The events the file tree publishes name a folder as often as a file: an
// upload names the folder it landed in, a new or restored folder names
// itself, and a delete or move into the trash names whatever was selected.
// The watcher keeps the index matching the disk through all of them (#2754).
func TestBuildAndWatchFollowsFolderEvents(t *testing.T) {
	root := t.TempDir()
	makeFile(t, makeDir(t, root, "a/c"), "d.txt")
	makeFile(t, filepath.Join(root, "a"), "b.txt")
	bus := eventbus.New()
	idx := NewFileIndex()
	idx.BuildAndWatch(bus, func() ([]ManagedDevice, error) {
		return []ManagedDevice{{FilesDir: root}}, nil
	})

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

	// A subscriber that fell too far behind gets one resync in place of what
	// it missed, and rebuilds from the disk (#2753).
	makeFile(t, filepath.Join(root, "empty"), "missed.txt")
	bus.Publish(eventbus.Event{Kind: eventbus.EventResync, Data: eventbus.Resync{Dropped: 1}})
	expect("resync", "empty/missed.txt", "z/b.txt", "z/new.txt")
}

// waitFor polls until cond holds, failing after a few seconds.
func waitFor(t *testing.T, cond func() bool, what string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

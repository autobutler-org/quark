package storageutil

import (
	"os"
	"path/filepath"
	"testing"
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
	// Trashed files are not searchable.
	makeFile(t, makeDir(t, root, TrashDir), "20240101T000000Z_abcd_old.txt")

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

package vfs

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHostMove_RenamesIntoANewFolder(t *testing.T) {
	filesDir := t.TempDir()
	seedTree(t, filesDir, "source.txt")

	if err := hostMove(filesDir, "source.txt", "new/path/dest.txt"); err != nil {
		t.Fatalf("hostMove: %v", err)
	}
	if _, err := os.Stat(filepath.Join(filesDir, "source.txt")); !os.IsNotExist(err) {
		t.Error("want the source gone")
	}
	if _, err := os.Stat(filepath.Join(filesDir, "new", "path", "dest.txt")); err != nil {
		t.Errorf("want the destination: %v", err)
	}
}

func TestHostMove_MissingSourceFails(t *testing.T) {
	if err := hostMove(t.TempDir(), "nonexistent/old.txt", "new/file.txt"); err == nil {
		t.Error("want an error for a missing source")
	}
}

func TestHostMove_RefusesAnEscape(t *testing.T) {
	filesDir := t.TempDir()
	seedTree(t, filesDir, "a.txt")
	if err := hostMove(filesDir, "a.txt", "../out.txt"); err == nil {
		t.Error("want an error for a destination outside the files directory")
	}
	if err := hostMove(filesDir, "../a.txt", "b.txt"); err == nil {
		t.Error("want an error for a source outside the files directory")
	}
}

func TestHostMkdirAll_CreatesTheFolderAndParents(t *testing.T) {
	filesDir := t.TempDir()
	if err := hostMkdirAll(filesDir, "a/b/new-folder/"); err != nil {
		t.Fatalf("hostMkdirAll: %v", err)
	}
	if info, err := os.Stat(filepath.Join(filesDir, "a", "b", "new-folder")); err != nil || !info.IsDir() {
		t.Errorf("want the folder: %v", err)
	}
	if err := hostMkdirAll(filesDir, "../escape"); err == nil {
		t.Error("want an error for a folder outside the files directory")
	}
}

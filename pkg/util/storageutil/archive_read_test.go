package storageutil

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestReadArchiveEntryImpl_PathEscapingFilesDir(t *testing.T) {
	device := makeListDevice(t)
	data := buildZipForList(t, []struct{ name, content string }{{"file.txt", "x"}})
	writeArchive(t, filepath.Dir(device.FilesDir), "outside.zip", data)

	_, _, err := ReadArchiveEntryImpl(ReadArchiveEntryParams{ArchivePath: "../outside.zip", EntryPath: "file.txt"}, device, "")
	if err == nil || !strings.Contains(err.Error(), "file not found") {
		t.Fatalf("expected 'file not found' for an archive outside the files directory, got %v", err)
	}
}

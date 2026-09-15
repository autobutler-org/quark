package storageutil

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func buildZipForList(t *testing.T, entries []struct{ name, content string }) []byte {
	t.Helper()
	var buf bytes.Buffer
	w := zip.NewWriter(&buf)
	for _, e := range entries {
		f, err := w.Create(e.name)
		if err != nil {
			t.Fatalf("create %q: %v", e.name, err)
		}
		if _, err := f.Write([]byte(e.content)); err != nil {
			t.Fatalf("write %q: %v", e.name, err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func buildTarGzForList(t *testing.T, entries []struct{ name, content string }) []byte {
	t.Helper()
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gw)
	for _, e := range entries {
		hdr := &tar.Header{
			Name:     e.name,
			Typeflag: tar.TypeReg,
			Size:     int64(len(e.content)),
			Mode:     0644,
		}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatalf("header %q: %v", e.name, err)
		}
		if _, err := tw.Write([]byte(e.content)); err != nil {
			t.Fatalf("write %q: %v", e.name, err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func makeListDevice(t *testing.T) *ManagedDevice {
	t.Helper()
	dir := t.TempDir()
	filesRoot := filepath.Join(dir, "files")
	if err := os.MkdirAll(filesRoot, 0755); err != nil {
		t.Fatal(err)
	}
	return &ManagedDevice{
		Device:   Device{Name: "test", MountPoint: dir, IsInternal: true},
		DataDir:  dir,
		FilesDir: filesRoot,
	}
}

func writeArchive(t *testing.T, dir, name string, data []byte) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), data, 0644); err != nil {
		t.Fatal(err)
	}
}

// --- tests ---

func TestListArchiveEntriesImpl_ZipRoot(t *testing.T) {
	device := makeListDevice(t)
	data := buildZipForList(t, []struct{ name, content string }{
		{"readme.txt", "hello"},
		{"photos/img001.jpg", "jpg1"},
		{"photos/img002.jpg", "jpg2"},
		{"docs/report.pdf", "pdf"},
	})
	writeArchive(t, device.FilesDir, "archive.zip", data)

	entries, err := ListArchiveEntriesImpl(ListArchiveParams{FilePath: "archive.zip"}, device, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Expect: docs/ (dir), photos/ (dir), readme.txt (file) — dirs first, then alpha
	names := make([]string, len(entries))
	for i, e := range entries {
		names[i] = e.Name
		if e.IsDir && !e.IsDir {
			t.Errorf("entry %q: IsDir mismatch", e.Name)
		}
	}

	if len(entries) != 3 {
		t.Fatalf("expected 3 entries, got %d: %v", len(entries), names)
	}
	if !entries[0].IsDir || entries[0].Name != "docs" {
		t.Errorf("entries[0] = {%q, dir=%v}; want {docs, true}", entries[0].Name, entries[0].IsDir)
	}
	if !entries[1].IsDir || entries[1].Name != "photos" {
		t.Errorf("entries[1] = {%q, dir=%v}; want {photos, true}", entries[1].Name, entries[1].IsDir)
	}
	if entries[2].IsDir || entries[2].Name != "readme.txt" {
		t.Errorf("entries[2] = {%q, dir=%v}; want {readme.txt, false}", entries[2].Name, entries[2].IsDir)
	}
}

func TestListArchiveEntriesImpl_ZipSubPath(t *testing.T) {
	device := makeListDevice(t)
	data := buildZipForList(t, []struct{ name, content string }{
		{"photos/vacation/img001.jpg", "jpg1"},
		{"photos/vacation/img002.jpg", "jpg2"},
		{"photos/portrait.jpg", "jpg3"},
	})
	writeArchive(t, device.FilesDir, "archive.zip", data)

	entries, err := ListArchiveEntriesImpl(ListArchiveParams{
		FilePath: "archive.zip",
		SubPath:  "photos",
	}, device, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Expect: vacation/ (dir), portrait.jpg (file)
	if len(entries) != 2 {
		names := make([]string, len(entries))
		for i, e := range entries {
			names[i] = e.Name
		}
		t.Fatalf("expected 2 entries, got %d: %v", len(entries), names)
	}
	if !entries[0].IsDir || entries[0].Name != "vacation" {
		t.Errorf("entries[0] = {%q, dir=%v}; want {vacation, true}", entries[0].Name, entries[0].IsDir)
	}
	if entries[1].IsDir || entries[1].Name != "portrait.jpg" {
		t.Errorf("entries[1] = {%q, dir=%v}; want {portrait.jpg, false}", entries[1].Name, entries[1].IsDir)
	}
}

func TestListArchiveEntriesImpl_TarGz(t *testing.T) {
	device := makeListDevice(t)
	data := buildTarGzForList(t, []struct{ name, content string }{
		{"file.txt", "hello"},
		{"subdir/nested.txt", "world"},
	})
	writeArchive(t, device.FilesDir, "archive.tar.gz", data)

	entries, err := ListArchiveEntriesImpl(ListArchiveParams{FilePath: "archive.tar.gz"}, device, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if !entries[0].IsDir || entries[0].Name != "subdir" {
		t.Errorf("entries[0] = {%q, dir=%v}; want {subdir, true}", entries[0].Name, entries[0].IsDir)
	}
	if entries[1].IsDir || entries[1].Name != "file.txt" {
		t.Errorf("entries[1] = {%q, dir=%v}; want {file.txt, false}", entries[1].Name, entries[1].IsDir)
	}
}

func TestListArchiveEntriesImpl_FileNotFound(t *testing.T) {
	device := makeListDevice(t)
	_, err := ListArchiveEntriesImpl(ListArchiveParams{FilePath: "nope.zip"}, device, "")
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestListArchiveEntriesImpl_PathEscapingFilesDir(t *testing.T) {
	device := makeListDevice(t)
	data := buildZipForList(t, []struct{ name, content string }{{"file.txt", "x"}})
	writeArchive(t, filepath.Dir(device.FilesDir), "outside.zip", data)

	_, err := ListArchiveEntriesImpl(ListArchiveParams{FilePath: "../outside.zip"}, device, "")
	if err == nil || !strings.Contains(err.Error(), "file not found") {
		t.Fatalf("expected 'file not found' for an archive outside the files directory, got %v", err)
	}
}

func TestListArchiveEntriesImpl_NotAnArchive(t *testing.T) {
	device := makeListDevice(t)
	if err := os.WriteFile(filepath.Join(device.FilesDir, "doc.pdf"), []byte("%PDF"), 0644); err != nil {
		t.Fatal(err)
	}
	_, err := ListArchiveEntriesImpl(ListArchiveParams{FilePath: "doc.pdf"}, device, "")
	if err == nil {
		t.Fatal("expected error for non-archive")
	}
}

func TestListArchiveEntriesImpl_InvalidSubPath(t *testing.T) {
	device := makeListDevice(t)
	data := buildZipForList(t, []struct{ name, content string }{{"file.txt", "x"}})
	writeArchive(t, device.FilesDir, "archive.zip", data)

	_, err := ListArchiveEntriesImpl(ListArchiveParams{
		FilePath: "archive.zip",
		SubPath:  "../escape",
	}, device, "")
	if err == nil {
		t.Fatal("expected error for traversal subPath")
	}
}

func TestListArchiveEntriesImpl_ZipCompressedSize(t *testing.T) {
	device := makeListDevice(t)

	// Build a zip with deflate compression so compressed != uncompressed.
	var buf bytes.Buffer
	w := zip.NewWriter(&buf)
	content := bytes.Repeat([]byte("abcdefghij"), 100) // 1000 bytes, highly compressible
	fw, err := w.CreateHeader(&zip.FileHeader{
		Name:   "compressible.txt",
		Method: zip.Deflate,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(content); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	writeArchive(t, device.FilesDir, "compressed.zip", buf.Bytes())

	entries, err := ListArchiveEntriesImpl(ListArchiveParams{FilePath: "compressed.zip"}, device, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	e := entries[0]
	if e.Size != 1000 {
		t.Errorf("expected uncompressed size 1000, got %d", e.Size)
	}
	if e.CompressedSize <= 0 {
		t.Errorf("expected positive compressed size, got %d", e.CompressedSize)
	}
	if e.CompressedSize >= e.Size {
		t.Errorf("expected compressed size (%d) < uncompressed size (%d)", e.CompressedSize, e.Size)
	}
}

func TestNormalizeSubPath(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{"", ""},
		{"/", ""},
		{"photos/", "photos"},
		{"/photos/vacation/", "photos/vacation"},
		{".", ""},
		{"photos/./vacation", "photos/vacation"},
	}
	for _, c := range cases {
		got := normalizeSubPath(c.input)
		if got != c.want {
			t.Errorf("normalizeSubPath(%q) = %q; want %q", c.input, got, c.want)
		}
	}
}

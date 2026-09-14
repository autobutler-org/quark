package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"hash/crc32"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestExtractZipVFSStreamsFromASeekableSource is the regression for #1705: the
// archive used to be buffered whole via io.ReadAll, so a 4 GiB zip asked for
// ~12 GiB of heap and the request died as a bare 500. A namespace whose Open
// hands back an *os.File is now read in place, so extraction has to keep
// working through a LocalVFS and the entries have to land intact.
func TestExtractZipVFSStreamsFromASeekableSource(t *testing.T) {
	root := t.TempDir()
	entries := map[string]string{
		"top.txt":           "top",
		"nested/inner.txt":  "inner",
		"nested/deep/x.txt": "x",
	}
	if err := os.WriteFile(filepath.Join(root, "bundle.zip"), []byte(zipWith(t, entries)), 0o600); err != nil {
		t.Fatalf("failed to seed the archive: %v", err)
	}

	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS failed: %v", err)
	}

	extracted, err := fileutil.ExtractZipVFS(context.Background(), fsys, "bundle.zip")
	if err != nil {
		t.Fatalf("ExtractZipVFS failed: %v", err)
	}
	if extracted.DestDir != "bundle" || !extracted.Created {
		t.Errorf("ExtractZipVFS = %+v, want a newly created bundle folder", extracted)
	}

	for name, want := range entries {
		got, err := os.ReadFile(filepath.Join(root, "bundle", filepath.FromSlash(name)))
		if err != nil {
			t.Fatalf("entry %q was not extracted: %v", name, err)
		}
		if string(got) != want {
			t.Errorf("entry %q: got %q, want %q", name, got, want)
		}
	}
}

// TestOpenArchiveEntryVFSOutlivesTheCall guards the other half of the streaming
// change: the entry reader now reads out of the archive file rather than a
// buffer, so the archive has to stay open until the entry is closed.
func TestOpenArchiveEntryVFSOutlivesTheCall(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "bundle.zip"), []byte(zipWith(t, map[string]string{
		"nested/inner.txt": "inner",
	})), 0o600); err != nil {
		t.Fatalf("failed to seed the archive: %v", err)
	}
	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS failed: %v", err)
	}

	opened, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
		Ctx:         context.Background(),
		Registry:    registryWith(t, fsys),
		ArchivePath: "bundle.zip",
		EntryPath:   "nested/inner.txt",
	})
	if err != nil {
		t.Fatalf("OpenArchiveEntry failed: %v", err)
	}
	defer opened.Reader.Close()

	got, err := io.ReadAll(opened.Reader)
	if err != nil {
		t.Fatalf("reading the entry after the call returned failed: %v", err)
	}
	if string(got) != "inner" {
		t.Errorf("entry content: got %q, want %q", got, "inner")
	}
}

// TestExtractZipVFSRejectsUnsupportedCompression covers what the 4 GiB archive
// in #1705 actually was: 1189 entries in Deflate64 (method 9), which Go's
// archive/zip cannot decompress. That used to surface as
// "zip: unsupported compression algorithm" behind a 500; it is now a 400 that
// names the method and the way out.
func TestExtractZipVFSRejectsUnsupportedCompression(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "bundle.zip", zipWithMethod(t, "audio.mp3", "payload", 9))

	_, err := fileutil.ExtractZipVFS(context.Background(), fsys, "bundle.zip")
	if err == nil {
		t.Fatal("extracting a Deflate64 archive should fail")
	}
	var unsupported *fileutil.UnsupportedError
	if !errors.As(err, &unsupported) {
		t.Fatalf("error should be an UnsupportedError so the handler answers 400, got %T: %v", err, err)
	}
	if !strings.Contains(err.Error(), "Deflate64") || !strings.Contains(err.Error(), "audio.mp3") {
		t.Errorf("error should name the method and the entry, got: %v", err)
	}
}

// zipWithMethod builds a one-entry archive declaring an arbitrary compression
// method. The bytes are stored raw, which is enough: nothing here gets far
// enough to decompress them.
func zipWithMethod(t *testing.T, name, content string, method uint16) string {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.CreateRaw(&zip.FileHeader{
		Name:               name,
		Method:             method,
		CRC32:              crc32.ChecksumIEEE([]byte(content)),
		CompressedSize64:   uint64(len(content)),
		UncompressedSize64: uint64(len(content)),
	})
	if err != nil {
		t.Fatalf("failed to create the raw zip entry: %v", err)
	}
	if _, err := w.Write([]byte(content)); err != nil {
		t.Fatalf("failed to write the raw zip entry: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("failed to close the zip: %v", err)
	}
	return buf.String()
}

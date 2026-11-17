package zipselectionutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/zipselectionutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// filesRegistry is an internal drive served from a temp directory, the
// namespace FilesVFS picks for an empty serial.
func filesRegistry(t *testing.T) (vfs.Registry, string) {
	t.Helper()
	dir := t.TempDir()
	local, err := vfs.NewLocalVFS(dir, "files")
	if err != nil {
		t.Fatal(err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, local); err != nil {
		t.Fatal(err)
	}
	return registry, dir
}

func systemAccess(t *testing.T) accessutil.Access {
	t.Helper()
	loaded, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access
}

func write(t *testing.T, dir, rel string, content []byte) {
	t.Helper()
	full := filepath.Join(dir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, content, 0o600); err != nil {
		t.Fatal(err)
	}
}

func paths(rels ...string) []zipselectionutil.Path {
	out := make([]zipselectionutil.Path, 0, len(rels))
	for _, rel := range rels {
		out = append(out, zipselectionutil.Path{FilePath: rel})
	}
	return out
}

// entries reads an archive back as name -> contents, in archive order.
func entries(t *testing.T, archive []byte) ([]string, map[string]string) {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		t.Fatalf("not a zip: %v", err)
	}
	var names []string
	contents := map[string]string{}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			t.Fatal(err)
		}
		names = append(names, f.Name)
		contents[f.Name] = string(body)
	}
	return names, contents
}

func TestValidateBoundsTheSelection(t *testing.T) {
	if err := zipselectionutil.Validate(nil); !errors.Is(err, zipselectionutil.ErrNoPaths) {
		t.Errorf("empty selection = %v, want ErrNoPaths", err)
	}
	if err := zipselectionutil.Validate(make([]zipselectionutil.Path, zipselectionutil.MaxPaths)); err != nil {
		t.Errorf("%d paths = %v, want nil", zipselectionutil.MaxPaths, err)
	}
	if err := zipselectionutil.Validate(make([]zipselectionutil.Path, zipselectionutil.MaxPaths+1)); !errors.Is(err, zipselectionutil.ErrTooManyPaths) {
		t.Errorf("%d paths = %v, want ErrTooManyPaths", zipselectionutil.MaxPaths+1, err)
	}
}

// The key a token is bound to names the selection and nothing else: the same
// paths give the same key, any change gives another.
func TestSelectionKeyNamesTheSelection(t *testing.T) {
	a := zipselectionutil.SelectionKey(paths("a.jpg", "b.jpg"))
	if a != zipselectionutil.SelectionKey(paths("a.jpg", "b.jpg")) {
		t.Error("the same selection gave two keys")
	}
	if a == zipselectionutil.SelectionKey(paths("a.jpg", "c.jpg")) {
		t.Error("two selections gave one key")
	}
	if !strings.HasPrefix(a, "selection:") {
		t.Errorf("key %q does not read as a selection", a)
	}
}

// Files from several folders land side by side; a name taken twice, in any
// case, gets a numbered suffix; the same path selected twice is zipped once.
func TestZipSelectionNumbersCollisions(t *testing.T) {
	registry, dir := filesRegistry(t)
	write(t, dir, "a/IMG.jpg", []byte("a"))
	write(t, dir, "b/IMG.jpg", []byte("b"))
	write(t, dir, "c/img.jpg", []byte("c"))
	write(t, dir, "c/notes", []byte("n"))
	write(t, dir, "d/notes", []byte("m"))

	var buf bytes.Buffer
	result, err := zipselectionutil.ZipSelection(zipselectionutil.ZipSelectionParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t),
		Paths:  paths("a/IMG.jpg", "b/IMG.jpg", "c/img.jpg", "a/IMG.jpg", "c/notes", "d/notes"),
		Writer: &buf,
	})
	if err != nil {
		t.Fatal(err)
	}
	names, contents := entries(t, buf.Bytes())
	want := []string{"IMG.jpg", "IMG (1).jpg", "img (2).jpg", "notes", "notes (1)"}
	if !slices.Equal(names, want) {
		t.Fatalf("entries = %v, want %v", names, want)
	}
	if contents["IMG (1).jpg"] != "b" || contents["img (2).jpg"] != "c" || contents["notes (1)"] != "m" {
		t.Errorf("renamed entries hold the wrong files: %v", contents)
	}
	if result.Entries != 5 || len(result.Skipped) != 0 {
		t.Errorf("result = %+v, want 5 entries and nothing skipped", result)
	}
}

// What cannot be read, does not exist, is a folder, or is on a device that is
// not attached is left out and named in skipped.txt, the archive's last entry.
func TestZipSelectionListsWhatItSkipped(t *testing.T) {
	registry, dir := filesRegistry(t)
	write(t, dir, "a.jpg", []byte("a"))
	write(t, dir, "folder/x.jpg", []byte("x"))
	// A selected file of the same name moves the list aside rather than
	// being overwritten by it.
	write(t, dir, "skipped.txt", []byte("mine"))

	var buf bytes.Buffer
	result, err := zipselectionutil.ZipSelection(zipselectionutil.ZipSelectionParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t),
		Paths: []zipselectionutil.Path{
			{FilePath: "a.jpg"},
			{FilePath: "missing.jpg"},
			{FilePath: "folder"},
			{FilePath: "skipped.txt"},
			{Serial: "GONE", FilePath: "b.jpg"},
		},
		Writer: &buf,
	})
	if err != nil {
		t.Fatal(err)
	}
	names, contents := entries(t, buf.Bytes())
	if want := []string{"a.jpg", "skipped.txt", "skipped (1).txt"}; !slices.Equal(names, want) {
		t.Fatalf("entries = %v, want %v", names, want)
	}
	if contents["skipped.txt"] != "mine" {
		t.Errorf("the selected skipped.txt was replaced: %q", contents["skipped.txt"])
	}
	list := contents["skipped (1).txt"]
	for _, name := range []string{"missing.jpg", "folder", "GONE: b.jpg"} {
		if !strings.Contains(list, name) {
			t.Errorf("skipped list does not name %s:\n%s", name, list)
		}
	}
	if len(result.Skipped) != 3 {
		t.Errorf("Skipped = %v, want 3", result.Skipped)
	}
}

// heapSampler is a client that records the live heap as the archive arrives.
type heapSampler struct {
	writes, n int64
	peak      uint64
}

func (s *heapSampler) Write(p []byte) (int, error) {
	s.writes++
	s.n += int64(len(p))
	if s.writes%16 == 0 {
		var m runtime.MemStats
		runtime.ReadMemStats(&m)
		s.peak = max(s.peak, m.HeapAlloc)
	}
	return len(p), nil
}

// Several large files stream through: the heap grows by a few MiB however big
// the archive is, so no file and no part of the archive is held whole.
func TestZipSelectionStreamsLargeFiles(t *testing.T) {
	const files, size = 4, 24 << 20
	registry, dir := filesRegistry(t)
	chunk := make([]byte, 1<<20)
	var selection []zipselectionutil.Path
	for i := range files {
		// Half photos, stored, and half other files, deflated, so both
		// compression paths are measured.
		name := fmt.Sprintf("folder%d/big%d.bin", i, i)
		if i%2 == 0 {
			name = fmt.Sprintf("folder%d/big%d.jpg", i, i)
		}
		full := filepath.Join(dir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		f, err := os.Create(full)
		if err != nil {
			t.Fatal(err)
		}
		for range size / len(chunk) {
			_, _ = rand.Read(chunk)
			if _, err := f.Write(chunk); err != nil {
				t.Fatal(err)
			}
		}
		if err := f.Close(); err != nil {
			t.Fatal(err)
		}
		selection = append(selection, zipselectionutil.Path{FilePath: name})
	}
	access := systemAccess(t)

	defer debug.SetGCPercent(debug.SetGCPercent(10))
	runtime.GC()
	var before runtime.MemStats
	runtime.ReadMemStats(&before)

	s := &heapSampler{}
	if _, err := zipselectionutil.ZipSelection(zipselectionutil.ZipSelectionParams{
		Ctx: context.Background(), Registry: registry, Access: access, Paths: selection, Writer: s,
	}); err != nil {
		t.Fatal(err)
	}
	if s.n < files*size {
		t.Fatalf("archive is %d bytes, want at least %d", s.n, files*size)
	}
	const bound = 16 << 20
	if grew := int64(s.peak) - int64(before.HeapAlloc); grew > bound {
		t.Errorf("heap grew %d bytes zipping a %d-byte archive, want under %d", grew, s.n, bound)
	}
}

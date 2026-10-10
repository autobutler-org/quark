package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// --- ZipMethod ---

// Formats that are already compressed are stored, as are files too small for
// deflate to pay off; everything else is deflated (#2757).
func TestZipMethod(t *testing.T) {
	const big = 64 << 10
	stored := []string{
		"a.jpg", "a.JPEG", "a.png", "a.webp", "a.heic", "a.gif",
		"a.mp4", "a.mov", "a.mkv", "a.webm",
		"a.mp3", "a.aac", "a.m4a", "a.flac", "a.ogg",
		"a.zip", "a.gz", "a.7z", "a.rar", "a.xz", "a.bz2",
		"a.pdf", "a.docx", "a.xlsx", "a.pptx", "a.odt",
	}
	for _, name := range stored {
		if got := fileutil.ZipMethod(name, "", big); got != zip.Store {
			t.Errorf("ZipMethod(%q) = %d, want Store", name, got)
		}
	}
	for _, name := range []string{"a.txt", "a.csv", "a.qsheet", "a.bmp", "a.svg", "README"} {
		if got := fileutil.ZipMethod(name, "", big); got != zip.Deflate {
			t.Errorf("ZipMethod(%q) = %d, want Deflate", name, got)
		}
	}
	// The MIME type catches a compressed file whose name does not say so.
	for _, mime := range []string{"image/jpeg", "video/mp4", "audio/mpeg", "application/zip"} {
		if got := fileutil.ZipMethod("upload", mime, big); got != zip.Store {
			t.Errorf("ZipMethod(mime %q) = %d, want Store", mime, got)
		}
	}
	if got := fileutil.ZipMethod("a.txt", "text/plain", 10); got != zip.Store {
		t.Errorf("ZipMethod(tiny text) = %d, want Store", got)
	}
}

// Both folder zips pick each entry's method by ZipMethod, and the archive
// still reads back byte for byte.
func TestZipDirsStoreCompressedEntries(t *testing.T) {
	text := strings.Repeat("compressible text ", 4096)
	jpeg := strings.Repeat("\xff\xd8 not really a jpeg ", 4096)
	want := map[string]uint16{
		"My Folder/notes.txt":  zip.Deflate,
		"My Folder/photo.jpg":  zip.Store,
		"My Folder/sub/v.mp4":  zip.Store,
		"My Folder/sub/ok.txt": zip.Store, // tiny
	}
	contents := map[string]string{"notes.txt": text, "photo.jpg": jpeg, "sub/v.mp4": jpeg, "sub/ok.txt": "ok"}

	dir, device := deviceFolder(t)
	fsys := vfs.NewMemVFS("files")
	for name, content := range contents {
		if err := os.MkdirAll(filepath.Join(dir, filepath.Dir(name)), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		writeMem(t, fsys, "folder/"+name, content)
	}
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}

	for label, write := range map[string]func(io.Writer) error{
		"ZipVFSDir on a device": func(w io.Writer) error {
			return fileutil.ZipVFSDir(context.Background(), device, "", "My Folder", system.Access, w)
		},
		"ZipVFSDir": func(w io.Writer) error {
			return fileutil.ZipVFSDir(context.Background(), fsys, "folder", "My Folder", system.Access, w)
		},
	} {
		var buf bytes.Buffer
		if err := write(&buf); err != nil {
			t.Fatalf("%s: %v", label, err)
		}
		zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
		if err != nil {
			t.Fatalf("%s: unreadable zip: %v", label, err)
		}
		seen := 0
		for _, f := range zr.File {
			method, ok := want[f.Name]
			if !ok {
				continue
			}
			seen++
			if f.Method != method {
				t.Errorf("%s: %s method = %d, want %d", label, f.Name, f.Method, method)
			}
			rc, err := f.Open()
			if err != nil {
				t.Fatalf("%s: open %s: %v", label, f.Name, err)
			}
			got, err := io.ReadAll(rc)
			rc.Close()
			if err != nil {
				t.Fatalf("%s: read %s: %v", label, f.Name, err)
			}
			if string(got) != contents[strings.TrimPrefix(f.Name, "My Folder/")] {
				t.Errorf("%s: %s content differs", label, f.Name)
			}
		}
		if seen != len(want) {
			t.Errorf("%s: found %d of %d entries", label, seen, len(want))
		}
	}
}

// --- streaming ---

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

// deviceFolder is the files directory of a USB device and the namespace
// serving it, the way a folder download on a device reads it.
func deviceFolder(tb testing.TB) (string, vfs.VFS) {
	tb.Helper()
	mountPoint := tb.TempDir()
	dir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		tb.Fatal(err)
	}
	svc := storageutil.NewStorageService(&oneUSBDetector{mountPoint: mountPoint, serial: "USB-ZIP"})
	return dir, vfs.NewDeviceStorageServiceVFS(svc, "USB-ZIP")
}

// zipAll zips everything on a device as the system principal.
func zipAll(tb testing.TB, fsys vfs.VFS, w io.Writer, root string) error {
	tb.Helper()
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		tb.Fatal(err)
	}
	return fileutil.ZipVFSDir(context.Background(), fsys, "", root, system.Access, w)
}

// makeSmallFiles writes n files of size bytes each, half photos and half text,
// onto a device.
func makeSmallFiles(tb testing.TB, n, size int) vfs.VFS {
	tb.Helper()
	dir, fsys := deviceFolder(tb)
	body := []byte(strings.Repeat("x", size))
	for i := range n {
		ext := ".txt"
		if i%2 == 0 {
			ext = ".jpg"
		}
		if err := os.WriteFile(filepath.Join(dir, fmt.Sprintf("f%05d%s", i, ext)), body, 0o600); err != nil {
			tb.Fatal(err)
		}
	}
	return fsys
}

// A 5,000-file folder streams: the heap stays a small fraction of the
// archive, so nothing accumulates the archive or its entries' contents.
func TestZipVFSDirStreamsManySmallFiles(t *testing.T) {
	const files, size = 5000, 16 << 10
	fsys := makeSmallFiles(t, files, size)

	// Collect often, so the sampled heap is close to what is live rather than
	// garbage from the walk waiting for the next cycle.
	defer debug.SetGCPercent(debug.SetGCPercent(10))
	runtime.GC()
	var before runtime.MemStats
	runtime.ReadMemStats(&before)

	s := &heapSampler{}
	if err := zipAll(t, fsys, s, "many"); err != nil {
		t.Fatal(err)
	}
	if s.n < files*size/2 {
		t.Fatalf("archive is %d bytes, want at least %d", s.n, files*size/2)
	}
	// The zip writer keeps one central-directory record per entry (~200 B),
	// about 1 MiB for 5,000 entries, and it measures ~5 MiB in all. A quarter
	// of the archive leaves room for that and is still half of what holding
	// even its stored entries would cost.
	bound := s.n / 4
	if grew := int64(s.peak) - int64(before.HeapAlloc); grew > bound {
		t.Errorf("heap grew %d bytes zipping a %d-byte archive, want under %d", grew, s.n, bound)
	}
}

func BenchmarkZipVFSDir5000SmallFiles(b *testing.B) {
	fsys := makeSmallFiles(b, 5000, 4<<10)
	b.ReportAllocs()
	for b.Loop() {
		if err := zipAll(b, fsys, io.Discard, "many"); err != nil {
			b.Fatal(err)
		}
	}
}

// --- zip64 ---

// tailRecorder keeps an archive's first and last bytes and counts the rest,
// which is all zip.NewReader needs to read the central directory.
type tailRecorder struct {
	head, tail []byte
	n          int64
}

const tailKeep = 1 << 20

func (r *tailRecorder) Write(p []byte) (int, error) {
	if room := tailKeep - len(r.head); room > 0 {
		r.head = append(r.head, p[:min(room, len(p))]...)
	}
	// Trim only once the tail doubles, so the copy is amortized.
	r.tail = append(r.tail, p...)
	if over := len(r.tail) - tailKeep; over > tailKeep {
		r.tail = append(r.tail[:0], r.tail[over:]...)
	}
	r.n += int64(len(p))
	return len(p), nil
}

// ReadAt serves the kept bytes and zeros for the middle nobody reads.
func (r *tailRecorder) ReadAt(p []byte, off int64) (int, error) {
	tailStart := r.n - int64(len(r.tail))
	for i := range p {
		at := off + int64(i)
		switch {
		case at >= r.n:
			return i, io.EOF
		case at < int64(len(r.head)):
			p[i] = r.head[at]
		case at >= tailStart:
			p[i] = r.tail[at-tailStart]
		default:
			p[i] = 0
		}
	}
	return len(p), nil
}

// An entry past 4 GiB, stored now that it is a video, still gets the zip64
// records that let a reader find and size it.
func TestZipVFSDirWritesZip64ForAnEntryOver4GiB(t *testing.T) {
	if testing.Short() {
		t.Skip("streams 4 GiB")
	}
	dir, fsys := deviceFolder(t)
	const size = 4<<30 + 1<<20
	if err := os.WriteFile(filepath.Join(dir, "small.txt"), []byte("hello"), 0o600); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(filepath.Join(dir, "huge.mp4"))
	if err != nil {
		t.Fatal(err)
	}
	// Sparse: no disk is spent on the zeros.
	if err := f.Truncate(size); err != nil {
		t.Fatal(err)
	}
	f.Close()

	rec := &tailRecorder{}
	if err := zipAll(t, fsys, rec, "big"); err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(rec, rec.n)
	if err != nil {
		t.Fatalf("unreadable zip: %v", err)
	}
	var found bool
	for _, e := range zr.File {
		if e.Name != "big/huge.mp4" {
			continue
		}
		found = true
		if e.UncompressedSize64 != size || e.CompressedSize64 != size {
			t.Errorf("sizes = %d/%d, want %d", e.CompressedSize64, e.UncompressedSize64, size)
		}
		if e.Method != zip.Store {
			t.Errorf("method = %d, want Store", e.Method)
		}
	}
	if !found {
		t.Error("big/huge.mp4 missing from the central directory")
	}
}

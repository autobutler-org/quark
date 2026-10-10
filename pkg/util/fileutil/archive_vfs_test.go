package fileutil_test

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"hash/crc32"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// archiveSerial names the USB drive the device cases run against.
const archiveSerial = "USB-ARCHIVE"

// archiveTarget is a device an archive test runs against: the internal drive
// or archiveSerial, each a namespace of its own in one registry.
type archiveTarget struct {
	name   string
	serial string
}

var archiveTargets = []archiveTarget{{name: "internal"}, {name: "device", serial: archiveSerial}}

// archiveRegistry registers a MemVFS for the internal drive and one for
// archiveSerial, and returns the registry, the namespace target names and
// the other one.
func archiveRegistry(t *testing.T, target archiveTarget) (vfs.Registry, vfs.VFS, vfs.VFS) {
	t.Helper()
	registry := vfs.NewRegistry()
	internal := vfs.NewMemVFS(vfs.FilesNamespace(""))
	device := vfs.NewMemVFS(vfs.FilesNamespace(archiveSerial))
	for id, fsys := range map[string]vfs.VFS{vfs.FilesNamespace(""): internal, vfs.FilesNamespace(archiveSerial): device} {
		if err := registry.Register(vfs.Namespace{ID: id}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	if target.serial == "" {
		return registry, internal, device
	}
	return registry, device, internal
}

// archiveEntries is what every multi-entry fixture holds.
var archiveEntries = map[string]string{
	"top.txt":          "top",
	"nested/inner.txt": "inner",
}

// archiveFormats builds the same entries in each format Quark extracts.
var archiveFormats = map[string]func(t *testing.T, entries map[string]string) string{
	"bundle.zip":    zipWith,
	"bundle.tar":    func(t *testing.T, e map[string]string) string { return tarWith(t, e) },
	"bundle.tar.gz": func(t *testing.T, e map[string]string) string { return gzipped(t, tarWith(t, e)) },
	"bundle.tgz":    func(t *testing.T, e map[string]string) string { return gzipped(t, tarWith(t, e)) },
	"bundle.7z": func(t *testing.T, _ map[string]string) string {
		// Go has no 7z writer, so the fixture is checked in; it holds
		// archiveEntries.
		data, err := os.ReadFile(filepath.Join("testdata", "archive", "bundle.7z"))
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	},
}

// Every format lists, reads and extracts through the namespace of the device
// the request names, and nothing lands on the other one (#2644).
func TestArchivesListReadAndExtractOnEveryDevice(t *testing.T) {
	ctx := context.Background()
	for _, target := range archiveTargets {
		for name, build := range archiveFormats {
			t.Run(target.name+"/"+name, func(t *testing.T) {
				registry, fsys, other := archiveRegistry(t, target)
				writeMem(t, fsys, "in/"+name, build(t, archiveEntries))

				listed, err := fileutil.ListArchive(fileutil.ListArchiveParams{
					Ctx: ctx, Registry: registry, FilePath: "in/" + name, Serial: target.serial,
				})
				if err != nil {
					t.Fatalf("ListArchive failed: %v", err)
				}
				if got := nodeNames(listed.Entries); !slices.Equal(got, []string{"nested/", "top.txt"}) {
					t.Errorf("root listing = %v, want the folder first, then top.txt", got)
				}
				for _, node := range listed.Entries {
					if node.DeviceSerial != target.serial {
						t.Errorf("%s carries serial %q, want %q", node.Name, node.DeviceSerial, target.serial)
					}
				}
				sub, err := fileutil.ListArchive(fileutil.ListArchiveParams{
					Ctx: ctx, Registry: registry, FilePath: "in/" + name, SubPath: "nested", Serial: target.serial,
				})
				if err != nil {
					t.Fatalf("ListArchive(nested) failed: %v", err)
				}
				if len(sub.Entries) != 1 || sub.Entries[0].FullPath != "in/"+name+"/nested/inner.txt" || sub.Entries[0].Size != 5 {
					t.Errorf("nested listing = %+v, want inner.txt of 5 bytes", sub.Entries)
				}

				if got := readEntry(t, registry, target.serial, "in/"+name, "nested/inner.txt"); got != "inner" {
					t.Errorf("entry read = %q, want %q", got, "inner")
				}

				extracted, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
					Ctx: ctx, Registry: registry, FilePath: "in/" + name, Serial: target.serial,
				})
				if err != nil {
					t.Fatalf("ExtractArchive failed: %v", err)
				}
				if extracted.CreatedPath != "in/bundle" {
					t.Errorf("CreatedPath = %q, want in/bundle", extracted.CreatedPath)
				}
				for entry, want := range archiveEntries {
					if got := readMem(t, fsys, "in/bundle/"+entry); got != want {
						t.Errorf("extracted %s = %q, want %q", entry, got, want)
					}
				}
				if _, err := other.Stat(ctx, "in/bundle"); !errors.Is(err, vfs.ErrNotFound) {
					t.Errorf("the other device got the extraction: %v", err)
				}
				assertNoStaging(t, fsys, "in")
			})
		}
	}
}

// A .gz that holds no tar is one file: it lists as the archive's stem, reads
// as the decompressed stream, and extracts to a file beside the archive.
func TestBareGzipIsOneFile(t *testing.T) {
	ctx := context.Background()
	for _, target := range archiveTargets {
		t.Run(target.name, func(t *testing.T) {
			registry, fsys, _ := archiveRegistry(t, target)
			writeMem(t, fsys, "notes.txt.gz", gzipped(t, "hello"))

			listed, err := fileutil.ListArchive(fileutil.ListArchiveParams{
				Ctx: ctx, Registry: registry, FilePath: "notes.txt.gz", Serial: target.serial,
			})
			if err != nil {
				t.Fatalf("ListArchive failed: %v", err)
			}
			if got := nodeNames(listed.Entries); !slices.Equal(got, []string{"notes.txt"}) {
				t.Errorf("listing = %v, want notes.txt", got)
			}

			opened, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
				Ctx: ctx, Registry: registry, ArchivePath: "notes.txt.gz", EntryPath: "notes.txt", Serial: target.serial,
			})
			if err != nil {
				t.Fatalf("OpenArchiveEntry failed: %v", err)
			}
			defer opened.Reader.Close()
			if opened.Size >= 0 {
				t.Errorf("Size = %d, want negative: a gzip stream does not say", opened.Size)
			}
			if got, _ := io.ReadAll(opened.Reader); string(got) != "hello" {
				t.Errorf("entry read = %q, want hello", got)
			}

			writeMem(t, fsys, "notes.txt", "already here")
			extracted, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
				Ctx: ctx, Registry: registry, FilePath: "notes.txt.gz", Serial: target.serial,
			})
			if err != nil {
				t.Fatalf("ExtractArchive failed: %v", err)
			}
			if extracted.CreatedPath == "notes.txt" {
				t.Fatal("the decompressed file replaced the one already there")
			}
			if got := readMem(t, fsys, extracted.CreatedPath); got != "hello" {
				t.Errorf("%s = %q, want hello", extracted.CreatedPath, got)
			}
			if got := readMem(t, fsys, "notes.txt"); got != "already here" {
				t.Errorf("notes.txt = %q, want it untouched", got)
			}
		})
	}
}

// A serial with no namespace is a drive that is not attached: every entry
// point answers 404 and never falls back to the internal drive.
func TestArchivesOnAnUnattachedDeviceAreNotFound(t *testing.T) {
	ctx := context.Background()
	registry, internal, _ := archiveRegistry(t, archiveTargets[0])
	writeMem(t, internal, "bundle.zip", zipWith(t, archiveEntries))

	_, listErr := fileutil.ListArchive(fileutil.ListArchiveParams{
		Ctx: ctx, Registry: registry, FilePath: "bundle.zip", Serial: "NOPE",
	})
	_, openErr := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
		Ctx: ctx, Registry: registry, ArchivePath: "bundle.zip", EntryPath: "top.txt", Serial: "NOPE",
	})
	_, extractErr := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
		Ctx: ctx, Registry: registry, FilePath: "bundle.zip", Serial: "NOPE",
	})
	for name, err := range map[string]error{"list": listErr, "open": openErr, "extract": extractErr} {
		var notFound *fileutil.NotFoundError
		if !errors.As(err, &notFound) || !errors.Is(err, fileutil.ErrNoDevice) {
			t.Errorf("%s on an unattached device = %v, want a NotFoundError for ErrNoDevice", name, err)
		}
	}
	if _, err := internal.Stat(ctx, "bundle"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("the extraction fell back to the internal drive: %v", err)
	}
}

// What is missing or not an archive gets a typed error, which the handler
// maps to 404 and 400 rather than matching message text.
func TestArchiveErrorsAreTyped(t *testing.T) {
	ctx := context.Background()
	registry, fsys, _ := archiveRegistry(t, archiveTargets[1])
	writeMem(t, fsys, "notes.txt", "plain")
	writeMem(t, fsys, "broken.zip", "not a zip")
	writeMem(t, fsys, "bundle.zip", zipWith(t, archiveEntries))

	cases := []struct {
		name        string
		path, entry string
		notFound    bool
	}{
		{name: "missing archive", path: "missing.zip", entry: "top.txt", notFound: true},
		{name: "missing entry", path: "bundle.zip", entry: "nope.txt", notFound: true},
		{name: "folder entry", path: "bundle.zip", entry: "nested", notFound: true},
		{name: "escaping entry", path: "bundle.zip", entry: "../bundle.zip", notFound: true},
		{name: "not an archive", path: "notes.txt", entry: "x"},
		{name: "corrupt archive", path: "broken.zip", entry: "x"},
	}
	for _, c := range cases {
		_, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
			Ctx: ctx, Registry: registry, ArchivePath: c.path, EntryPath: c.entry, Serial: archiveSerial,
		})
		var notFound *fileutil.NotFoundError
		var unsupported *fileutil.UnsupportedError
		switch {
		case c.notFound && !errors.As(err, &notFound):
			t.Errorf("%s: got %T %v, want a NotFoundError", c.name, err, err)
		case !c.notFound && !errors.As(err, &unsupported):
			t.Errorf("%s: got %T %v, want an UnsupportedError", c.name, err, err)
		}
	}
	for _, p := range []string{"notes.txt", "broken.zip"} {
		_, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
			Ctx: ctx, Registry: registry, FilePath: p, Serial: archiveSerial,
		})
		var unsupported *fileutil.UnsupportedError
		if !errors.As(err, &unsupported) {
			t.Errorf("extracting %s: got %T %v, want an UnsupportedError", p, err, err)
		}
	}
}

// An extraction never merges into what is already there: a taken name is
// numbered, and the folder that had it is left alone. The new folder is
// announced with the serial of the device it is on.
func TestExtractArchiveTakesAFreeNameAndPublishes(t *testing.T) {
	ctx := context.Background()
	registry, fsys, _ := archiveRegistry(t, archiveTargets[1])
	writeMem(t, fsys, "bundle.zip", zipWith(t, archiveEntries))
	writeMem(t, fsys, "bundle/top.txt", "mine")

	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe(t.Name())
	defer unsubscribe()

	extracted, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
		Ctx: ctx, Registry: registry, EventBus: bus, FilePath: "bundle.zip", Serial: archiveSerial,
	})
	if err != nil {
		t.Fatalf("ExtractArchive failed: %v", err)
	}
	want := storageutil.NumberedName("bundle", 1)
	if extracted.CreatedPath != want {
		t.Errorf("CreatedPath = %q, want %q", extracted.CreatedPath, want)
	}
	if got := readMem(t, fsys, "bundle/top.txt"); got != "mine" {
		t.Errorf("bundle/top.txt = %q, want it untouched", got)
	}
	if got := readMem(t, fsys, want+"/top.txt"); got != "top" {
		t.Errorf("%s/top.txt = %q, want top", want, got)
	}
	e := <-events
	if e.Kind != eventbus.EventNewFolder || e.Path != want || e.DeviceSerial != archiveSerial {
		t.Errorf("event = %+v, want a new folder %s on %s", e, want, archiveSerial)
	}
}

// An extraction that fails partway leaves nothing a user would see: not the
// entries already written, not the half-filled folder.
func TestExtractArchiveThatFailsLeavesNothingBehind(t *testing.T) {
	ctx := context.Background()
	setEntryLimit(t, 4)

	cases := map[string]string{
		// The second entry declares more than the limit.
		"bundle.tar": tarWith(t, map[string]string{"a/ok.txt": "abc", "a/z-big.txt": "0123456789"}),
		// A gzip stream declares nothing, so only reading it finds out.
		"notes.gz": gzipped(t, "0123456789"),
	}
	for name, archive := range cases {
		t.Run(name, func(t *testing.T) {
			registry, fsys, _ := archiveRegistry(t, archiveTargets[1])
			writeMem(t, fsys, name, archive)

			bus := eventbus.New()
			events, unsubscribe := bus.Subscribe(t.Name())
			defer unsubscribe()

			_, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
				Ctx: ctx, Registry: registry, EventBus: bus, FilePath: name, Serial: archiveSerial,
			})
			var unsupported *fileutil.UnsupportedError
			if !errors.As(err, &unsupported) {
				t.Fatalf("got %T %v, want an UnsupportedError for the oversized entry", err, err)
			}
			if got := listNames(t, fsys, ""); !slices.Equal(got, []string{name}) {
				t.Errorf("after a failed extraction the folder holds %v, want only %s", got, name)
			}
			select {
			case e := <-events:
				t.Errorf("a failed extraction published %+v", e)
			default:
			}
		})
	}
}

// An entry that climbs out of the archive is skipped, so nothing lands beside
// the extraction folder (Zip Slip), and a link is never written.
func TestExtractArchiveSkipsEscapingEntriesAndLinks(t *testing.T) {
	ctx := context.Background()
	registry, fsys, _ := archiveRegistry(t, archiveTargets[1])

	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	for _, h := range []*tar.Header{
		{Name: "../evil.txt", Typeflag: tar.TypeReg, Size: 4, Mode: 0o644},
		{Name: "ok.txt", Typeflag: tar.TypeReg, Size: 4, Mode: 0o644},
		{Name: "link", Typeflag: tar.TypeSymlink, Linkname: "../../etc/passwd", Mode: 0o777},
	} {
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
		if h.Size > 0 {
			if _, err := tw.Write([]byte("data")); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	writeMem(t, fsys, "in/bundle.tar", buf.String())

	if _, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
		Ctx: ctx, Registry: registry, FilePath: "in/bundle.tar", Serial: archiveSerial,
	}); err != nil {
		t.Fatalf("ExtractArchive failed: %v", err)
	}
	if got := listNames(t, fsys, "in/bundle"); !slices.Equal(got, []string{"ok.txt"}) {
		t.Errorf("extracted %v, want only ok.txt", got)
	}
	if got := listNames(t, fsys, "in"); !slices.Equal(got, []string{"bundle", "bundle.tar"}) {
		t.Errorf("beside the archive: %v, want nothing but the archive and its folder", got)
	}
}

// An archive over the entry limit is refused before it is written out.
func TestExtractArchiveRefusesTooManyEntries(t *testing.T) {
	orig := storageutil.MaxArchiveEntries
	storageutil.MaxArchiveEntries = 2
	t.Cleanup(func() { storageutil.MaxArchiveEntries = orig })

	registry, fsys, _ := archiveRegistry(t, archiveTargets[1])
	writeMem(t, fsys, "many.zip", zipWith(t, map[string]string{"a": "1", "b": "2", "c": "3"}))
	_, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
		Ctx: context.Background(), Registry: registry, FilePath: "many.zip", Serial: archiveSerial,
	})
	if err == nil || !strings.Contains(err.Error(), "exceeds maximum") {
		t.Fatalf("got %v, want the entry limit", err)
	}
	if got := listNames(t, fsys, ""); !slices.Equal(got, []string{"many.zip"}) {
		t.Errorf("after a refused extraction the folder holds %v", got)
	}
}

// TestLargeArchiveEntriesStream is the #1705 guard: an entry of hundreds of
// megabytes reads and extracts in a few megabytes of heap, for a zip read in
// place and a tar.gz streamed, so a 4 GiB archive cannot ask for gigabytes.
// The archives are zeros, which compress to almost nothing, so the test costs
// disk only for the extracted copy.
func TestLargeArchiveEntriesStream(t *testing.T) {
	if testing.Short() {
		t.Skip("writes a large extracted file")
	}
	const entrySize = 256 << 20
	const heapBudget = 32 << 20
	ctx := context.Background()

	for _, name := range []string{"big.zip", "big.tar.gz"} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			writeZeroArchive(t, filepath.Join(root, name), entrySize)
			local, err := vfs.NewLocalVFS(root, vfs.FilesNamespace(archiveSerial))
			if err != nil {
				t.Fatal(err)
			}
			registry := vfs.NewRegistry()
			for _, id := range []string{vfs.FilesNamespace(""), vfs.FilesNamespace(archiveSerial)} {
				if err := registry.Register(vfs.Namespace{ID: id}, local); err != nil {
					t.Fatal(err)
				}
			}

			allocated := allocatedBy(t, func() {
				opened, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
					Ctx: ctx, Registry: registry, ArchivePath: name, EntryPath: "zeros.bin", Serial: archiveSerial,
				})
				if err != nil {
					t.Fatalf("OpenArchiveEntry failed: %v", err)
				}
				defer opened.Reader.Close()
				n, err := io.Copy(io.Discard, opened.Reader)
				if err != nil || n != entrySize {
					t.Fatalf("read %d bytes, %v; want %d", n, err, entrySize)
				}
			})
			if allocated > heapBudget {
				t.Errorf("reading a %d MiB entry allocated %d MiB", entrySize>>20, allocated>>20)
			}

			allocated = allocatedBy(t, func() {
				extracted, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
					Ctx: ctx, Registry: registry, FilePath: name, Serial: archiveSerial,
				})
				if err != nil {
					t.Fatalf("ExtractArchive failed: %v", err)
				}
				info, err := os.Stat(filepath.Join(root, extracted.CreatedPath, "zeros.bin"))
				if err != nil || info.Size() != entrySize {
					t.Fatalf("extracted entry: %v, %v; want %d bytes", info, err, entrySize)
				}
			})
			if allocated > heapBudget {
				t.Errorf("extracting a %d MiB entry allocated %d MiB", entrySize>>20, allocated>>20)
			}
		})
	}
}

// TestOpenArchiveEntryVFSOutlivesTheCall guards the other half of the streaming
// change: the entry reader reads out of the archive file rather than a buffer,
// so the archive has to stay open until the entry is closed.
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
	if got := readEntry(t, registryWith(t, fsys), "", "bundle.zip", "nested/inner.txt"); got != "inner" {
		t.Errorf("entry content: got %q, want %q", got, "inner")
	}
}

// TestExtractArchiveRejectsUnsupportedCompression covers what the 4 GiB
// archive in #1705 actually was: 1189 entries in Deflate64 (method 9), which
// Go's archive/zip cannot decompress. That used to surface as
// "zip: unsupported compression algorithm" behind a 500; it is now a 400 that
// names the method and the way out.
func TestExtractArchiveRejectsUnsupportedCompression(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "bundle.zip", zipWithMethod(t, "audio.mp3", "payload", 9))

	_, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
		Ctx: context.Background(), Registry: registryWith(t, fsys), FilePath: "bundle.zip",
	})
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
	if got := listNames(t, fsys, ""); !slices.Equal(got, []string{"bundle.zip"}) {
		t.Errorf("after a failed extraction the folder holds %v", got)
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

// tarWith builds an uncompressed tar of entries, in name order.
func tarWith(t *testing.T, entries map[string]string) string {
	t.Helper()
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)
	names := make([]string, 0, len(entries))
	for name := range entries {
		names = append(names, name)
	}
	slices.Sort(names)
	for _, name := range names {
		content := entries[name]
		if err := tw.WriteHeader(&tar.Header{Name: name, Typeflag: tar.TypeReg, Size: int64(len(content)), Mode: 0o644}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.String()
}

// gzipped compresses content with gzip.
func gzipped(t *testing.T, content string) string {
	t.Helper()
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	if _, err := gw.Write([]byte(content)); err != nil {
		t.Fatal(err)
	}
	if err := gw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.String()
}

// writeZeroArchive writes an archive at p holding zeros.bin, size zero bytes,
// streaming it so the test itself stays small.
func writeZeroArchive(t *testing.T, p string, size int64) {
	t.Helper()
	f, err := os.Create(p)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	zeros := io.LimitReader(zeroReader{}, size)
	if strings.HasSuffix(p, ".zip") {
		zw := zip.NewWriter(f)
		w, err := zw.CreateHeader(&zip.FileHeader{Name: "zeros.bin", Method: zip.Deflate})
		if err == nil {
			_, err = io.Copy(w, zeros)
		}
		if err == nil {
			err = zw.Close()
		}
		if err != nil {
			t.Fatal(err)
		}
		return
	}
	gw, _ := gzip.NewWriterLevel(f, gzip.BestSpeed)
	tw := tar.NewWriter(gw)
	err = tw.WriteHeader(&tar.Header{Name: "zeros.bin", Typeflag: tar.TypeReg, Size: size, Mode: 0o644})
	if err == nil {
		_, err = io.Copy(tw, zeros)
	}
	if err == nil {
		err = tw.Close()
	}
	if err == nil {
		err = gw.Close()
	}
	if err != nil {
		t.Fatal(err)
	}
}

// zeroReader reads zeros forever.
type zeroReader struct{}

func (zeroReader) Read(p []byte) (int, error) {
	clear(p)
	return len(p), nil
}

// allocatedBy reports how many bytes of heap fn allocated in total.
func allocatedBy(t *testing.T, fn func()) uint64 {
	t.Helper()
	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	fn()
	runtime.ReadMemStats(&after)
	return after.TotalAlloc - before.TotalAlloc
}

// setEntryLimit lowers the per-entry size limit for the test.
func setEntryLimit(t *testing.T, limit int64) {
	t.Helper()
	orig := storageutil.MaxArchiveEntryBytes
	storageutil.MaxArchiveEntryBytes = limit
	t.Cleanup(func() { storageutil.MaxArchiveEntryBytes = orig })
}

// readEntry reads one archive entry whole. The entries are a few bytes.
func readEntry(t *testing.T, registry vfs.Registry, serial, archive, entry string) string {
	t.Helper()
	opened, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
		Ctx: context.Background(), Registry: registry, ArchivePath: archive, EntryPath: entry, Serial: serial,
	})
	if err != nil {
		t.Fatalf("OpenArchiveEntry(%s, %s) failed: %v", archive, entry, err)
	}
	defer opened.Reader.Close()
	got, err := io.ReadAll(opened.Reader)
	if err != nil {
		t.Fatalf("reading %s from %s failed: %v", entry, archive, err)
	}
	return string(got)
}

// readMem reads a small file out of fsys.
func readMem(t *testing.T, fsys vfs.VFS, p string) string {
	t.Helper()
	f, err := fsys.Open(context.Background(), p)
	if err != nil {
		t.Fatalf("open %s: %v", p, err)
	}
	defer f.Close()
	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("read %s: %v", p, err)
	}
	return string(got)
}

// listNames lists dir in fsys, internal names included, sorted.
func listNames(t *testing.T, fsys vfs.VFS, dir string) []string {
	t.Helper()
	infos, err := fsys.List(context.Background(), dir, nil)
	if err != nil {
		t.Fatalf("list %q: %v", dir, err)
	}
	names := make([]string, 0, len(infos))
	for _, info := range infos {
		names = append(names, info.Name)
	}
	slices.Sort(names)
	return names
}

// assertNoStaging fails when an extraction left its hidden folder in dir.
func assertNoStaging(t *testing.T, fsys vfs.VFS, dir string) {
	t.Helper()
	for _, name := range listNames(t, fsys, dir) {
		if strings.HasPrefix(name, storageutil.WriteTempPrefix) {
			t.Errorf("%s/%s was left behind", dir, name)
		}
	}
}

// nodeNames is each node's name, with a slash after a folder's.
func nodeNames(nodes []fileutil.FileNode) []string {
	names := make([]string, 0, len(nodes))
	for _, n := range nodes {
		if n.IsDir {
			names = append(names, n.Name+"/")
			continue
		}
		names = append(names, n.Name)
	}
	return names
}

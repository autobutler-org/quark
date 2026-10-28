package server

import (
	"context"
	"path"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const contentUSB = "USB-CONTENT"

// contentFixture is the content indexer over a fresh database and two
// in-memory devices: the internal drive and contentUSB. Events are applied
// directly, the way the subscriber's loop does.
type contentFixture struct {
	deps     deputil.Dependencies
	database *db.DatabaseSqlc
	registry vfs.Registry
	devices  map[string]vfs.VFS
}

func newContentFixture(t *testing.T) *contentFixture {
	t.Helper()
	database := dbtest.NewDB(t)
	registry := vfs.NewRegistry()
	devices := map[string]vfs.VFS{}
	for _, serial := range []string{"", contentUSB} {
		ns := vfs.FilesNamespace(serial)
		devices[serial] = vfs.NewMemVFS(ns)
		if err := registry.Register(vfs.Namespace{ID: ns}, devices[serial]); err != nil {
			t.Fatal(err)
		}
	}
	deps := deputil.NewDependencies().WithDatabase(database).WithVFSRegistry(registry)
	return &contentFixture{deps: deps, database: database, registry: registry, devices: devices}
}

func (f *contentFixture) write(t *testing.T, serial, p string, data string) {
	t.Helper()
	ctx := context.Background()
	fsys := f.devices[serial]
	if dir := path.Dir(p); dir != "." {
		if err := fsys.MkdirAll(ctx, dir); err != nil {
			t.Fatal(err)
		}
	}
	if err := fsys.Write(ctx, p, strings.NewReader(data), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
}

func (f *contentFixture) handle(evt eventbus.Event) {
	handleContentEvent(f.deps, f.database.Db, f.registry, evt)
}

// countOpens wraps each device so later reads are counted. Writes already made
// through the fixture stay visible, since the wrapper is the same filesystem.
func (f *contentFixture) countOpens(t *testing.T) map[string]*countingVFS {
	t.Helper()
	out := map[string]*countingVFS{}
	for serial, fsys := range f.devices {
		wrapped := &countingVFS{VFS: fsys}
		ns := vfs.FilesNamespace(serial)
		f.registry.Unregister(ns)
		if err := f.registry.Register(vfs.Namespace{ID: ns}, wrapped); err != nil {
			t.Fatal(err)
		}
		out[serial] = wrapped
	}
	return out
}

// hits is every content-search match for query, as "serial:relPath", in order.
func (f *contentFixture) hits(t *testing.T, query string) []string {
	t.Helper()
	found, err := searchutil.Search(context.Background(), f.database.Db, query, 50)
	if err != nil {
		t.Fatalf("search %q: %v", query, err)
	}
	out := make([]string, 0, len(found))
	for _, hit := range found {
		out = append(out, hit.Serial+":"+hit.RelPath)
	}
	slices.Sort(out)
	return out
}

func (f *contentFixture) wantHits(t *testing.T, query string, want ...string) {
	t.Helper()
	got := f.hits(t, query)
	slices.Sort(want)
	if !slices.Equal(got, want) {
		t.Fatalf("hits for %q = %v, want %v", query, got, want)
	}
}

// TestContentIndexerFolderEventIndexesTheFilesUnderIt is the upload and
// new_folder case: both name the folder, not the files. Text under that
// folder becomes searchable, including a path with a leading slash, and
// nothing else is read — a photo in the folder, a document outside it, or
// the same path on another device.
func TestContentIndexerFolderEventIndexesTheFilesUnderIt(t *testing.T) {
	for _, tc := range []struct {
		kind eventbus.EventKind
		path string
	}{
		{kind: eventbus.EventUpload, path: "/Notes"},
		{kind: eventbus.EventNewFolder, path: "Notes"},
	} {
		t.Run(string(tc.kind), func(t *testing.T) {
			f := newContentFixture(t)
			f.write(t, "", "Notes/notes.txt", "alpha document")
			f.write(t, "", "Notes/nested/deep.md", "bravo nested")
			f.write(t, "", "Notes/photo.jpg", "alpha should not be indexed")
			f.write(t, "", "Elsewhere/other.txt", "charlie outside")
			f.write(t, contentUSB, "Notes/notes.txt", "charlie other device")
			opens := f.countOpens(t)

			f.handle(eventbus.Event{Kind: tc.kind, Path: tc.path})

			f.wantHits(t, "alpha", ":Notes/notes.txt")
			f.wantHits(t, "bravo", ":Notes/nested/deep.md")
			f.wantHits(t, "charlie")
			got := append([]string(nil), opens[""].opened...)
			slices.Sort(got)
			want := []string{"Notes/nested/deep.md", "Notes/notes.txt"}
			if !slices.Equal(got, want) {
				t.Fatalf("opened = %v, want %v", got, want)
			}
			if len(opens[contentUSB].opened) != 0 {
				t.Fatalf("other device opened %v", opens[contentUSB].opened)
			}

			// A later upload of the same folder re-reads a file that changed.
			if tc.kind != eventbus.EventUpload {
				return
			}
			f.write(t, "", "Notes/notes.txt", "delta replacement")
			f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: tc.path})
			f.wantHits(t, "alpha")
			f.wantHits(t, "delta", ":Notes/notes.txt")
		})
	}
}

// TestContentIndexerFileUploadIndexesOnlyThatFile covers publishers that name
// the file itself, such as a transcode or a restored file. The sibling next
// to it is not read.
func TestContentIndexerFileUploadIndexesOnlyThatFile(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "docs/a.txt", "alpha alone")
	f.write(t, "", "docs/b.txt", "bravo sibling")
	opens := f.countOpens(t)

	f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "docs/a.txt"})

	f.wantHits(t, "alpha", ":docs/a.txt")
	f.wantHits(t, "bravo")
	if got := opens[""].opened; len(got) != 1 || got[0] != "docs/a.txt" {
		t.Fatalf("opened = %v, want docs/a.txt", got)
	}
}

// TestContentIndexerRootUploadIndexesTheTree treats an empty path as the
// device root, which an upload into the top directory names. The other
// device is unread, and the trash is not indexed.
func TestContentIndexerRootUploadIndexesTheTree(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "top.txt", "alpha at the root")
	f.write(t, "", "dir/nested.txt", "bravo below")
	f.write(t, "", ".trash/n/secret.txt", "delta trashed")
	f.write(t, contentUSB, "top.txt", "charlie elsewhere")
	opens := f.countOpens(t)

	f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: ""})

	f.wantHits(t, "alpha", ":top.txt")
	f.wantHits(t, "bravo", ":dir/nested.txt")
	f.wantHits(t, "charlie")
	f.wantHits(t, "delta")
	if len(opens[contentUSB].opened) != 0 {
		t.Fatalf("other device opened %v", opens[contentUSB].opened)
	}
}

// TestContentIndexerMoveAndDeleteFollowAFile renames a document and then
// removes it. The index follows the file's own path.
func TestContentIndexerMoveAndDeleteFollowAFile(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "docs/notes.txt", "alpha draft")
	f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "/docs/notes.txt"})
	f.wantHits(t, "alpha", ":docs/notes.txt")

	if err := f.devices[""].Move(context.Background(), "docs/notes.txt", "docs/renamed.txt"); err != nil {
		t.Fatal(err)
	}
	f.handle(eventbus.Event{Kind: eventbus.EventMove, Path: "/docs/notes.txt", NewPath: "/docs/renamed.txt"})
	f.wantHits(t, "alpha", ":docs/renamed.txt")

	f.handle(eventbus.Event{Kind: eventbus.EventDelete, Path: "/docs/renamed.txt"})
	f.wantHits(t, "alpha")
}

// TestContentIndexerSkipsWhatItCannotRead drops an event for a serial with
// no files namespace, and never indexes the trash. A missing folder and an
// empty new folder add no rows.
func TestContentIndexerSkipsWhatItCannotRead(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "Notes/notes.txt", "alpha kept unread")
	f.write(t, "", ".trash/n/notes.txt", "bravo trashed")

	f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "Notes", DeviceSerial: "gone"})
	f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: ".trash/n"})
	f.handle(eventbus.Event{Kind: eventbus.EventNewFolder, Path: ".trash/n/notes.txt"})
	f.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "missing"})
	if err := f.devices[""].MkdirAll(context.Background(), "empty"); err != nil {
		t.Fatal(err)
	}
	f.handle(eventbus.Event{Kind: eventbus.EventNewFolder, Path: "empty"})

	f.wantHits(t, "alpha")
	f.wantHits(t, "bravo")
	var n int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM file_content`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("file_content has %d rows, want 0", n)
	}
}

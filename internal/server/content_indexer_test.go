package server

import (
	"context"
	"database/sql"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// indexedWord is the distinctive word a folder upload must make searchable.
const indexedWord = "xylophone"

// contentFixture is a content index over a fresh database and two in-memory
// devices: the internal drive and USB1. Opens are counted so a walk can show
// which files it read.
type contentFixture struct {
	db       *sql.DB
	registry vfs.Registry
	opens    map[string]*countingVFS
}

func newContentFixture(t *testing.T) *contentFixture {
	t.Helper()
	database := dbtest.NewDB(t)
	registry := vfs.NewRegistry()
	opens := map[string]*countingVFS{}
	for _, serial := range []string{"", contentUSB} {
		ns := vfs.FilesNamespace(serial)
		wrapped := &countingVFS{VFS: vfs.NewMemVFS(ns)}
		if err := registry.Register(vfs.Namespace{ID: ns}, wrapped); err != nil {
			t.Fatal(err)
		}
		opens[serial] = wrapped
	}
	return &contentFixture{db: database.Db, registry: registry, opens: opens}
}

const contentUSB = "USB1"

func (f *contentFixture) write(t *testing.T, serial, p, body string) {
	t.Helper()
	err := f.opens[serial].Write(context.Background(), p, strings.NewReader(body), vfs.WriteOptions{})
	if err != nil {
		t.Fatal(err)
	}
}

func (f *contentFixture) event(kind eventbus.EventKind, serial, p string) {
	handleContentEvent(deputil.NewDependencies(), f.db, f.registry, eventbus.Event{
		Kind:         kind,
		DeviceSerial: serial,
		Path:         p,
	})
}

// hits is every match for query, as "serial:relPath", in path order.
func (f *contentFixture) hits(t *testing.T, query string) []string {
	t.Helper()
	found, err := searchutil.Search(context.Background(), f.db, query, 20)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(found))
	for _, hit := range found {
		out = append(out, hit.Serial+":"+hit.RelPath)
	}
	slices.Sort(out)
	return out
}

// TestContentIndexerFolderEventIndexesTheFilesUnderIt is the repro for #3300:
// an upload or new_folder event names the folder the files landed in, and a
// search for a word written into a file there finds that file. A file outside
// the folder, and a binary inside it, stay unread.
func TestContentIndexerFolderEventIndexesTheFilesUnderIt(t *testing.T) {
	for _, kind := range []eventbus.EventKind{eventbus.EventUpload, eventbus.EventNewFolder} {
		t.Run(string(kind), func(t *testing.T) {
			f := newContentFixture(t)
			f.write(t, "", "notes/trip.txt", "pack a "+indexedWord+" for the trip")
			f.write(t, "", "notes/2024/deep.md", "the "+indexedWord+" is nested")
			f.write(t, "", "notes/photo.jpg", indexedWord+" in a picture")
			f.write(t, "", "elsewhere.txt", "a "+indexedWord+" in another folder")

			// The nested upload route keeps gin's leading slash on the folder.
			f.event(kind, "", "/notes")

			want := []string{":notes/2024/deep.md", ":notes/trip.txt"}
			if got := f.hits(t, indexedWord); !slices.Equal(got, want) {
				t.Fatalf("hits = %v, want %v", got, want)
			}
			opened := append([]string(nil), f.opens[""].opened...)
			slices.Sort(opened)
			if !slices.Equal(opened, wantPaths(want)) {
				t.Fatalf("opened = %v, want only the text files under notes", opened)
			}
		})
	}
}

// TestContentIndexerFolderEventStaysOnItsDevice indexes the drive the event
// names. The same folder on the internal drive is left unread.
func TestContentIndexerFolderEventStaysOnItsDevice(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, contentUSB, "Album/note.txt", "a "+indexedWord+" on the drive")
	f.write(t, "", "Album/note.txt", "a "+indexedWord+" on the internal drive")

	f.event(eventbus.EventUpload, contentUSB, "Album")

	want := []string{contentUSB + ":Album/note.txt"}
	if got := f.hits(t, indexedWord); !slices.Equal(got, want) {
		t.Fatalf("hits = %v, want %v", got, want)
	}
	if len(f.opens[""].opened) != 0 {
		t.Fatalf("internal drive opened %v", f.opens[""].opened)
	}
}

// TestContentIndexerRootUploadIndexesTheTree treats an empty path as the
// files root, which is the folder a top-level upload names.
func TestContentIndexerRootUploadIndexesTheTree(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "top.txt", "a "+indexedWord+" at the root")
	f.write(t, "", "notes/trip.txt", "a "+indexedWord+" in a folder")
	f.write(t, "", "photo.jpg", indexedWord+" in a picture")

	f.event(eventbus.EventUpload, "", "")

	want := []string{":notes/trip.txt", ":top.txt"}
	if got := f.hits(t, indexedWord); !slices.Equal(got, want) {
		t.Fatalf("hits = %v, want %v", got, want)
	}
}

// TestContentIndexerFilePathIndexesOnlyThatFile keeps an event that names a
// file, which some writers publish, to that one file.
func TestContentIndexerFilePathIndexesOnlyThatFile(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "notes/trip.txt", "pack a "+indexedWord)
	f.write(t, "", "notes/other.txt", "another "+indexedWord)

	f.event(eventbus.EventUpload, "", "/notes/trip.txt")

	want := []string{":notes/trip.txt"}
	if got := f.hits(t, indexedWord); !slices.Equal(got, want) {
		t.Fatalf("hits = %v, want %v", got, want)
	}
	if !slices.Equal(f.opens[""].opened, []string{"notes/trip.txt"}) {
		t.Fatalf("opened = %v, want notes/trip.txt", f.opens[""].opened)
	}
}

// TestContentIndexerMoveKeepsTheNewPath drops the old path and indexes the
// file the move landed on.
func TestContentIndexerMoveKeepsTheNewPath(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "old.txt", "pack a "+indexedWord)
	f.event(eventbus.EventUpload, "", "old.txt")
	if err := f.opens[""].Move(context.Background(), "old.txt", "dir/new.txt"); err != nil {
		t.Fatal(err)
	}
	handleContentEvent(deputil.NewDependencies(), f.db, f.registry, eventbus.Event{
		Kind:    eventbus.EventMove,
		Path:    "old.txt",
		NewPath: "dir/new.txt",
	})

	want := []string{":dir/new.txt"}
	if got := f.hits(t, indexedWord); !slices.Equal(got, want) {
		t.Fatalf("hits = %v, want %v", got, want)
	}
}

// TestContentIndexerSkipsTheTrash leaves a trashed file out of the index.
func TestContentIndexerSkipsTheTrash(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", ".trash/gone.txt", "pack a "+indexedWord)
	f.event(eventbus.EventUpload, "", ".trash/gone.txt")
	f.event(eventbus.EventNewFolder, "", ".trash/album")

	if got := f.hits(t, indexedWord); len(got) != 0 {
		t.Fatalf("hits = %v, want none", got)
	}
	if len(f.opens[""].opened) != 0 {
		t.Fatalf("opened %v, want nothing in the trash read", f.opens[""].opened)
	}
}

// TestContentIndexerSkipsADeviceItCannotRead drops an event for a serial with
// no files namespace. Nothing is opened and nothing is indexed.
func TestContentIndexerSkipsADeviceItCannotRead(t *testing.T) {
	f := newContentFixture(t)
	f.write(t, "", "notes/trip.txt", "pack a "+indexedWord)

	f.event(eventbus.EventUpload, "GONE", "notes")

	if got := f.hits(t, indexedWord); len(got) != 0 {
		t.Fatalf("hits = %v, want none", got)
	}
	for serial, fsys := range f.opens {
		if len(fsys.opened) != 0 {
			t.Fatalf("device %q opened %v", serial, fsys.opened)
		}
	}
}

// wantPaths strips the leading ":" serial marker from internal-drive hits.
func wantPaths(hits []string) []string {
	out := make([]string, len(hits))
	for i, hit := range hits {
		out[i] = strings.TrimPrefix(hit, ":")
	}
	return out
}

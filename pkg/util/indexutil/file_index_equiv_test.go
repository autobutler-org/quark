package indexutil

import (
	"context"
	"fmt"
	"io/fs"
	"math/rand/v2"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// nameIndex is what FileIndex and the reference index both offer.
type nameIndex interface {
	Build(ctx context.Context, registry vfs.Registry)
	Search(query string, serials map[string]bool) []IndexedFile
	SearchEach(query string, serials map[string]bool, visit func(IndexedFile) bool)
	HandleAdd(serial, relPath string, size, mtime int64)
	HandleDelete(serial, relPath string)
	HandleMove(ctx context.Context, fsys vfs.VFS, serial, oldRelPath, newRelPath string)
	HandleRescan(ctx context.Context, fsys vfs.VFS, serial, relPath string)
}

var (
	_ nameIndex = (*FileIndex)(nil)
	_ nameIndex = (*refIndex)(nil)
)

// equivSegments are the names the randomized trees are made of: mixed case,
// non-ASCII (including the Kelvin sign, which lowercases to ASCII k), shared
// prefixes, and the internal names the index never holds.
var equivSegments = []string{
	"a", "ab", "A", "Photos", "photos 2024", "IMG_0001.JPG", "img_0001.jpg", "notes.txt",
	"Gro\u00dfe.md", "\u00dc.pdf", "Kelvin.txt", "kelvin.TXT", "日本語.txt", "x", "x.y",
	"report final.docx", "Ab", ".trash", storageutil.VersionsDirName, storageutil.WriteTempPrefix + "upload",
}

// equivQueries are run against both indexes after every step.
var equivQueries = []string{
	"", "a", "A", "img", "IMG_0001", ".txt", "GROSS", "gro\u00dfe", "ü", "Ü", "k", "K",
	"kelvin", "日本", "/", "a/b", "photos 2", "x.y", "nothing-matches", " ",
}

// equivState is a randomized pair of devices on disk, indexed twice.
type equivState struct {
	t       *testing.T
	rng     *rand.Rand
	mounts  []mount
	devices devices
	got     *FileIndex
	want    *refIndex
}

// pickDevice returns one device's files directory, serial and namespace.
func (s *equivState) pickDevice() (string, string, vfs.VFS) {
	m := s.mounts[s.rng.IntN(len(s.mounts))]
	return m.filesDir, m.serial, s.devices.fsys(s.t, m.serial)
}

// randomRel makes a relative path one to three segments deep.
func (s *equivState) randomRel() string {
	parts := make([]string, 1+s.rng.IntN(3))
	for i := range parts {
		parts[i] = equivSegments[s.rng.IntN(len(equivSegments))]
	}
	return strings.Join(parts, "/")
}

// existing returns a path already on disk under dir, files and folders alike,
// or a random one when the device is empty.
func (s *equivState) existing(dir string) string {
	var all []string
	_ = filepath.WalkDir(dir, func(p string, _ fs.DirEntry, err error) error {
		if err == nil && p != dir {
			rel, _ := filepath.Rel(dir, p)
			all = append(all, filepath.ToSlash(rel))
		}
		return nil
	})
	if len(all) == 0 {
		return s.randomRel()
	}
	return all[s.rng.IntN(len(all))]
}

// writeFile creates a file at rel, making its folders, unless a file is in
// the way of one of them.
func (s *equivState) writeFile(dir, rel string) bool {
	full := filepath.Join(dir, filepath.FromSlash(rel))
	if os.MkdirAll(filepath.Dir(full), 0o755) != nil {
		return false
	}
	if info, err := os.Stat(full); err == nil && info.IsDir() {
		return false
	}
	return os.WriteFile(full, nil, 0o644) == nil
}

// step changes the disk at random and tells both indexes what the watcher
// would, sometimes with an event that disagrees with the disk.
func (s *equivState) step() string {
	dir, serial, fsys := s.pickDevice()
	ctx := context.Background()
	both := func(f func(nameIndex)) { f(s.got); f(s.want) }
	switch s.rng.IntN(10) {
	case 0: // upload: the event names the folder
		rel := s.randomRel()
		if !s.writeFile(dir, rel) {
			return "upload blocked"
		}
		parent := filepath.ToSlash(filepath.Dir(rel))
		both(func(i nameIndex) { i.HandleRescan(ctx, fsys, serial, parent) })
		return "upload " + rel
	case 1: // a file added by path
		rel := s.randomRel()
		s.writeFile(dir, rel)
		both(func(i nameIndex) { i.HandleAdd(serial, rel, 0, 0) })
		return "add " + rel
	case 2: // new folder with files in it
		rel := s.randomRel()
		for range 1 + s.rng.IntN(4) {
			s.writeFile(dir, rel+"/"+equivSegments[s.rng.IntN(len(equivSegments))])
		}
		both(func(i nameIndex) { i.HandleRescan(ctx, fsys, serial, rel) })
		return "new folder " + rel
	case 3, 4: // delete
		rel := s.existing(dir)
		_ = os.RemoveAll(filepath.Join(dir, filepath.FromSlash(rel)))
		both(func(i nameIndex) { i.HandleDelete(serial, rel) })
		return "delete " + rel
	case 5, 6: // move, sometimes into the trash
		from := s.existing(dir)
		to := s.randomRel()
		if s.rng.IntN(5) == 0 {
			to = ".trash/" + to
		}
		dst := filepath.Join(dir, filepath.FromSlash(to))
		if os.MkdirAll(filepath.Dir(dst), 0o755) == nil {
			_ = os.RemoveAll(dst)
			_ = os.Rename(filepath.Join(dir, filepath.FromSlash(from)), dst)
		}
		both(func(i nameIndex) { i.HandleMove(ctx, fsys, serial, from, to) })
		return "move " + from + " -> " + to
	case 7: // stale events naming paths the disk does not have
		rel, to := s.randomRel(), s.randomRel()
		switch s.rng.IntN(3) {
		case 0:
			both(func(i nameIndex) { i.HandleDelete(serial, rel) })
		case 1:
			both(func(i nameIndex) { i.HandleMove(ctx, fsys, serial, rel, to) })
		default:
			both(func(i nameIndex) { i.HandleRescan(ctx, fsys, serial, rel) })
		}
		return "stale " + rel
	case 8: // a change nobody published, then a rescan of a folder above it
		rel := s.randomRel()
		s.writeFile(dir, rel)
		parts := strings.Split(rel, "/")
		up := strings.Join(parts[:s.rng.IntN(len(parts))], "/")
		both(func(i nameIndex) { i.HandleRescan(ctx, fsys, serial, up) })
		return "rescan " + up
	default: // resync
		both(func(i nameIndex) { i.Build(ctx, s.devices.registry) })
		return "resync"
	}
}

// sortedFiles is a result in a fixed order, for comparing as a set.
func sortedFiles(files []IndexedFile) []string {
	out := make([]string, len(files))
	for i, f := range files {
		out[i] = f.DeviceSerial + "|" + f.RelPath + "|" + f.Name
	}
	slices.Sort(out)
	return out
}

// compare fails when any query or device filter answers differently.
func (s *equivState) compare(after string) {
	s.t.Helper()
	filters := []map[string]bool{nil, {"": true}, {"USB1": true}, {"": true, "USB1": true}, {"none": true}}
	for _, q := range equivQueries {
		for _, serials := range filters {
			got, want := sortedFiles(s.got.Search(q, serials)), sortedFiles(s.want.Search(q, serials))
			if !slices.Equal(got, want) {
				s.t.Fatalf("after %s, Search(%q, %v):\n got  %v\n want %v", after, q, serials, got, want)
			}
			// Stopping early returns that many of the same matches.
			limit := s.rng.IntN(len(want) + 1)
			var some []IndexedFile
			s.got.SearchEach(q, serials, func(f IndexedFile) bool {
				some = append(some, f)
				return len(some) < limit
			})
			if limit > 0 && len(some) != limit {
				s.t.Fatalf("after %s, SearchEach(%q) stopped at %d, want %d", after, q, len(some), limit)
			}
			for _, f := range sortedFiles(some) {
				if _, ok := slices.BinarySearch(want, f); !ok {
					s.t.Fatalf("after %s, SearchEach(%q) visited %s, not a match", after, q, f)
				}
			}
		}
	}
}

// The table (#2956) answers every search exactly as the map-per-folder index
// the in-memory one replaced did, through randomized trees and randomized event
// sequences: uploads, adds, new folders, deletes and moves of files and
// folders, moves into the trash, stale events, unpublished changes, resyncs,
// and two devices with their own serials.
func TestFileIndexMatchesReference(t *testing.T) {
	for seed := range uint64(12) {
		t.Run(fmt.Sprint("seed", seed), func(t *testing.T) {
			// Each seed has its own disk and database.
			t.Parallel()
			s := &equivState{
				t:      t,
				rng:    rand.New(rand.NewPCG(seed, 2760)),
				mounts: []mount{newMount(t, ""), newMount(t, "USB1")},
				got:    newIndex(t),
				want:   newRefIndex(),
			}
			s.devices = newDevices(t, s.mounts...)
			for range 60 {
				dir, _, _ := s.pickDevice()
				s.writeFile(dir, s.randomRel())
			}
			s.got.Build(context.Background(), s.devices.registry)
			s.want.Build(context.Background(), s.devices.registry)
			s.compare("build")
			for range 80 {
				s.compare(s.step())
			}
		})
	}
}

// syntheticRel is the i-th path of a generated library: 100 files a folder,
// 50 folders per year, names shaped like camera and document files.
func syntheticRel(i int) string {
	folder := i / 100
	year := 2000 + folder/50
	switch i % 4 {
	case 0, 1:
		return fmt.Sprintf("Photos/%d/Trip %03d/IMG_%d%04d_%06d.jpg", year, folder%50, year, folder%10000, i)
	case 2:
		return fmt.Sprintf("Photos/%d/Trip %03d/PXL_%08d.MP4", year, folder%50, i)
	default:
		return fmt.Sprintf("Documents/%d/Folder %03d/Report %d final.pdf", year, folder%50, i)
	}
}

// BenchmarkFileIndexBuild measures Build, the startup and resync cost, over
// a generated tree of 100k empty files on disk, against the in-memory
// reference, then how long a miss, a hit and a two-letter query take to
// search the table: a miss and a hit go through the trigram index, the short
// query reads the rows in order. Point TMPDIR at a disk, not tmpfs, to
// measure a real walk.
func BenchmarkFileIndexBuild(b *testing.B) {
	internal := newMount(b, "")
	root := internal.filesDir
	made := map[string]bool{}
	for i := range 100_000 {
		full := filepath.Join(root, filepath.FromSlash(syntheticRel(i)))
		if parent := filepath.Dir(full); !made[parent] {
			if err := os.MkdirAll(parent, 0o755); err != nil {
				b.Fatal(err)
			}
			made[parent] = true
		}
		if err := os.WriteFile(full, nil, 0o644); err != nil {
			b.Fatal(err)
		}
	}
	registry := newDevices(b, internal).registry
	table := NewFileIndex(dbtest.NewDB(b))
	for _, impl := range []struct {
		name string
		idx  func() nameIndex
	}{{"table", func() nameIndex { return table }}, {"reference", func() nameIndex { return newRefIndex() }}} {
		b.Run(impl.name, func(b *testing.B) {
			b.ReportAllocs()
			for range b.N {
				impl.idx().Build(context.Background(), registry)
			}
		})
	}
	for _, q := range []string{"zzz-miss", "img_2003", "xq"} {
		b.Run("search/"+q, func(b *testing.B) {
			for range b.N {
				hits := 0
				table.SearchEach(q, nil, func(IndexedFile) bool { hits++; return hits < 500 })
			}
		})
	}
}

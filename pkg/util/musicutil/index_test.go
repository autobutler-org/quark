package musicutil_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func indexTrack(t *testing.T, sqlDB *db.DatabaseSqlc, fsys vfs.VFS, relPath string) musicutil.IndexTrackResult {
	t.Helper()
	got, err := musicutil.IndexTrack(musicutil.IndexTrackParams{
		Ctx: context.Background(), DB: sqlDB.Db, FS: fsys, Serial: usbSerial, RelPath: relPath,
	})
	if err != nil {
		t.Fatalf("IndexTrack(%q): %v", relPath, err)
	}
	return got
}

func backfill(t *testing.T, database *db.DatabaseSqlc, fsys vfs.VFS) musicutil.BackfillDeviceResult {
	t.Helper()
	got, err := musicutil.BackfillDevice(musicutil.BackfillDeviceParams{
		Ctx: context.Background(), DB: database.Db, FS: fsys, Serial: usbSerial,
	})
	if err != nil {
		t.Fatalf("BackfillDevice: %v", err)
	}
	return got
}

// TestIndexTrack_ReadsTags stores what the tags say, with the album artist
// falling back to the artist and the duration from the stream header.
func TestIndexTrack_ReadsTags(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{"Nina/Pastel/01.flac": tagged("Feeling Good", "Nina Simone", "Pastel Blues", "Jazz", 1)})

	if got := indexTrack(t, database, fsys, "/Nina/Pastel/01.flac"); !got.Indexed || got.TagsUnreadable {
		t.Fatalf("IndexTrack = %+v, want indexed with readable tags", got)
	}
	row, ok := rows(t, database.Db)[usbSerial+":Nina/Pastel/01.flac"]
	if !ok {
		t.Fatalf("no row for the track; rows = %v", rows(t, database.Db))
	}
	if row.Title != "Feeling Good" || row.Artist != "Nina Simone" || row.AlbumArtist != "Nina Simone" ||
		row.Album != "Pastel Blues" || row.Genre != "Jazz" || row.TrackNo.Int64 != 1 || row.Year.Int64 != 1999 {
		t.Errorf("row = %+v", row)
	}
	if row.DurationMs.Int64 != 180_000 || row.DurationExact != 1 {
		t.Errorf("duration = %v exact %d, want 180000 exact", row.DurationMs, row.DurationExact)
	}
	if row.ScannerVersion != musicutil.ScannerVersion || row.AlbumKey == "" || row.CoverSource != "" {
		t.Errorf("version %d, album key %q, cover %q", row.ScannerVersion, row.AlbumKey, row.CoverSource)
	}
}

// TestIndexTrack_AlbumKeySplitsFolders keeps two same-named albums by one
// artist apart when they sit in different folders, and joins the tracks of
// one folder regardless of tag case.
func TestIndexTrack_AlbumKeySplitsFolders(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{
		"a/1.flac": tagged("One", "Band", "Greatest Hits", "Rock", 1),
		"a/2.flac": tagged("Two", "BAND", "greatest hits", "Rock", 2),
		"b/1.flac": tagged("Three", "Band", "Greatest Hits", "Rock", 1),
	})
	backfill(t, database, fsys)
	got := rows(t, database.Db)
	a1, a2, b1 := got[usbSerial+":a/1.flac"], got[usbSerial+":a/2.flac"], got[usbSerial+":b/1.flac"]
	if a1.AlbumKey != a2.AlbumKey {
		t.Errorf("one folder's tracks have keys %q and %q, want one album", a1.AlbumKey, a2.AlbumKey)
	}
	if a1.AlbumKey == b1.AlbumKey {
		t.Errorf("two folders share album key %q, want two albums", a1.AlbumKey)
	}
}

// TestIndexTrack_UnreadableTagsStillIndexed keeps a file whose tags cannot
// be read in the library, titled from its name.
func TestIndexTrack_UnreadableTagsStillIndexed(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{"odd/My Song.mp3": []byte("this is not an mp3 at all")})

	got := indexTrack(t, database, fsys, "odd/My Song.mp3")
	if !got.Indexed || !got.TagsUnreadable {
		t.Fatalf("IndexTrack = %+v, want indexed with unreadable tags", got)
	}
	if row := rows(t, database.Db)[usbSerial+":odd/My Song.mp3"]; row.Title != "My Song" {
		t.Errorf("Title = %q, want the file name", row.Title)
	}
}

// TestIndexTrack_SkipsWhatIsNotLibraryAudio leaves non-audio files, the
// trash, the version store and in-flight writes alone without opening them.
func TestIndexTrack_SkipsWhatIsNotLibraryAudio(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{"notes.txt": []byte("hi")})
	for _, p := range []string{"notes.txt", ".trash/x/a.flac", "music/" + storageutil.VersionsDirName + "/a.flac", "music/" + storageutil.WriteTempPrefix + "a.flac"} {
		got, err := musicutil.IndexTrack(musicutil.IndexTrackParams{
			Ctx: context.Background(), DB: database.Db, FS: fsys, Serial: usbSerial, RelPath: p,
		})
		if err != nil || got.Indexed {
			t.Errorf("IndexTrack(%q) = %+v, %v; want a no-op", p, got, err)
		}
	}
	if len(fsys.opened) != 0 || len(rows(t, database.Db)) != 0 {
		t.Errorf("opened %v and stored %d rows, want neither", fsys.opened, len(rows(t, database.Db)))
	}
}

// TestIndexTrack_CoverSources prefers an embedded picture, then the
// best-ranked folder image matched without case, and keys each by its bytes.
func TestIndexTrack_CoverSources(t *testing.T) {
	database := newDB(t)
	art := []byte("\xff\xd8\xff folder art")
	embedded := []byte("\xff\xd8\xff embedded art")
	fsys := memFS(t, map[string][]byte{
		"album/01.flac":    flacFile(10, nil, "TITLE=a"),
		"album/02.flac":    flacFile(10, embedded, "TITLE=b"),
		"album/Album.png":  []byte("lower ranked"),
		"album/COVER.JPG":  art,
		"album/notes.jpg":  []byte("not a cover name"),
		"bare/01.flac":     flacFile(10, nil, "TITLE=c"),
		"bare/picture.jpg": []byte("not a cover name"),
	})
	backfill(t, database, fsys)
	got := rows(t, database.Db)
	sum := func(b []byte) string { s := sha256.Sum256(b); return hex.EncodeToString(s[:]) }

	if r := got[usbSerial+":album/01.flac"]; r.CoverSource != "folder:COVER.JPG" || r.CoverKey != sum(art) {
		t.Errorf("folder cover = %q %q, want folder:COVER.JPG keyed by its bytes", r.CoverSource, r.CoverKey)
	}
	if r := got[usbSerial+":album/02.flac"]; r.CoverSource != "embedded" || r.CoverKey != sum(embedded) {
		t.Errorf("embedded cover = %q %q, want embedded keyed by the picture", r.CoverSource, r.CoverKey)
	}
	if r := got[usbSerial+":bare/01.flac"]; r.CoverSource != "" || r.CoverKey != "" {
		t.Errorf("bare folder cover = %q %q, want none", r.CoverSource, r.CoverKey)
	}
}

// TestBackfillDevice_Incremental opens only new or changed files on a second
// pass and drops the rows of files that are gone.
func TestBackfillDevice_Incremental(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{
		"a/1.flac":  tagged("One", "X", "A", "Rock", 1),
		"a/2.flac":  tagged("Two", "X", "A", "Rock", 2),
		"b/3.flac":  tagged("Three", "Y", "B", "Pop", 1),
		"readme.md": []byte("not audio"),
	})

	first := backfill(t, database, fsys)
	if first != (musicutil.BackfillDeviceResult{Scanned: 3, Indexed: 3}) {
		t.Fatalf("first pass = %+v, want 3 scanned and indexed", first)
	}

	fsys.opened = nil
	second := backfill(t, database, fsys)
	if second != (musicutil.BackfillDeviceResult{Scanned: 3, Unchanged: 3}) || len(fsys.opened) != 0 {
		t.Fatalf("unchanged pass = %+v opening %v, want 3 unchanged and nothing opened", second, fsys.opened)
	}

	ctx := context.Background()
	write(t, fsys, "a/2.flac", flacFile(200, nil, "TITLE=Two (remaster)"))
	if err := fsys.Delete(ctx, "b/3.flac", vfs.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	write(t, fsys, "c/4.flac", tagged("Four", "Z", "C", "Jazz", 1))
	fsys.opened = nil
	third := backfill(t, database, fsys)
	if third != (musicutil.BackfillDeviceResult{Scanned: 3, Indexed: 2, Unchanged: 1, Deleted: 1}) {
		t.Fatalf("third pass = %+v, want the changed and new file read and the gone one deleted", third)
	}
	if slices.Contains(fsys.opened, "a/1.flac") {
		t.Errorf("opened %v, which includes the unchanged a/1.flac", fsys.opened)
	}
	got := rows(t, database.Db)
	if _, ok := got[usbSerial+":b/3.flac"]; ok {
		t.Error("the deleted file's row is still there")
	}
	if got[usbSerial+":a/2.flac"].Title != "Two (remaster)" {
		t.Errorf("changed file title = %q", got[usbSerial+":a/2.flac"].Title)
	}
}

// TestBackfillDevice_ScannerVersionForcesReread re-reads a row stored by an
// older scanner even though the file is unchanged.
func TestBackfillDevice_ScannerVersionForcesReread(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{"1.flac": tagged("One", "X", "A", "Rock", 1)})
	backfill(t, database, fsys)
	if _, err := database.Db.Exec(`UPDATE music_tracks SET scanner_version = 0`); err != nil {
		t.Fatal(err)
	}
	if got := backfill(t, database, fsys); got.Indexed != 1 {
		t.Errorf("pass after a scanner bump = %+v, want the file re-read", got)
	}
}

// TestBackfillDevice_CanceledDeletesNothing keeps every row when the walk
// did not finish: a file it never reached is not a file that is gone.
func TestBackfillDevice_CanceledDeletesNothing(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{"a/1.flac": tagged("One", "X", "A", "Rock", 1), "b/2.flac": tagged("Two", "X", "B", "Rock", 1)})
	backfill(t, database, fsys)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	got, err := musicutil.BackfillDevice(musicutil.BackfillDeviceParams{Ctx: ctx, DB: database.Db, FS: fsys, Serial: usbSerial})
	if err == nil || got.Deleted != 0 {
		t.Fatalf("canceled pass = %+v, %v; want an error and nothing deleted", got, err)
	}
	if n := len(rows(t, database.Db)); n != 2 {
		t.Errorf("%d rows after a canceled pass, want 2", n)
	}
}

// TestBackfillDevice_FileBecameFolder drops the row of a path that is now a
// folder and indexes what the folder holds.
func TestBackfillDevice_FileBecameFolder(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{"x.flac": tagged("Old", "X", "A", "Rock", 1)})
	backfill(t, database, fsys)
	if err := fsys.Delete(context.Background(), "x.flac", vfs.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	write(t, fsys, "x.flac/inner.flac", tagged("New", "X", "A", "Rock", 1))

	got := backfill(t, database, fsys)
	if got.Deleted != 1 || got.Indexed != 1 {
		t.Errorf("pass = %+v, want the stale row deleted and the inner file indexed", got)
	}
	stored := rows(t, database.Db)
	if _, ok := stored[usbSerial+":x.flac"]; ok || len(stored) != 1 {
		t.Errorf("rows = %v, want only x.flac/inner.flac", stored)
	}
}

// TestMovePath_RewritesAndRekeys moves a folder's rows without reading a
// file, recomputes their album key for the new folder, and replaces what the
// destination held.
func TestMovePath_RewritesAndRekeys(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{
		"old/1.flac":  tagged("One", "X", "A", "Rock", 1),
		"old/2.flac":  tagged("Two", "X", "A", "Rock", 2),
		"new/1.flac":  tagged("Stale", "Y", "B", "Pop", 1),
		"old2/1.flac": tagged("Keep", "Z", "C", "Jazz", 1),
	})
	backfill(t, database, fsys)
	before := rows(t, database.Db)

	got, err := musicutil.MovePath(musicutil.MovePathParams{
		Ctx: context.Background(), DB: database.Db, Serial: usbSerial, OldPath: "/old", NewPath: "new/",
	})
	if err != nil || got.Moved != 2 {
		t.Fatalf("MovePath = %+v, %v; want 2 moved", got, err)
	}
	after := rows(t, database.Db)
	moved := after[usbSerial+":new/1.flac"]
	if moved.Title != "One" || moved.ID != before[usbSerial+":old/1.flac"].ID {
		t.Errorf("new/1.flac = %+v, want the moved row", moved)
	}
	if moved.AlbumKey == before[usbSerial+":old/1.flac"].AlbumKey {
		t.Error("album key did not change with the folder")
	}
	if moved.AlbumKey != after[usbSerial+":new/2.flac"].AlbumKey {
		t.Error("the moved album's tracks no longer share a key")
	}
	if _, ok := after[usbSerial+":old2/1.flac"]; !ok || len(after) != 3 {
		t.Errorf("rows = %v, want old2 untouched and the stale destination row gone", after)
	}

	// The key a fresh scan computes is the one the move wrote.
	fresh := newDB(t)
	write(t, fsys, "new/1.flac", tagged("One", "X", "A", "Rock", 1))
	indexTrack(t, fresh, fsys, "new/1.flac")
	if k := rows(t, fresh.Db)[usbSerial+":new/1.flac"].AlbumKey; k != moved.AlbumKey {
		t.Errorf("moved key %q, fresh scan key %q; want them equal", moved.AlbumKey, k)
	}
}

// TestDeletePathAndDropDevice drops a folder's rows, then a device's.
func TestDeletePathAndDropDevice(t *testing.T) {
	database := newDB(t)
	fsys := memFS(t, map[string][]byte{
		"a/1.flac":   tagged("One", "X", "A", "Rock", 1),
		"a/b/2.flac": tagged("Two", "X", "A", "Rock", 2),
		"ab/3.flac":  tagged("Three", "X", "A", "Rock", 3),
	})
	backfill(t, database, fsys)
	ctx := context.Background()

	if _, err := musicutil.DeletePath(musicutil.DeletePathParams{Ctx: ctx, DB: database.Db, Serial: usbSerial, RelPath: "a"}); err != nil {
		t.Fatal(err)
	}
	got := rows(t, database.Db)
	if _, ok := got[usbSerial+":ab/3.flac"]; !ok || len(got) != 1 {
		t.Fatalf("rows after deleting a = %v, want only ab/3.flac", got)
	}

	if _, err := musicutil.DropDevice(musicutil.DropDeviceParams{Ctx: ctx, DB: database.Db, Serial: usbSerial}); err != nil {
		t.Fatal(err)
	}
	if n := len(rows(t, database.Db)); n != 0 {
		t.Errorf("%d rows after dropping the device, want 0", n)
	}
}

package server

import (
	"bytes"
	"context"
	"encoding/binary"
	"path"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const musicUSB = "USB-MUSIC"

// flacTrack is a FLAC file titled title: a STREAMINFO block for a three
// minute track and a Vorbis comment block.
func flacTrack(title string) []byte {
	const rate, seconds = 44100, 180
	info := make([]byte, 34)
	binary.BigEndian.PutUint64(info[10:18], uint64(rate)<<44|uint64(1)<<41|uint64(15)<<36|seconds*rate)
	comment := "TITLE=" + title
	vc := binary.LittleEndian.AppendUint32(nil, 4)
	vc = append(vc, "test"...)
	vc = binary.LittleEndian.AppendUint32(vc, 1)
	vc = binary.LittleEndian.AppendUint32(vc, uint32(len(comment)))
	vc = append(vc, comment...)
	block := func(typ byte, body []byte) []byte {
		return append([]byte{typ, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}, body...)
	}
	out := append([]byte("fLaC"), block(0, info)...)
	out = append(out, block(0x84, vc)...)
	return append(out, make([]byte, 64)...)
}

// musicFixture is an indexer over a fresh database, a bus and two in-memory
// devices: the internal drive and musicUSB.
type musicFixture struct {
	indexer  *musicIndexer
	database *db.DatabaseSqlc
	bus      *eventbus.Bus
	registry vfs.Registry
	events   <-chan eventbus.Event
	devices  map[string]vfs.VFS
}

func newMusicFixture(t *testing.T) *musicFixture {
	t.Helper()
	database := dbtest.NewDB(t)
	bus := eventbus.New()
	registry := vfs.NewRegistry()
	devices := map[string]vfs.VFS{}
	for _, serial := range []string{"", musicUSB} {
		ns := vfs.FilesNamespace(serial)
		devices[serial] = vfs.NewMemVFS(ns)
		if err := registry.Register(vfs.Namespace{ID: ns}, devices[serial]); err != nil {
			t.Fatal(err)
		}
	}
	jobs := jobutil.NewQueue(jobutil.NewQueueParams{Database: database, EventBus: bus})
	deps := deputil.NewDependencies().
		WithDatabase(database).WithEventBus(bus).WithVFSRegistry(registry).WithJobQueue(jobs)
	indexer := newMusicIndexer(deps)
	indexer.changes.delay = 10 * time.Millisecond
	indexer.settle = 10 * time.Millisecond
	jobs.Register(jobutil.RegisterParams{Kind: musicRescanKind, Handler: indexer.rescanHandler()})
	events, unsub := bus.Subscribe("test")
	t.Cleanup(unsub)
	return &musicFixture{indexer: indexer, database: database, bus: bus, registry: registry, events: events, devices: devices}
}

func (f *musicFixture) write(t *testing.T, serial, p string, data []byte) {
	t.Helper()
	ctx := context.Background()
	fsys := f.devices[serial]
	if err := fsys.MkdirAll(ctx, path.Dir(p)); err != nil {
		t.Fatal(err)
	}
	if err := fsys.Write(ctx, p, bytes.NewReader(data), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
}

// titles is every stored track's title, keyed by serial and path.
func (f *musicFixture) titles(t *testing.T) map[string]string {
	t.Helper()
	rows, err := f.database.Queries.ListMusicTracksAfter(context.Background(), db.ListMusicTracksAfterParams{Limit: 1 << 20})
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, row := range rows {
		out[row.Serial+":"+row.RelPath] = row.Title
	}
	return out
}

// wantTitles fails unless the library holds exactly want.
func (f *musicFixture) wantTitles(t *testing.T, want map[string]string) {
	t.Helper()
	got := f.titles(t)
	if len(got) != len(want) {
		t.Fatalf("library = %v, want %v", got, want)
	}
	for k, v := range want {
		if got[k] != v {
			t.Fatalf("library = %v, want %v", got, want)
		}
	}
}

// nextLibraryChange waits for the next music_library_changed, skipping any
// other event.
func (f *musicFixture) nextLibraryChange(t *testing.T) eventbus.Event {
	t.Helper()
	timeout := time.After(5 * time.Second)
	for {
		select {
		case evt := <-f.events:
			if evt.Kind == eventbus.EventMusicLibraryChanged {
				return evt
			}
		case <-timeout:
			t.Fatal("no music_library_changed")
		}
	}
}

// noLibraryChange fails if a music_library_changed arrives within a while.
func (f *musicFixture) noLibraryChange(t *testing.T) {
	t.Helper()
	timeout := time.After(100 * time.Millisecond)
	for {
		select {
		case evt := <-f.events:
			if evt.Kind == eventbus.EventMusicLibraryChanged {
				t.Fatalf("unexpected %+v", evt)
			}
		case <-timeout:
			return
		}
	}
}

// TestMusicIndexerFollowsFileEvents walks one track through upload, move,
// a rename away from an audio name and back, and delete, and checks each step
// lands in the library and is announced for its device.
func TestMusicIndexerFollowsFileEvents(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, musicUSB, "Music/a.flac", flacTrack("Alpha"))

	f.indexer.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "Music/a.flac", DeviceSerial: musicUSB})
	f.wantTitles(t, map[string]string{musicUSB + ":Music/a.flac": "Alpha"})
	if evt := f.nextLibraryChange(t); evt.DeviceSerial != musicUSB || evt.Path != "" {
		t.Fatalf("event = %+v, want one for %s with no path", evt, musicUSB)
	}

	f.indexer.handle(eventbus.Event{Kind: eventbus.EventMove, Path: "Music", NewPath: "Albums", DeviceSerial: musicUSB})
	f.wantTitles(t, map[string]string{musicUSB + ":Albums/a.flac": "Alpha"})
	f.nextLibraryChange(t)

	f.indexer.handle(eventbus.Event{Kind: eventbus.EventMove, Path: "Albums/a.flac", NewPath: "Albums/a.txt", DeviceSerial: musicUSB})
	f.wantTitles(t, map[string]string{})
	f.nextLibraryChange(t)

	// The file is read again under its audio name, since no row moved.
	f.write(t, musicUSB, "Albums/a.flac", flacTrack("Alpha"))
	f.indexer.handle(eventbus.Event{Kind: eventbus.EventMove, Path: "Albums/a.txt", NewPath: "Albums/a.flac", DeviceSerial: musicUSB})
	f.wantTitles(t, map[string]string{musicUSB + ":Albums/a.flac": "Alpha"})
	f.nextLibraryChange(t)

	f.indexer.handle(eventbus.Event{Kind: eventbus.EventDelete, Path: "Albums", DeviceSerial: musicUSB})
	f.wantTitles(t, map[string]string{})
	f.nextLibraryChange(t)
}

// TestMusicIndexerIgnoresNonAudio writes no row and announces nothing for a
// file that is not audio.
func TestMusicIndexerIgnoresNonAudio(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, "", "notes.txt", []byte("hello"))
	f.indexer.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "notes.txt"})
	f.wantTitles(t, map[string]string{})
	f.noLibraryChange(t)
}

// TestMusicIndexerFolderUploadBackfillsItsDevice reads every track under an
// uploaded folder, since an upload event names only the folder it landed in,
// and leaves a folder with no audio alone.
func TestMusicIndexerFolderUploadBackfillsItsDevice(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, "", "Photos/beach.jpg", []byte("jpeg"))
	f.indexer.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "Photos"})
	if len(f.indexer.dirty) != 0 {
		t.Fatalf("dirty = %v after a folder with no audio", f.indexer.dirty)
	}

	f.write(t, "", "Albums/One/a.flac", flacTrack("Alpha"))
	f.write(t, "", "Albums/One/b.flac", flacTrack("Bravo"))
	f.indexer.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: ""})
	f.indexer.handle(eventbus.Event{Kind: eventbus.EventNewFolder, Path: "Albums/One"})
	if !f.indexer.dirty[""] || len(f.indexer.dirty) != 1 {
		t.Fatalf("dirty = %v, want the internal drive", f.indexer.dirty)
	}
	f.indexer.backfillDirty()
	f.wantTitles(t, map[string]string{":Albums/One/a.flac": "Alpha", ":Albums/One/b.flac": "Bravo"})
	if evt := f.nextLibraryChange(t); evt.DeviceSerial != "" {
		t.Fatalf("event = %+v, want the internal drive's", evt)
	}
	if len(f.indexer.dirty) != 0 {
		t.Fatalf("dirty = %v after the backfill", f.indexer.dirty)
	}
}

// TestMusicIndexerRunLoop drives the subscriber through the bus: a folder
// upload settles into a backfill, and a resync reconciles every device.
func TestMusicIndexerRunLoop(t *testing.T) {
	f := newMusicFixture(t)
	// A row exists, so startup runs the pass in place rather than queueing
	// the first scan.
	f.write(t, musicUSB, "old.flac", flacTrack("Old"))
	f.indexer.handle(eventbus.Event{Kind: eventbus.EventUpload, Path: "old.flac", DeviceSerial: musicUSB})
	f.nextLibraryChange(t)

	go f.indexer.run(deputil.NewDependencies())
	f.write(t, "", "Albums/a.flac", flacTrack("Alpha"))
	// Wait for the subscription before publishing.
	deadline := time.Now().Add(5 * time.Second)
	for {
		f.bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "Albums"})
		if _, ok := f.titles(t)[":Albums/a.flac"]; ok {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("folder upload never indexed")
		}
		time.Sleep(20 * time.Millisecond)
	}

	if err := f.devices[musicUSB].Delete(context.Background(), "old.flac", vfs.DeleteOptions{}); err != nil {
		t.Fatal(err)
	}
	f.bus.Publish(eventbus.Event{Kind: eventbus.EventResync})
	for time.Now().Before(deadline) {
		if _, ok := f.titles(t)[musicUSB+":old.flac"]; !ok {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("resync never dropped the deleted file's row")
}

// TestMusicIndexerSyncDevices drops the rows of a drive that went away and
// backfills one that appeared.
func TestMusicIndexerSyncDevices(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, musicUSB, "a.flac", flacTrack("Alpha"))
	f.indexer.backfillAll()
	f.wantTitles(t, map[string]string{musicUSB + ":a.flac": "Alpha"})
	f.nextLibraryChange(t)

	f.registry.Unregister(vfs.FilesNamespace(musicUSB))
	f.indexer.syncDevices()
	f.wantTitles(t, map[string]string{})
	if evt := f.nextLibraryChange(t); evt.DeviceSerial != musicUSB {
		t.Fatalf("event = %+v, want %s's", evt, musicUSB)
	}

	if err := f.registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(musicUSB)}, f.devices[musicUSB]); err != nil {
		t.Fatal(err)
	}
	f.indexer.syncDevices()
	f.wantTitles(t, map[string]string{musicUSB + ":a.flac": "Alpha"})
}

// TestMusicIndexerFirstStartQueuesTheScan queues music_rescan when the
// library is empty and no scan is on record, and not again once one is.
func TestMusicIndexerFirstStartQueuesTheScan(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, "", "a.flac", flacTrack("Alpha"))
	f.indexer.startup()
	listed, err := f.indexer.jobs.List(context.Background(), jobutil.ListParams{Kinds: []string{musicRescanKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(listed.Jobs) != 1 {
		t.Fatalf("jobs = %+v, want one queued scan", listed.Jobs)
	}
	// The job reads the files, not startup.
	f.wantTitles(t, map[string]string{})
	if f.indexer.firstStart(context.Background()) {
		t.Fatal("firstStart with a scan on record")
	}
}

// TestMusicIndexerStartupBackfillsAScannedLibrary runs the incremental pass
// in place once the library has rows.
func TestMusicIndexerStartupBackfillsAScannedLibrary(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, "", "a.flac", flacTrack("Alpha"))
	f.indexer.indexPath("", "a.flac")
	f.write(t, "", "b.flac", flacTrack("Bravo"))
	f.indexer.startup()
	f.wantTitles(t, map[string]string{":a.flac": "Alpha", ":b.flac": "Bravo"})
	listed, err := f.indexer.jobs.List(context.Background(), jobutil.ListParams{Kinds: []string{musicRescanKind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(listed.Jobs) != 0 {
		t.Fatalf("jobs = %+v, want none", listed.Jobs)
	}
}

// TestMusicRescanJob scans every device, reports progress up to done, and
// announces each device as it finishes, even one with nothing new.
func TestMusicRescanJob(t *testing.T) {
	f := newMusicFixture(t)
	f.write(t, "", "a.flac", flacTrack("Alpha"))
	f.write(t, musicUSB, "b.flac", flacTrack("Bravo"))
	var progress []float64
	run := f.indexer.rescanHandler().Run
	if err := run(context.Background(), []byte("{}"), func(p float64) { progress = append(progress, p) }); err != nil {
		t.Fatal(err)
	}
	f.wantTitles(t, map[string]string{":a.flac": "Alpha", musicUSB + ":b.flac": "Bravo"})
	if len(progress) == 0 || progress[len(progress)-1] >= 1 {
		t.Fatalf("progress = %v, want steps held below 1", progress)
	}
	for _, want := range []string{"", musicUSB} {
		if evt := f.nextLibraryChange(t); evt.DeviceSerial != want {
			t.Fatalf("event = %+v, want %q's", evt, want)
		}
	}

	// A second scan changes nothing and still says it finished.
	if err := run(context.Background(), []byte("{}"), func(float64) {}); err != nil {
		t.Fatal(err)
	}
	f.nextLibraryChange(t)
	f.nextLibraryChange(t)
}

// TestMusicRescanJobCanceled stops at the first device once its context is
// canceled and reports the cancel.
func TestMusicRescanJobCanceled(t *testing.T) {
	f := newMusicFixture(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := f.indexer.rescan(ctx, func(float64) {}); err == nil {
		t.Fatal("rescan with a canceled context succeeded")
	}
}

func TestRescanProgress(t *testing.T) {
	for _, tc := range []struct {
		scanned       int
		total         int64
		done, devices int
		want          float64
	}{
		{scanned: 5, total: 10, want: 0.5},
		{scanned: 20, total: 10, want: 0.99},
		{done: 1, devices: 2, want: 0.5},
		{done: 2, devices: 2, want: 0.99},
		{},
	} {
		if got := rescanProgress(tc.scanned, tc.total, tc.done, tc.devices); got != tc.want {
			t.Errorf("rescanProgress(%d, %d, %d, %d) = %v, want %v", tc.scanned, tc.total, tc.done, tc.devices, got, tc.want)
		}
	}
}

// TestMusicChangesDebounces folds a burst of changes into one event per
// device, and flush publishes at once in place of the waiting one.
func TestMusicChangesDebounces(t *testing.T) {
	bus := eventbus.New()
	events, unsub := bus.Subscribe("test")
	defer unsub()
	changes := newMusicChanges(bus, 50*time.Millisecond)
	for range 10 {
		changes.changed("")
		changes.changed(musicUSB)
	}
	got := map[string]int{}
	timeout := time.After(300 * time.Millisecond)
collect:
	for {
		select {
		case evt := <-events:
			got[evt.DeviceSerial]++
		case <-timeout:
			break collect
		}
	}
	if got[""] != 1 || got[musicUSB] != 1 || len(got) != 2 {
		t.Fatalf("events per device = %v, want one each", got)
	}

	changes.changed("")
	changes.flush("")
	if evt := <-events; evt.Kind != eventbus.EventMusicLibraryChanged || evt.DeviceSerial != "" {
		t.Fatalf("event = %+v", evt)
	}
	select {
	case evt := <-events:
		t.Fatalf("flush left the waiting change to fire: %+v", evt)
	case <-time.After(150 * time.Millisecond):
	}
}

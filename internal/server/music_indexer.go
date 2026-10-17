package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"maps"
	"slices"
	"sync"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// musicRescanKind is the jobutil kind of a full music library scan: every
// device, through musicutil.BackfillDevice. It is queued on first start and
// by an admin from Settings.
const musicRescanKind = "music_rescan"

const (
	// musicChangedDelay is the least time between two music_library_changed
	// events for one device while changes keep landing.
	musicChangedDelay = 2 * time.Second
	// musicFolderSettle is how long the indexer gathers folder events before
	// it backfills the devices they touched, so a burst of uploads costs one
	// walk.
	musicFolderSettle = 2 * time.Second
	// musicBackfillTimeout bounds one pass the indexer runs itself. A pass
	// reads only changed files, so it is mostly a walk; the rescan job has no
	// bound but its own cancel.
	musicBackfillTimeout = 30 * time.Minute
)

// errFoundAudio stops a walk at the first audio file.
var errFoundAudio = errors.New("found an audio file")

// musicIndexer keeps the music library in step with the file tree (#2982,
// docs/architecture/music-library.md). It is a queued bus subscriber, like the
// content indexer:
//
//	upload     → a file is read into the library; a folder (an upload's root,
//	             a restored or extracted folder) marks its device for a backfill
//	new_folder → the same as a folder upload
//	delete     → drop the rows at and under the path
//	move       → rewrite the rows' paths without reading a file
//	resync     → backfill every device
//
// A backfill reads only the files whose size, mtime or scanner version
// changed. A drive that appears is backfilled, and one that goes away loses
// its rows. Every change publishes music_library_changed for its device,
// debounced by musicChanges.
//
// Indexing is best-effort: failures are logged, never surfaced, since a
// rescan rebuilds the library from the files.
type musicIndexer struct {
	db       *sql.DB
	registry vfs.Registry
	bus      *eventbus.Bus
	jobs     *jobutil.Queue
	changes  *musicChanges
	// settle is musicFolderSettle; tests shorten it.
	settle time.Duration

	// scanMu serializes whole-device passes, so the rescan job, a drive
	// appearing and the event loop never walk one device twice at once.
	scanMu sync.Mutex

	// dirty is the devices a folder event touched since the last backfill.
	// Only the event loop reads or writes it.
	dirty map[string]bool

	// devicesMu guards known, the devices whose namespaces were registered at
	// the last sync.
	devicesMu sync.Mutex
	known     map[string]bool
}

// newMusicIndexer builds the indexer over the server's dependencies. Nothing
// runs until run is called; rescanHandler can be registered before that.
func newMusicIndexer(deps deputil.Dependencies) *musicIndexer {
	m := &musicIndexer{
		registry: deps.VFSRegistry(),
		bus:      deps.EventBus(),
		jobs:     deps.JobQueue(),
		changes:  newMusicChanges(deps.EventBus(), musicChangedDelay),
		settle:   musicFolderSettle,
		dirty:    map[string]bool{},
		known:    map[string]bool{},
	}
	if conn := deps.Database(); conn != nil {
		m.db = conn.Db
	}
	for serial := range vfs.FilesNamespaces(m.registry) {
		m.known[serial] = true
	}
	return m
}

// run subscribes to the bus, brings the library in step with the files
// already on disk, and then applies events until the bus closes the
// subscription. It subscribes before the startup pass, so nothing written
// during that pass is missed.
func (m *musicIndexer) run(deps deputil.Dependencies) {
	if m.bus == nil || m.db == nil {
		return
	}
	ch, unsub := m.bus.Subscribe("music-indexer")
	defer unsub()
	if svc := deps.StorageService(); svc != nil {
		svc.OnDevicesChanged(func() { go m.syncDevices() })
	}
	m.startup()

	var settle <-chan time.Time
	for {
		select {
		case evt, ok := <-ch:
			if !ok {
				return
			}
			m.handle(evt)
			if settle == nil && len(m.dirty) > 0 {
				settle = time.After(m.settle)
			}
		case <-settle:
			settle = nil
			m.backfillDirty()
		}
	}
}

// startup queues the rescan job on first start, when the library is empty
// and no scan is on record, so the first full read shows in the jobs badge.
// Any other start runs the incremental pass in place: it opens only files
// that changed while the server was down.
func (m *musicIndexer) startup() {
	ctx := context.Background()
	if m.firstStart(ctx) {
		if _, err := m.jobs.Enqueue(ctx, jobutil.EnqueueParams{
			Kind: musicRescanKind, Name: "Scan the music library", Params: struct{}{},
		}); err != nil {
			log.Printf("[music-indexer] queue the first scan: %v", err)
		} else {
			return
		}
	}
	m.backfillAll()
}

// firstStart reports whether the library has no rows and no music_rescan job
// is on record. A library that has rows was scanned whatever the jobs table
// says, since finished jobs are pruned.
func (m *musicIndexer) firstStart(ctx context.Context) bool {
	if m.jobs == nil {
		return false
	}
	count, err := db.NewQueries(m.db).CountMusicTracks(ctx, db.CountMusicTracksParams{})
	if err != nil || count > 0 {
		return false
	}
	listed, err := m.jobs.List(ctx, jobutil.ListParams{Kinds: []string{musicRescanKind}})
	return err == nil && len(listed.Jobs) == 0
}

// handle applies one bus event to the library.
func (m *musicIndexer) handle(evt eventbus.Event) {
	serial := evt.DeviceSerial
	switch evt.Kind {
	case eventbus.EventResync:
		// The bus dropped events while this loop was busy (#2753).
		m.backfillAll()
	case eventbus.EventUpload, eventbus.EventNewFolder:
		m.indexPath(serial, evt.Path)
	case eventbus.EventDelete:
		if evt.Path != "" {
			m.deletePath(serial, evt.Path)
		}
	case eventbus.EventMove:
		m.movePath(serial, evt.Path, evt.NewPath)
	}
}

// indexPath reads a file into the library. A folder marks its device for a
// backfill when it holds any audio: an upload names only the folder it
// landed in, and the backfill opens only what changed.
func (m *musicIndexer) indexPath(serial, relPath string) {
	fsys, ok := m.registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), musicutil.FileTimeout)
	defer cancel()
	relPath = accessutil.Canonical(relPath)
	fi, err := fsys.Stat(ctx, relPath)
	if err != nil {
		// Gone already: the delete or move that took it follows.
		return
	}
	if fi.IsDir {
		if holdsAudio(ctx, fsys, relPath) {
			m.dirty[serial] = true
		}
		return
	}
	res, err := musicutil.IndexTrack(musicutil.IndexTrackParams{
		Ctx: ctx, DB: m.db, FS: fsys, Serial: serial, RelPath: relPath,
	})
	if err != nil {
		log.Printf("[music-indexer] index %s: %v", relPath, err)
		return
	}
	if res.Indexed {
		m.changes.changed(serial)
	}
}

// holdsAudio reports whether any file at or under relPath is audio. The walk
// stops at the first one, so an upload of photos costs a walk of their
// folder and no backfill.
func holdsAudio(ctx context.Context, fsys vfs.VFS, relPath string) bool {
	err := vfs.Walk(ctx, fsys, relPath, func(fi vfs.FileInfo) error {
		if !fi.IsDir && musicutil.IsAudioPath(fi.Path) {
			return errFoundAudio
		}
		return nil
	})
	return errors.Is(err, errFoundAudio)
}

// deletePath drops the rows at and under relPath.
func (m *musicIndexer) deletePath(serial, relPath string) {
	if _, err := musicutil.DeletePath(musicutil.DeletePathParams{
		Ctx: context.Background(), DB: m.db, Serial: serial, RelPath: relPath,
	}); err != nil {
		log.Printf("[music-indexer] delete %s: %v", relPath, err)
		return
	}
	m.changes.changed(serial)
}

// movePath rewrites the rows under oldPath to newPath. A move that carried
// no rows is read as an upload of newPath, which covers a file renamed to an
// audio name; a file renamed away from one loses its row.
func (m *musicIndexer) movePath(serial, oldPath, newPath string) {
	if oldPath == "" {
		return
	}
	if newPath == "" {
		m.deletePath(serial, oldPath)
		return
	}
	res, err := musicutil.MovePath(musicutil.MovePathParams{
		Ctx: context.Background(), DB: m.db, Serial: serial, OldPath: oldPath, NewPath: newPath,
	})
	switch {
	case err != nil:
		log.Printf("[music-indexer] move %s to %s: %v", oldPath, newPath, err)
		m.dirty[serial] = true
	case res.Moved == 0:
		m.indexPath(serial, newPath)
	case musicutil.IsAudioPath(oldPath) && !musicutil.IsAudioPath(newPath):
		m.deletePath(serial, newPath)
	default:
		m.changes.changed(serial)
	}
}

// backfillDirty backfills every device a folder event marked.
func (m *musicIndexer) backfillDirty() {
	ctx, cancel := context.WithTimeout(context.Background(), musicBackfillTimeout)
	defer cancel()
	for _, serial := range slices.Sorted(maps.Keys(m.dirty)) {
		delete(m.dirty, serial)
		if fsys, ok := m.registry.Get(vfs.FilesNamespace(serial)); ok {
			_, _ = m.backfill(ctx, serial, fsys, nil) // backfill logs its own failure
		}
	}
}

// backfillAll backfills every device registered now.
func (m *musicIndexer) backfillAll() {
	ctx, cancel := context.WithTimeout(context.Background(), musicBackfillTimeout)
	defer cancel()
	namespaces := vfs.FilesNamespaces(m.registry)
	for _, serial := range slices.Sorted(maps.Keys(namespaces)) {
		_, _ = m.backfill(ctx, serial, namespaces[serial], nil) // backfill logs its own failure
	}
}

// backfill brings one device's rows in step with its files and announces
// the change when the pass read or dropped anything.
func (m *musicIndexer) backfill(ctx context.Context, serial string, fsys vfs.VFS, progress func(musicutil.BackfillDeviceResult)) (musicutil.BackfillDeviceResult, error) {
	m.scanMu.Lock()
	defer m.scanMu.Unlock()
	res, err := musicutil.BackfillDevice(musicutil.BackfillDeviceParams{
		Ctx: ctx, DB: m.db, FS: fsys, Serial: serial, Progress: progress,
	})
	if err != nil {
		log.Printf("[music-indexer] backfill %s: %v", vfs.FilesNamespace(serial), err)
	} else {
		log.Printf(
			"[music-indexer] backfill %s: scanned %d, read %d, unchanged %d, failed %d, dropped %d",
			vfs.FilesNamespace(serial), res.Scanned, res.Indexed, res.Unchanged, res.Failed, res.Deleted,
		)
	}
	if res.Indexed > 0 || res.Deleted > 0 {
		m.changes.flush(serial)
	}
	return res, err
}

// syncDevices backfills every device whose namespace appeared and drops the
// rows of every device whose namespace went away. The internal drive is
// never dropped.
func (m *musicIndexer) syncDevices() {
	m.devicesMu.Lock()
	defer m.devicesMu.Unlock()
	present := vfs.FilesNamespaces(m.registry)
	for serial := range m.known {
		if _, ok := present[serial]; ok || serial == "" {
			continue
		}
		delete(m.known, serial)
		if _, err := musicutil.DropDevice(musicutil.DropDeviceParams{
			Ctx: context.Background(), DB: m.db, Serial: serial,
		}); err != nil {
			log.Printf("[music-indexer] drop %s: %v", vfs.FilesNamespace(serial), err)
			continue
		}
		m.changes.flush(serial)
	}
	ctx, cancel := context.WithTimeout(context.Background(), musicBackfillTimeout)
	defer cancel()
	for _, serial := range slices.Sorted(maps.Keys(present)) {
		if m.known[serial] {
			continue
		}
		m.known[serial] = true
		_, _ = m.backfill(ctx, serial, present[serial], nil) // backfill logs its own failure
	}
}

// rescanHandler is the jobutil Handler for musicRescanKind, in its one lane.
func (m *musicIndexer) rescanHandler() jobutil.Handler {
	return jobutil.Handler{
		Run: func(ctx context.Context, _ json.RawMessage, report func(float64)) error {
			return m.rescan(ctx, report)
		},
	}
}

// rescan backfills every device and announces each one as it finishes, so a
// Music page showing "scanning" fetches again. Progress is the files walked
// over the size the library had when the scan began, or the share of
// devices done for a library that was empty.
func (m *musicIndexer) rescan(ctx context.Context, report func(float64)) error {
	total, err := db.NewQueries(m.db).CountMusicTracks(ctx, db.CountMusicTracksParams{})
	if err != nil {
		return err
	}
	namespaces := vfs.FilesNamespaces(m.registry)
	serials := slices.Sorted(maps.Keys(namespaces))
	scanned := 0
	var errs []error
	for i, serial := range serials {
		before := scanned
		res, err := m.backfill(ctx, serial, namespaces[serial], func(r musicutil.BackfillDeviceResult) {
			report(rescanProgress(before+r.Scanned, total, i, len(serials)))
		})
		scanned += res.Scanned
		if res.Indexed == 0 && res.Deleted == 0 {
			// backfill announced a pass that changed something; one that
			// changed nothing is still a scan that finished.
			m.changes.flush(serial)
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			return ctxErr
		}
		if err != nil {
			errs = append(errs, err)
		}
		report(rescanProgress(scanned, total, i+1, len(serials)))
	}
	return errors.Join(errs...)
}

// rescanProgress is a scan's progress: scanned over the library's size when
// it began, held below 1 until the job finishes, or devicesDone over devices
// when the library was empty.
func rescanProgress(scanned int, total int64, devicesDone, devices int) float64 {
	if total > 0 {
		return min(float64(scanned)/float64(total), 0.99)
	}
	if devices == 0 {
		return 0
	}
	return min(float64(devicesDone)/float64(devices), 0.99)
}

// musicChanges publishes music_library_changed for a device at most once per
// delay while changes keep landing: the first change arms a timer, and later
// ones ride it. flush publishes at once, for a scan that finished.
type musicChanges struct {
	bus   *eventbus.Bus
	delay time.Duration

	mu      sync.Mutex
	pending map[string]*time.Timer
}

func newMusicChanges(bus *eventbus.Bus, delay time.Duration) *musicChanges {
	return &musicChanges{bus: bus, delay: delay, pending: map[string]*time.Timer{}}
}

// changed notes that a device's rows changed.
func (c *musicChanges) changed(serial string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.pending[serial]; ok {
		return
	}
	var timer *time.Timer
	// The callback takes mu before reading timer, and timer is set before
	// mu is released, so it always sees its own timer.
	timer = time.AfterFunc(c.delay, func() {
		c.mu.Lock()
		mine := c.pending[serial] == timer
		if mine {
			delete(c.pending, serial)
		}
		c.mu.Unlock()
		if mine {
			c.publish(serial)
		}
	})
	c.pending[serial] = timer
}

// flush publishes for a device now, folding in any change still waiting.
func (c *musicChanges) flush(serial string) {
	c.mu.Lock()
	if timer, ok := c.pending[serial]; ok {
		timer.Stop()
		delete(c.pending, serial)
	}
	c.mu.Unlock()
	c.publish(serial)
}

func (c *musicChanges) publish(serial string) {
	if c.bus != nil {
		c.bus.Publish(eventbus.Event{Kind: eventbus.EventMusicLibraryChanged, DeviceSerial: serial})
	}
}

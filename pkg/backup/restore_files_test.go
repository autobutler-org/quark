package backup

import (
	"context"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// restoreFixture is a backup drive BACKUP-1 holding two runs, each a
// snapshot of the internal drive, of USB-ABCDEFGH-1 and of a drive that is
// gone, and a newer partial run; and the two attached drives, empty. The
// drive lists folder names ending in "/", as a real drive does (#4043).
type restoreFixture struct {
	database *db.DatabaseSqlc
	registry vfs.Registry
	queue    *jobutil.Queue
	backup   vfs.VFS
	internal vfs.VFS
	usb      vfs.VFS
}

func newRestoreFixture(t *testing.T) restoreFixture {
	t.Helper()
	database := dbtest.NewDB(t)
	f := restoreFixture{
		database: database,
		registry: vfs.NewRegistry(),
		queue:    jobutil.NewQueue(jobutil.NewQueueParams{Database: database}),
		backup:   slashVFS{vfs.NewMemVFS(vfs.FilesNamespace("BACKUP-1"))},
		internal: vfs.NewMemVFS(vfs.FilesNamespace("")),
		usb:      vfs.NewMemVFS(vfs.FilesNamespace("USB-ABCDEFGH-1")),
	}
	for serial, fsys := range map[string]vfs.VFS{"BACKUP-1": f.backup, "": f.internal, "USB-ABCDEFGH-1": f.usb} {
		if err := f.registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	f.queue.Register(jobutil.RegisterParams{Kind: RestoreKind, Handler: NewRestoreHandler(NewRestoreHandlerParams{Registry: f.registry})})
	setRole(t, database, "BACKUP-1", "snapshot-backup")

	// Folder names a restore could not parse a serial out of: the manifest
	// says which drive each came from.
	drives := []ManifestDrive{
		{Folder: "Built-in storage", Serial: "", Name: "Pi"},
		{Folder: "Photos (USB USB-ABCD)", Serial: "USB-ABCDEFGH-1", Name: "Photos"},
		{Folder: "Old Drive (USB GONE1234)", Serial: "GONE12345678", Name: "Old Drive"},
	}
	at := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	putRun(t, f.backup, olderRun, at, drives, map[string]string{
		"Built-in storage/docs/a.txt":       "old a",
		"Photos (USB USB-ABCD)/2024/b.jpg":  "old b",
		"Old Drive (USB GONE1234)/c.txt":    "old c",
		"Photos (USB USB-ABCD)/2023/z.jpg":  "z",
		"Built-in storage/docs/removed.txt": "removed",
	})
	putRun(t, f.backup, newestRun, at.Add(24*time.Hour), drives, map[string]string{
		"Built-in storage/docs/a.txt":      "a",
		"Photos (USB USB-ABCD)/2024/b.jpg": "b",
		"Old Drive (USB GONE1234)/c.txt":   "c",
	})
	putRun(t, f.backup, ".2026-11-03 08.00.partial", at.Add(48*time.Hour), drives[:1], map[string]string{
		"Built-in storage/docs/half.txt": "half",
	})
	return f
}

const (
	olderRun  = "2026-11-01 08.00"
	newestRun = "2026-11-02 08.00"
)

func setRole(t *testing.T, database *db.DatabaseSqlc, serial, role string) {
	t.Helper()
	if err := database.Queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{DeviceSerial: serial, Role: role}); err != nil {
		t.Fatal(err)
	}
}

func putFile(t *testing.T, fsys vfs.VFS, p, content string) {
	t.Helper()
	ctx := context.Background()
	if dir := p[:max(strings.LastIndex(p, "/"), 0)]; dir != "" {
		if err := fsys.MkdirAll(ctx, dir); err != nil {
			t.Fatal(err)
		}
	}
	if err := fsys.Write(ctx, p, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
		t.Fatalf("write %s: %v", p, err)
	}
}

func readFile(t *testing.T, fsys vfs.VFS, p string) string {
	t.Helper()
	f, err := fsys.Open(context.Background(), p)
	if err != nil {
		t.Fatalf("open %s: %v", p, err)
	}
	defer f.Close()
	b, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func (f restoreFixture) start(missingToBuiltIn bool) (StartRestoreFilesResult, error) {
	return f.startRun("", missingToBuiltIn)
}

func (f restoreFixture) startRun(run string, missingToBuiltIn bool) (StartRestoreFilesResult, error) {
	return StartRestoreFiles(StartRestoreFilesParams{
		Ctx:              context.Background(),
		Queries:          f.database.Queries,
		Registry:         f.registry,
		Queue:            f.queue,
		BackupSerial:     "BACKUP-1",
		MissingToBuiltIn: missingToBuiltIn,
		Run:              run,
	})
}

func TestStartRestoreFiles_RefusesADriveWithoutTheSnapshotRole(t *testing.T) {
	f := newRestoreFixture(t)
	for _, role := range []string{"unassigned", "default-storage"} {
		setRole(t, f.database, "BACKUP-1", role)
		if _, err := f.start(true); !errors.Is(err, ErrRestoreRoleRequired) {
			t.Errorf("restore from a %q drive = %v, want ErrRestoreRoleRequired", role, err)
		}
	}
}

func TestStartRestoreFiles_PlansEachFolderOntoItsDevice(t *testing.T) {
	f := newRestoreFixture(t)
	result, err := f.start(false)
	if err != nil {
		t.Fatalf("StartRestoreFiles: %v", err)
	}
	want := []RestoreFolder{
		{Folder: "Built-in storage", TargetSerial: ""},
		{Folder: "Photos (USB USB-ABCD)", TargetSerial: "USB-ABCDEFGH-1"},
	}
	if !reflect.DeepEqual(result.Folders, want) {
		t.Errorf("folders = %+v, want %+v", result.Folders, want)
	}
	if !reflect.DeepEqual(result.Missing, []string{"Old Drive (USB GONE1234)"}) {
		t.Errorf("missing = %v, want the gone drive's folder", result.Missing)
	}
	if result.Run != newestRun {
		t.Errorf("run = %q, want the newest complete run %q", result.Run, newestRun)
	}
	if result.JobID == "" {
		t.Error("no job queued")
	}
}

// A restore takes the run it is asked for, and only a complete run the drive
// lists: never a partial one or a path out of backups/.
func TestStartRestoreFiles_ChoosesARun(t *testing.T) {
	f := newRestoreFixture(t)
	result, err := f.startRun(olderRun, false)
	if err != nil || result.Run != olderRun {
		t.Fatalf("restore of %s = %+v, %v", olderRun, result, err)
	}
	for _, run := range []string{".2026-11-03 08.00.partial", "../backups/" + olderRun, "../../etc", "nope"} {
		if _, err := f.startRun(run, false); !errors.Is(err, ErrRunNotFound) {
			t.Errorf("restore of %q = %v, want ErrRunNotFound", run, err)
		}
	}
}

func TestStartRestoreFiles_PutsAGoneDevicesFilesOnBuiltInStorage(t *testing.T) {
	f := newRestoreFixture(t)
	result, err := f.start(true)
	if err != nil {
		t.Fatalf("StartRestoreFiles: %v", err)
	}
	gone := RestoreFolder{Folder: "Old Drive (USB GONE1234)", TargetSerial: "", ToBuiltIn: true}
	if result.Folders[1] != gone || len(result.Missing) != 0 {
		t.Errorf("result = %+v, want %+v first and nothing missing", result, gone)
	}
}

func TestStartRestoreFiles_NothingToRestore(t *testing.T) {
	f := newRestoreFixture(t)
	empty := vfs.NewMemVFS(vfs.FilesNamespace("EMPTY"))
	if err := f.registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("EMPTY")}, empty); err != nil {
		t.Fatal(err)
	}
	setRole(t, f.database, "EMPTY", "snapshot-backup")
	_, err := StartRestoreFiles(StartRestoreFilesParams{
		Ctx: context.Background(), Queries: f.database.Queries, Registry: f.registry, Queue: f.queue, BackupSerial: "EMPTY",
	})
	if !errors.Is(err, ErrNoSnapshot) {
		t.Errorf("restore from an empty drive = %v, want ErrNoSnapshot", err)
	}

	// Only a gone drive's folder, and built-in storage not chosen.
	gone := vfs.NewMemVFS(vfs.FilesNamespace("GONE-ONLY"))
	if err := f.registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("GONE-ONLY")}, gone); err != nil {
		t.Fatal(err)
	}
	setRole(t, f.database, "GONE-ONLY", "snapshot-backup")
	putRun(t, gone, newestRun, time.Now(), []ManifestDrive{{Folder: "Old (USB GONE1234)", Serial: "GONE12345678"}},
		map[string]string{"Old (USB GONE1234)/x.txt": "x"})
	_, err = StartRestoreFiles(StartRestoreFilesParams{
		Ctx: context.Background(), Queries: f.database.Queries, Registry: f.registry, Queue: f.queue, BackupSerial: "GONE-ONLY",
	})
	if !errors.Is(err, ErrRestoreDevicesMissing) {
		t.Errorf("restore of only a gone drive = %v, want ErrRestoreDevicesMissing", err)
	}
}

func TestStartRestoreFiles_UnknownDrive(t *testing.T) {
	f := newRestoreFixture(t)
	setRole(t, f.database, "NOPE", "snapshot-backup")
	_, err := StartRestoreFiles(StartRestoreFilesParams{
		Ctx: context.Background(), Queries: f.database.Queries, Registry: f.registry, Queue: f.queue, BackupSerial: "NOPE",
	})
	if err == nil {
		t.Fatal("restore from a drive that is not attached succeeded")
	}
}

func TestRestoreFiles_CopiesBackAndKeepsWhatIsThere(t *testing.T) {
	f := newRestoreFixture(t)
	// A file that changed since the snapshot stays as it is now.
	putFile(t, f.internal, "docs/a.txt", "edited")
	putFile(t, f.internal, "docs/live.txt", "live")
	bus := eventbus.New()
	events, unsub := bus.Subscribe("test")
	defer unsub()

	result, err := RestoreFiles(RestoreFilesParams{
		Ctx:          context.Background(),
		Registry:     f.registry,
		BackupSerial: "BACKUP-1",
		Run:          newestRun,
		Folders: []RestoreFolder{
			{Folder: "Old Drive (USB GONE1234)", ToBuiltIn: true},
			{Folder: "Photos (USB USB-ABCD)", TargetSerial: "USB-ABCDEFGH-1"},
			{Folder: "Built-in storage"},
		},
		EventBus: bus,
	})
	if err != nil {
		t.Fatalf("RestoreFiles: %v", err)
	}
	if result.FilesCopied != 2 || result.FilesKept != 1 || result.BytesCopied != 2 {
		t.Errorf("result = %+v, want 2 copied (2 bytes), 1 kept", result)
	}
	if got := readFile(t, f.usb, "2024/b.jpg"); got != "b" {
		t.Errorf("usb 2024/b.jpg = %q", got)
	}
	if got := readFile(t, f.internal, "Old Drive (USB GONE1234)/c.txt"); got != "c" {
		t.Errorf("built-in Old Drive (USB GONE1234)/c.txt = %q", got)
	}
	if got := readFile(t, f.internal, "docs/a.txt"); got != "edited" {
		t.Errorf("docs/a.txt = %q, want the live edit kept", got)
	}
	if got := readFile(t, f.internal, "docs/live.txt"); got != "live" {
		t.Errorf("docs/live.txt = %q, want it untouched", got)
	}

	uploads := map[string]bool{}
	for len(events) > 0 {
		evt := <-events
		if evt.Kind == eventbus.EventUpload {
			uploads[evt.DeviceSerial+":"+evt.Path] = true
		}
	}
	for _, want := range []string{"USB-ABCDEFGH-1:2024/b.jpg", ":Old Drive (USB GONE1234)/c.txt"} {
		if !uploads[want] {
			t.Errorf("no upload event for %s; got %v", want, uploads)
		}
	}
}

func TestRestoreFiles_ACanceledRestoreLeavesTheTarget(t *testing.T) {
	f := newRestoreFixture(t)
	putFile(t, f.internal, "docs/live.txt", "live")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := RestoreFiles(RestoreFilesParams{
		Ctx: ctx, Registry: f.registry, BackupSerial: "BACKUP-1", Run: newestRun,
		Folders: []RestoreFolder{{Folder: "Built-in storage"}},
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("RestoreFiles = %v, want context.Canceled", err)
	}
	if got := readFile(t, f.internal, "docs/live.txt"); got != "live" {
		t.Errorf("docs/live.txt = %q after a failed restore", got)
	}
}

// The queued job restores the run it was started on, here the older one.
func TestRestoreFiles_RestoresTheChosenRun(t *testing.T) {
	f := newRestoreFixture(t)
	result, err := RestoreFiles(RestoreFilesParams{
		Ctx: context.Background(), Registry: f.registry, BackupSerial: "BACKUP-1", Run: olderRun,
		Folders: []RestoreFolder{{Folder: "Built-in storage"}, {Folder: "Photos (USB USB-ABCD)", TargetSerial: "USB-ABCDEFGH-1"}},
	})
	if err != nil {
		t.Fatalf("RestoreFiles: %v", err)
	}
	if result.FilesCopied != 4 {
		t.Errorf("copied %d files, want the older run's 4", result.FilesCopied)
	}
	if got := readFile(t, f.internal, "docs/a.txt"); got != "old a" {
		t.Errorf("docs/a.txt = %q, want the older run's", got)
	}
	if got := readFile(t, f.usb, "2023/z.jpg"); got != "z" {
		t.Errorf("2023/z.jpg = %q", got)
	}
}

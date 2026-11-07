package backup

import (
	"context"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// restoreFixture is a backup drive BACKUP-1 holding a snapshot of the
// internal drive and of USB-ABCDEFGH-1, and those two drives, empty.
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
		backup:   vfs.NewMemVFS(vfs.FilesNamespace("BACKUP-1")),
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

	putFile(t, f.backup, "internal/docs/a.txt", "a")
	putFile(t, f.backup, "Photos_USB-ABCD/2024/b.jpg", "b")
	putFile(t, f.backup, "Old Drive_GONE1234/c.txt", "c")
	putFile(t, f.backup, backupManifestFileForTest, "{}")
	return f
}

// backupManifestFileForTest is a file at the drive's root, which is no
// device's folder.
const backupManifestFileForTest = "backup_manifest.json"

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
	return StartRestoreFiles(StartRestoreFilesParams{
		Ctx:              context.Background(),
		Queries:          f.database.Queries,
		Registry:         f.registry,
		Queue:            f.queue,
		BackupSerial:     "BACKUP-1",
		MissingToBuiltIn: missingToBuiltIn,
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
		{Folder: "Photos_USB-ABCD", TargetSerial: "USB-ABCDEFGH-1"},
		{Folder: "internal", TargetSerial: ""},
	}
	if !reflect.DeepEqual(result.Folders, want) {
		t.Errorf("folders = %+v, want %+v", result.Folders, want)
	}
	if !reflect.DeepEqual(result.Missing, []string{"Old Drive_GONE1234"}) {
		t.Errorf("missing = %v, want the gone drive's folder", result.Missing)
	}
	if result.JobID == "" {
		t.Error("no job queued")
	}
}

func TestStartRestoreFiles_PutsAGoneDevicesFilesOnBuiltInStorage(t *testing.T) {
	f := newRestoreFixture(t)
	result, err := f.start(true)
	if err != nil {
		t.Fatalf("StartRestoreFiles: %v", err)
	}
	gone := RestoreFolder{Folder: "Old Drive_GONE1234", TargetSerial: "", ToBuiltIn: true}
	if result.Folders[0] != gone || len(result.Missing) != 0 {
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
	putFile(t, gone, "Old_GONE1234/x.txt", "x")
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
		Folders: []RestoreFolder{
			{Folder: "Old Drive_GONE1234", ToBuiltIn: true},
			{Folder: "Photos_USB-ABCD", TargetSerial: "USB-ABCDEFGH-1"},
			{Folder: "internal"},
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
	if got := readFile(t, f.internal, "Old Drive_GONE1234/c.txt"); got != "c" {
		t.Errorf("built-in Old Drive_GONE1234/c.txt = %q", got)
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
	for _, want := range []string{"USB-ABCDEFGH-1:2024/b.jpg", ":Old Drive_GONE1234/c.txt"} {
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
		Ctx: ctx, Registry: f.registry, BackupSerial: "BACKUP-1",
		Folders: []RestoreFolder{{Folder: "internal"}},
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("RestoreFiles = %v, want context.Canceled", err)
	}
	if got := readFile(t, f.internal, "docs/live.txt"); got != "live" {
		t.Errorf("docs/live.txt = %q after a failed restore", got)
	}
}

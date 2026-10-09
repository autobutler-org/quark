package backup

import (
	"context"
	"errors"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// memNamespaces registers each in-memory namespace as the files namespace of
// the device with its serial, "" being the internal drive.
func memNamespaces(t *testing.T, namespaces map[string]vfs.VFS) vfs.Registry {
	t.Helper()
	reg := vfs.NewRegistry()
	for serial, fsys := range namespaces {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	return reg
}

// memWith returns a MemVFS holding files, keyed by path.
func memWith(t *testing.T, serial string, files map[string]string) *vfs.MemVFS {
	t.Helper()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(serial))
	for p, content := range files {
		if err := fsys.Write(t.Context(), p, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	return fsys
}

func assertMemContent(t *testing.T, fsys vfs.VFS, p, want string) {
	t.Helper()
	f, err := fsys.Open(t.Context(), p)
	if err != nil {
		t.Errorf("%s: %v", p, err)
		return
	}
	defer f.Close()
	got, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != want {
		t.Errorf("%s = %q, want %q", p, got, want)
	}
}

// brokenVFS serves every file as a stream that fails partway through, the
// way a drive unplugged mid-copy does.
type brokenVFS struct {
	*vfs.MemVFS
}

func (b brokenVFS) Open(ctx context.Context, p string) (vfs.File, error) {
	f, err := b.MemVFS.Open(ctx, p)
	if err != nil {
		return nil, err
	}
	return &brokenFile{File: f}, nil
}

type brokenFile struct {
	vfs.File
	read bool
}

func (f *brokenFile) Read(p []byte) (int, error) {
	if f.read {
		return 0, errors.New("device went away")
	}
	f.read = true
	return f.File.Read(p[:1])
}

// An upload event names the folder the file landed in, not the file, so the
// mirror copies what that folder holds (#2649).
func TestSyncWorker_UploadEventForAFolderMirrorsItsFiles(t *testing.T) {
	src := memWith(t, "", map[string]string{"docs/a.txt": "a", "docs/b.txt": "b"})
	if err := src.MkdirAll(t.Context(), "docs/sub"); err != nil {
		t.Fatal(err)
	}
	dst := vfs.NewMemVFS(vfs.FilesNamespace(targetSerial))
	w := newSyncWorker(memNamespaces(t, map[string]vfs.VFS{"": src, targetSerial: dst}), targetSerial)

	w.handleEvent(t.Context(), eventbus.Event{Kind: eventbus.EventUpload, Path: "docs"})

	assertMemContent(t, dst, "docs/a.txt", "a")
	assertMemContent(t, dst, "docs/b.txt", "b")
	if info, err := dst.Stat(t.Context(), "docs/sub"); err != nil || !info.IsDir {
		t.Errorf("docs/sub not mirrored: %v", err)
	}
	if n := w.QueueLength(); n != 0 {
		t.Errorf("queued %d retries, want 0", n)
	}
}

// A file the target already holds an up-to-date copy of is not copied again.
func TestSyncWorker_UploadEventSkipsUpToDateFiles(t *testing.T) {
	src := memWith(t, "", map[string]string{"docs/a.txt": "a"})
	dst := memWith(t, targetSerial, map[string]string{"docs/a.txt": "x"})
	w := newSyncWorker(memNamespaces(t, map[string]vfs.VFS{"": src, targetSerial: dst}), targetSerial)

	w.syncPath(t.Context(), "docs")

	assertMemContent(t, dst, "docs/a.txt", "x")
}

func TestSyncWorker_ResyncBetweenMemNamespaces(t *testing.T) {
	src := memWith(t, "", map[string]string{"a.txt": "a", "deep/er/b.txt": "b"})
	dst := memWith(t, targetSerial, map[string]string{"only-on-target.txt": "keep"})
	w := newSyncWorker(memNamespaces(t, map[string]vfs.VFS{"": src, targetSerial: dst}), targetSerial)

	w.handleEvent(t.Context(), eventbus.Event{Kind: eventbus.EventResync})

	assertMemContent(t, dst, "a.txt", "a")
	assertMemContent(t, dst, "deep/er/b.txt", "b")
	assertMemContent(t, dst, "only-on-target.txt", "keep")
}

func TestSyncWorker_MoveOnMemTarget(t *testing.T) {
	src := vfs.NewMemVFS(vfs.FilesNamespace(""))
	dst := memWith(t, targetSerial, map[string]string{"old/f.txt": "f"})
	w := newSyncWorker(memNamespaces(t, map[string]vfs.VFS{"": src, targetSerial: dst}), targetSerial)

	w.handleEvent(t.Context(), eventbus.Event{Kind: eventbus.EventMove, Path: "old/f.txt", NewPath: "new/f.txt"})

	assertMemContent(t, dst, "new/f.txt", "f")
	if _, err := dst.Stat(t.Context(), "old/f.txt"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("old/f.txt still on target: %v", err)
	}
}

// A default-storage drive that is not plugged in has no namespace: every
// event is a no-op, and nothing is queued to retry against it.
func TestSyncWorker_UnattachedTargetDoesNothing(t *testing.T) {
	src := memWith(t, "", map[string]string{"docs/a.txt": "a"})
	w := newSyncWorker(memNamespaces(t, map[string]vfs.VFS{"": src}), "unplugged")

	for _, evt := range []eventbus.Event{
		{Kind: eventbus.EventUpload, Path: "docs"},
		{Kind: eventbus.EventNewFolder, Path: "docs"},
		{Kind: eventbus.EventMove, Path: "docs/a.txt", NewPath: "docs/b.txt"},
		{Kind: eventbus.EventResync},
	} {
		w.handleEvent(t.Context(), evt)
	}

	if n := w.QueueLength(); n != 0 {
		t.Errorf("queued %d retries for an unplugged drive, want 0", n)
	}
	assertMemContent(t, src, "docs/a.txt", "a")
}

// A copy cut short leaves nothing under the real name on the target, and is
// queued to retry (#2649).
func TestSyncWorker_InterruptedCopyLeavesNoPartialFile(t *testing.T) {
	src := brokenVFS{memWith(t, "", map[string]string{"big.bin": "0123456789"})}
	dstDir := t.TempDir()
	dst := localFS(t, dstDir)
	w := newSyncWorker(memNamespaces(t, map[string]vfs.VFS{"": src, targetSerial: dst}), targetSerial)

	w.syncPath(t.Context(), "big.bin")

	entries, err := os.ReadDir(dstDir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		t.Errorf("target holds %s after a failed copy", e.Name())
	}
	if n := w.QueueLength(); n != 1 {
		t.Errorf("queued %d retries, want 1", n)
	}
}

func TestSnapshotBackup_BetweenMemNamespaces(t *testing.T) {
	internal := memWith(t, "", map[string]string{"photos/a.jpg": "photo-a"})
	usb := memWith(t, "USB-1", map[string]string{"docs/b.txt": "doc-b"})
	target := vfs.NewMemVFS(vfs.FilesNamespace("BACKUP"))
	store := NewInMemoryBackupJobStore()
	job := newJob("BACKUP")
	if err := store.Create(t.Context(), job); err != nil {
		t.Fatal(err)
	}

	err := SnapshotBackup(t.Context(), SnapshotBackupParams{
		TargetDeviceSerial: "BACKUP",
		Job:                job,
		Store:              store,
	}, []SourceDevice{
		{Name: "Internal", Files: internal},
		{Name: "Stick", Serial: "USB-1", Files: usb},
	}, target)
	if err != nil {
		t.Fatalf("SnapshotBackup: %v", err)
	}

	assertMemContent(t, target, "internal/photos/a.jpg", "photo-a")
	assertMemContent(t, target, "Stick_USB-1/docs/b.txt", "doc-b")
	if job.FilesCopied != 2 || job.BytesCopied != int64(len("photo-a")+len("doc-b")) {
		t.Errorf("copied %d files, %d bytes", job.FilesCopied, job.BytesCopied)
	}

	result, err := VerifyBackup(VerifyBackupParams{
		Ctx:          t.Context(),
		Registry:     memNamespaces(t, map[string]vfs.VFS{"": internal, "BACKUP": target}),
		DeviceSerial: "BACKUP",
		Full:         true,
	})
	if err != nil {
		t.Fatalf("VerifyBackup: %v", err)
	}
	if result.OK != 2 || len(result.Missing)+len(result.Corrupted)+len(result.Added) != 0 {
		t.Errorf("verify = %+v, want 2 OK and nothing else", result)
	}
}

// A snapshot copy cut short fails the job and leaves nothing under the real
// name on the target.
func TestSnapshotBackup_InterruptedCopyLeavesNoPartialFile(t *testing.T) {
	src := brokenVFS{memWith(t, "USB-1", map[string]string{"big.bin": "0123456789"})}
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("BACKUP")
	if err := store.Create(t.Context(), job); err != nil {
		t.Fatal(err)
	}

	err := SnapshotBackup(t.Context(), SnapshotBackupParams{
		TargetDeviceSerial: "BACKUP",
		Job:                job,
		Store:              store,
	}, []SourceDevice{{Name: "Stick", Serial: "USB-1", Files: src}}, target.VFS)
	if err == nil {
		t.Fatal("SnapshotBackup succeeded copying from a failing drive")
	}
	if job.Status != BackupStatusFailed {
		t.Errorf("status = %s, want FAILED", job.Status)
	}
	entries, err := os.ReadDir(target.FilesDir + "/Stick_USB-1")
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	for _, e := range entries {
		t.Errorf("target holds %s after a failed copy", e.Name())
	}
}

func TestVerifyBackup_UnattachedDeviceIsNotFound(t *testing.T) {
	_, err := VerifyBackup(VerifyBackupParams{
		Ctx:          t.Context(),
		Registry:     memNamespaces(t, map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace(""))}),
		DeviceSerial: "unplugged",
	})
	var notFound *fileutil.NotFoundError
	if !errors.As(err, &notFound) || !errors.Is(err, fileutil.ErrNoDevice) {
		t.Fatalf("VerifyBackup on an unplugged drive = %v, want a NotFoundError for ErrNoDevice", err)
	}
}

func TestStartSnapshotBackup_UnattachedTargetIsNotManaged(t *testing.T) {
	const serial = "USB-001"
	ctx := t.Context()
	queries := newRolesQueries(t)
	if err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{
		DeviceSerial: serial,
		Role:         "snapshot-backup",
	}); err != nil {
		t.Fatalf("seed role: %v", err)
	}

	_, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                ctx,
		Queries:            queries,
		Registry:           memNamespaces(t, map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace(""))}),
		Store:              NewInMemoryBackupJobStore(),
		TargetDeviceSerial: serial,
	})
	if !errors.Is(err, ErrTargetNotManaged) {
		t.Fatalf("StartSnapshotBackup onto an unplugged drive = %v, want ErrTargetNotManaged", err)
	}
}

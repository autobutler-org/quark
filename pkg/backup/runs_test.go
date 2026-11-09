package backup

import (
	"context"
	"errors"
	"os"
	"path"
	"path/filepath"
	"reflect"
	"regexp"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// slashVFS ends every folder's name in a listing with "/", as the files
// namespace of a real drive does (#4043).
type slashVFS struct{ vfs.VFS }

func (s slashVFS) List(ctx context.Context, p string, filter *vfs.ListFilter) ([]vfs.FileInfo, error) {
	entries, err := s.VFS.List(ctx, p, filter)
	for i := range entries {
		if entries[i].IsDir {
			entries[i].Name += "/"
		}
	}
	return entries, err
}

// refusingLinker is a drive whose filesystem has no hard links, as FAT and
// exFAT have none.
type refusingLinker struct{ vfs.VFS }

func (refusingLinker) Link(context.Context, string, string) error {
	return errors.New("operation not permitted")
}

// putRun puts a complete run on fsys: files under its folder, keyed by their
// path in the run, and a manifest naming drives.
func putRun(t *testing.T, fsys vfs.VFS, folder string, completedAt time.Time, drives []ManifestDrive, files map[string]string) {
	t.Helper()
	ctx := context.Background()
	dir := runDir(folder)
	if err := fsys.MkdirAll(ctx, dir); err != nil {
		t.Fatal(err)
	}
	for p, content := range files {
		putFile(t, fsys, path.Join(dir, p), content)
	}
	m, err := GenerateManifest(ctx, fsys, dir)
	if err != nil {
		t.Fatal(err)
	}
	m.CompletedAt, m.Drives = completedAt, drives
	if err := WriteManifest(ctx, m, fsys, dir); err != nil {
		t.Fatal(err)
	}
}

// onlyRun is the one complete run on fsys.
func onlyRun(t *testing.T, fsys vfs.VFS) Run {
	t.Helper()
	runs, err := ListRuns(context.Background(), fsys)
	if err != nil {
		t.Fatal(err)
	}
	if len(runs) != 1 {
		t.Fatalf("runs = %+v, want one", runs)
	}
	return runs[0]
}

// runHostDir is the host folder of the one complete run on target.
func runHostDir(t *testing.T, target localTarget) string {
	t.Helper()
	return filepath.Join(target.FilesDir, BackupsDir, onlyRun(t, target).Folder)
}

func snapshot(t *testing.T, target vfs.VFS, sources ...SourceDevice) *BackupJob {
	t.Helper()
	job := newJob("TARGET")
	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{TargetDeviceSerial: "TARGET", Job: job}, sources, target); err != nil {
		t.Fatalf("SnapshotBackup: %v", err)
	}
	return job
}

// A run is a dated folder under backups/ with a readable folder per drive,
// and its manifest maps each folder to the drive it came from.
func TestSnapshotBackup_WritesADatedRunUnderBackups(t *testing.T) {
	builtIn := makeSource(t, "Pi", "", map[string]string{"data.txt": "internal"})
	usb := makeSource(t, "Quark", "90C82C65ABCD", map[string]string{"photos/a.jpg": "photo"})
	target := makeTarget(t)
	job := snapshot(t, target.VFS, builtIn, usb)

	run := onlyRun(t, target)
	if !regexp.MustCompile(`^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}$`).MatchString(run.Folder) {
		t.Errorf("run folder %q is not YYYY-MM-DD HH.MM", run.Folder)
	}
	dir := filepath.Join(target.FilesDir, BackupsDir, run.Folder)
	assertFileContent(t, filepath.Join(dir, "Built-in storage", "data.txt"), "internal")
	assertFileContent(t, filepath.Join(dir, "Quark (USB 90C82C65)", "photos", "a.jpg"), "photo")
	want := []ManifestDrive{
		{Folder: "Built-in storage", Serial: "", Name: "Pi"},
		{Folder: "Quark (USB 90C82C65)", Serial: "90C82C65ABCD", Name: "Quark"},
	}
	if !reflect.DeepEqual(run.Drives, want) {
		t.Errorf("drives = %+v, want %+v", run.Drives, want)
	}
	if !run.CompletedAt.Equal(*job.CompletedAt) {
		t.Errorf("run completed at %v, the job at %v", run.CompletedAt, job.CompletedAt)
	}
	entries, err := os.ReadDir(filepath.Join(target.FilesDir, BackupsDir))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Errorf("backups/ holds %d entries, want the run alone", len(entries))
	}
}

func TestNewRunFolder_SuffixesASharedMinute(t *testing.T) {
	ctx := context.Background()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace("B"))
	at := time.Date(2026, 11, 7, 21, 57, 30, 0, time.Local)
	if got, err := newRunFolder(ctx, fsys, at); err != nil || got != "2026-11-07 21.57" {
		t.Errorf("first run = %q, %v", got, err)
	}
	for _, p := range []string{runDir("2026-11-07 21.57"), partialDir("2026-11-07 21.57 (2)")} {
		if err := fsys.MkdirAll(ctx, p); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := newRunFolder(ctx, fsys, at); err != nil || got != "2026-11-07 21.57 (3)" {
		t.Errorf("third run in the minute = %q, %v; want the (3) suffix", got, err)
	}
}

// A run that fails or is canceled removes its partial folder, and the next
// run removes one a stopped Quark left behind.
func TestSnapshotBackup_LeavesNoPartialFolder(t *testing.T) {
	canceled, cancel := context.WithCancel(context.Background())
	cancel()
	for _, tc := range []struct {
		name string
		ctx  context.Context
		src  SourceDevice
	}{
		{"failed copy", context.Background(), SourceDevice{Name: "Stick", Serial: "USB-1", Files: brokenVFS{memWith(t, "USB-1", map[string]string{"big.bin": "0123456789"})}}},
		{"canceled", canceled, makeSource(t, "Drive", "SER1", map[string]string{"a.txt": "a"})},
	} {
		t.Run(tc.name, func(t *testing.T) {
			target := makeTarget(t)
			if err := SnapshotBackup(tc.ctx, SnapshotBackupParams{Job: newJob("TARGET")}, []SourceDevice{tc.src}, target.VFS); err == nil {
				t.Fatal("SnapshotBackup succeeded")
			}
			entries, err := os.ReadDir(filepath.Join(target.FilesDir, BackupsDir))
			if err != nil && !os.IsNotExist(err) {
				t.Fatal(err)
			}
			for _, e := range entries {
				t.Errorf("backups/ holds %s after a failed run", e.Name())
			}
		})
	}

	target := makeTarget(t)
	stale := filepath.Join(target.FilesDir, BackupsDir, ".2026-01-01 00.00.partial")
	if err := os.MkdirAll(stale, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stale, "half.bin"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	snapshot(t, target.VFS, makeSource(t, "Drive", "SER1", map[string]string{"a.txt": "a"}))
	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Errorf("a stale partial run is still there: %v", err)
	}
}

// A file unchanged since the previous run is the previous run's file, hard
// linked; a changed one is a new copy, and the old run keeps its own.
func TestSnapshotBackup_LinksWhatDidNotChange(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"same.txt": "same", "changed.txt": "old"})
	target := makeTarget(t)
	snapshot(t, target.VFS, src)
	if err := os.WriteFile(filepath.Join(hostRoot(t, src.Files), "changed.txt"), []byte("new content"), 0o644); err != nil {
		t.Fatal(err)
	}
	job := snapshot(t, target.VFS, src)
	if job.FilesSkipped != 1 || job.FilesCopied != 1 {
		t.Errorf("second run linked %d and copied %d, want 1 and 1", job.FilesSkipped, job.FilesCopied)
	}

	runs, err := ListRuns(context.Background(), target)
	if err != nil || len(runs) != 2 {
		t.Fatalf("runs = %+v, %v; want two", runs, err)
	}
	newer := filepath.Join(target.FilesDir, BackupsDir, runs[0].Folder, "Drive (USB SER1)")
	older := filepath.Join(target.FilesDir, BackupsDir, runs[1].Folder, "Drive (USB SER1)")
	if !sameFile(t, filepath.Join(newer, "same.txt"), filepath.Join(older, "same.txt")) {
		t.Error("an unchanged file was copied, not linked")
	}
	if sameFile(t, filepath.Join(newer, "changed.txt"), filepath.Join(older, "changed.txt")) {
		t.Error("a changed file was linked to its old copy")
	}
	assertFileContent(t, filepath.Join(newer, "changed.txt"), "new content")
	assertFileContent(t, filepath.Join(older, "changed.txt"), "old")
}

// hostRoot is the host path of a disk-backed namespace's root.
func hostRoot(t *testing.T, fsys vfs.VFS) string {
	t.Helper()
	p, err := fsys.(vfs.HostPather).HostPath(context.Background(), "")
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func sameFile(t *testing.T, a, b string) bool {
	t.Helper()
	ai, err := os.Stat(a)
	if err != nil {
		t.Fatal(err)
	}
	bi, err := os.Stat(b)
	if err != nil {
		t.Fatal(err)
	}
	return os.SameFile(ai, bi)
}

// A drive that cannot link gets a full copy of every file in every run.
func TestSnapshotBackup_CopiesWhereTheDriveCannotLink(t *testing.T) {
	for name, target := range map[string]vfs.VFS{
		"no link operation":     vfs.NewMemVFS(vfs.FilesNamespace("TARGET")),
		"filesystem refuses it": refusingLinker{makeTarget(t).VFS},
	} {
		t.Run(name, func(t *testing.T) {
			src := memWith(t, "SER1", map[string]string{"a.txt": "a"})
			source := SourceDevice{Name: "Drive", Serial: "SER1", Files: src}
			snapshot(t, target, source)
			job := snapshot(t, target, source)
			if job.FilesCopied != 1 || job.FilesSkipped != 0 {
				t.Errorf("second run copied %d and linked %d, want a full copy", job.FilesCopied, job.FilesSkipped)
			}
			runs, err := ListRuns(context.Background(), target)
			if err != nil || len(runs) != 2 {
				t.Fatalf("runs = %+v, %v; want two", runs, err)
			}
			for _, run := range runs {
				assertMemContent(t, target, path.Join(runDir(run.Folder), "Drive (USB SER1)", "a.txt"), "a")
			}
		})
	}
}

// A source's own backups/ folder is never copied, so built-in storage that
// holds backups is not backed up into itself. A backups folder deeper down is
// the user's and is copied.
func TestSnapshotBackup_LeavesOutEverySourcesBackups(t *testing.T) {
	builtIn := memWith(t, "", map[string]string{
		"docs/a.txt": "a",
		"backups/2026-01-01 00.00/Built-in storage/x.txt": "old run",
		"photos/backups/keep.txt":                         "keep",
	})
	target := vfs.NewMemVFS(vfs.FilesNamespace("TARGET"))
	job := snapshot(t, target, SourceDevice{Name: "Pi", Files: builtIn})
	if job.TotalFiles != 2 || job.FilesCopied != 2 {
		t.Errorf("counted %d and copied %d files, want 2 and 2", job.TotalFiles, job.FilesCopied)
	}
	dir := path.Join(runDir(onlyRun(t, target).Folder), "Built-in storage")
	assertMemContent(t, target, path.Join(dir, "docs/a.txt"), "a")
	assertMemContent(t, target, path.Join(dir, "photos/backups/keep.txt"), "keep")
	if _, err := target.Stat(context.Background(), path.Join(dir, BackupsDir)); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("the source's backups/ was copied: %v", err)
	}
}

// ListRuns reads a drive whose listing ends folder names with "/", leaves out
// partial runs and folders with no manifest, and lists newest first, each
// run sized by its manifest. A
// manifest's drive folder that is not one entry in the run is dropped.
func TestListRuns(t *testing.T) {
	mem := vfs.NewMemVFS(vfs.FilesNamespace("B"))
	older := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	newer := older.Add(24 * time.Hour)
	drives := []ManifestDrive{{Folder: "Built-in storage"}, {Folder: "../escape", Serial: "X"}, {Folder: ".hidden", Serial: "Y"}}
	putRun(t, mem, "2026-11-01 08.00", older, drives, map[string]string{"Built-in storage/a.txt": "a"})
	putRun(t, mem, "2026-11-02 08.00", newer, drives, map[string]string{"Built-in storage/a.txt": "a"})
	putRun(t, mem, ".2026-11-03 08.00.partial", newer.Add(time.Hour), drives, nil)
	if err := mem.MkdirAll(context.Background(), runDir("no manifest")); err != nil {
		t.Fatal(err)
	}

	runs, err := ListRuns(context.Background(), slashVFS{mem})
	if err != nil {
		t.Fatal(err)
	}
	want := []Run{
		{Folder: "2026-11-02 08.00", CompletedAt: newer, Drives: []ManifestDrive{{Folder: "Built-in storage"}}, SizeBytes: 1},
		{Folder: "2026-11-01 08.00", CompletedAt: older, Drives: []ManifestDrive{{Folder: "Built-in storage"}}, SizeBytes: 1},
	}
	if !reflect.DeepEqual(runs, want) {
		t.Errorf("runs = %+v\nwant %+v", runs, want)
	}

	if runs, err := ListRuns(context.Background(), vfs.NewMemVFS(vfs.FilesNamespace("E"))); err != nil || len(runs) != 0 {
		t.Errorf("a drive with no backups/ = %+v, %v; want none", runs, err)
	}
}

// Verify checks the newest complete run unless told which, and never a
// partial one or a path out of backups/.
func TestVerifyBackup_ChoosesARun(t *testing.T) {
	mem := vfs.NewMemVFS(vfs.FilesNamespace("BACKUP"))
	at := time.Date(2026, 11, 1, 8, 0, 0, 0, time.UTC)
	putRun(t, mem, "2026-11-01 08.00", at, nil, map[string]string{"Built-in storage/a.txt": "aaa"})
	putRun(t, mem, "2026-11-02 08.00", at.Add(24*time.Hour), nil, map[string]string{"Built-in storage/a.txt": "bbb"})
	putRun(t, mem, ".2026-11-03 08.00.partial", at.Add(48*time.Hour), nil, map[string]string{"Built-in storage/a.txt": "ccc"})
	// The older run's file goes bad after its manifest was written.
	putFile(t, mem, path.Join(runDir("2026-11-01 08.00"), "Built-in storage/a.txt"), "xyz")
	reg := memNamespaces(t, map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), "BACKUP": slashVFS{mem}})
	verify := func(run string) (*VerifyResult, error) {
		return VerifyBackup(VerifyBackupParams{Ctx: context.Background(), Registry: reg, DeviceSerial: "BACKUP", Full: true, Run: run})
	}

	result, err := verify("")
	if err != nil || result.Run != "2026-11-02 08.00" || result.OK != 1 {
		t.Errorf("verify of the newest run = %+v, %v", result, err)
	}
	result, err = verify("2026-11-01 08.00")
	if err != nil || result.Run != "2026-11-01 08.00" || len(result.Corrupted) != 1 {
		t.Errorf("verify of the older run = %+v, %v; want its file corrupted", result, err)
	}
	for _, run := range []string{".2026-11-03 08.00.partial", "../backups/2026-11-01 08.00", "nope"} {
		if _, err := verify(run); !errors.Is(err, ErrRunNotFound) {
			t.Errorf("verify of %q = %v, want ErrRunNotFound", run, err)
		}
	}

	empty := memNamespaces(t, map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), "BACKUP": vfs.NewMemVFS(vfs.FilesNamespace("BACKUP"))})
	if _, err := VerifyBackup(VerifyBackupParams{Ctx: context.Background(), Registry: empty, DeviceSerial: "BACKUP"}); !errors.Is(err, ErrNoManifest) {
		t.Errorf("verify of a drive with no run = %v, want ErrNoManifest", err)
	}
}

// The vault comes back from the run asked for, or the newest one.
func TestRestoreVault_ReadsTheChosenRun(t *testing.T) {
	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice", "bob")
	seedVault(t, source, vaultOwner{"alice", randomBytes(t, 32), []string{"a", "b"}})
	target := makeTarget(t)
	snap := func() {
		if err := SnapshotBackup(context.Background(), SnapshotBackupParams{Job: newJob("BACKUP-1"), LiveDB: source}, nil, target.VFS); err != nil {
			t.Fatal(err)
		}
	}
	snap()
	first := onlyRun(t, target).Folder
	seedVault(t, source, vaultOwner{"bob", randomBytes(t, 32), []string{"c"}})
	snap()

	reg := memNamespaces(t, map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), "BACKUP-1": target.VFS})
	restore := func(run string) (VaultImportResult, error) {
		live := dbtest.NewDB(t)
		addChatUsers(t, live.Db, "alice", "bob")
		chatExec(t, live.Db, `INSERT INTO device_roles (device_serial, role) VALUES ('BACKUP-1', 'snapshot-backup')`)
		return RestoreVault(RestoreVaultParams{
			Ctx: context.Background(), LiveDB: live.Db, Queries: live.Queries, Registry: reg, DeviceSerial: "BACKUP-1", Run: run,
		})
	}

	if result, err := restore(first); err != nil || result.Items != 2 || result.Run != first {
		t.Errorf("restore of the first run = %+v, %v; want alice's 2 items", result, err)
	}
	if result, err := restore(""); err != nil || result.Items != 3 || result.Run == first {
		t.Errorf("restore of the newest run = %+v, %v; want 3 items", result, err)
	}
	if _, err := restore("nope"); !errors.Is(err, ErrRunNotFound) {
		t.Errorf("restore of an unknown run = %v, want ErrRunNotFound", err)
	}
}

package backup

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/vfs"
)

func sizedRuns(sizes ...int64) []Run {
	runs := make([]Run, len(sizes))
	for i, size := range sizes {
		runs[i] = Run{Folder: string(rune('a' + i)), SizeBytes: size}
	}
	return runs
}

func folders(runs []Run) []string {
	names := []string{}
	for _, run := range runs {
		names = append(names, run.Folder)
	}
	return names
}

// planPrune deletes oldest first, stops as soon as there is room, never
// deletes the newest run, and says so when even that is not enough.
func TestPlanPrune(t *testing.T) {
	for _, tc := range []struct {
		name       string
		runs       []Run
		free, need int64
		want       []string
		ok         bool
	}{
		{"room already", sizedRuns(10, 10, 10), 50, 50, []string{}, true},
		{"oldest is enough", sizedRuns(10, 10, 10), 45, 50, []string{"a"}, true},
		{"two oldest", sizedRuns(10, 10, 10), 35, 50, []string{"a", "b"}, true},
		{"newest is never pruned", sizedRuns(10, 10, 100), 35, 60, nil, false},
		{"only the newest", sizedRuns(100), 0, 50, nil, false},
		{"no runs, no room", nil, 0, 1, nil, false},
		{"no runs, room", nil, 1, 1, []string{}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := planPrune(tc.runs, tc.free, tc.need)
			if ok != tc.ok || (ok && !reflect.DeepEqual(folders(got), tc.want)) {
				t.Errorf("planPrune = %v, %v; want %v, %v", folders(got), ok, tc.want, tc.ok)
			}
		})
	}
}

// sizedDrive is a drive of capacity bytes whose free space is what its files
// leave. It cannot link, so a run needs every byte it copies.
type sizedDrive struct {
	*vfs.MemVFS
	capacity int64
}

func (d sizedDrive) FreeSpace(ctx context.Context) (uint64, error) {
	used, err := usedBytes(ctx, d.MemVFS)
	return uint64(max(d.capacity-used, 0)), err
}

func usedBytes(ctx context.Context, fsys vfs.VFS) (int64, error) {
	var used int64
	err := vfs.Walk(ctx, fsys, "", func(fi vfs.FileInfo) error {
		if !fi.IsDir {
			used += fi.Size
		}
		return nil
	})
	return used, err
}

// newSizedDrive holds three 100-byte runs, oldest first, and freeBytes more.
func newSizedDrive(t *testing.T, freeBytes int64) sizedDrive {
	t.Helper()
	mem := vfs.NewMemVFS(vfs.FilesNamespace("BK"))
	at := time.Date(2026, 11, 1, 9, 0, 0, 0, time.UTC)
	for i, folder := range []string{"2026-11-01 09.00", "2026-11-02 09.00", "2026-11-03 09.00"} {
		putRun(t, mem, folder, at.Add(time.Duration(i)*24*time.Hour), nil,
			map[string]string{builtInFolder + "/a.txt": strings.Repeat("x", 100)})
	}
	used, err := usedBytes(t.Context(), mem)
	if err != nil {
		t.Fatal(err)
	}
	return sizedDrive{MemVFS: mem, capacity: used + freeBytes}
}

func snapshotOnto(t *testing.T, target vfs.VFS, files map[string]string) (*BackupJob, error) {
	t.Helper()
	job := newJob("BK")
	job.TargetName = "Backup"
	src := SourceDevice{Name: "Pi", Files: memWith(t, "", files)}
	return job, SnapshotBackup(t.Context(), SnapshotBackupParams{TargetDeviceSerial: "BK", Job: job}, []SourceDevice{src}, target)
}

// A backup short of room deletes the oldest run, and only as many as it
// needs, before it copies.
func TestSnapshotBackup_PrunesTheOldestRunForRoom(t *testing.T) {
	drive := newSizedDrive(t, 60)
	if _, err := snapshotOnto(t, drive, map[string]string{"new.bin": strings.Repeat("n", 150)}); err != nil {
		t.Fatalf("SnapshotBackup: %v", err)
	}
	runs, err := ListRuns(t.Context(), drive)
	if err != nil {
		t.Fatal(err)
	}
	if got := folders(runs[1:]); !reflect.DeepEqual(got, []string{"2026-11-03 09.00", "2026-11-02 09.00"}) {
		t.Errorf("runs kept beside the new one = %v, want the two newest", got)
	}
}

// A backup that cannot fit even with every run but the newest gone fails
// before it writes anything, deletes nothing, and says what to do.
func TestSnapshotBackup_FailsWhenItCannotFit(t *testing.T) {
	drive := newSizedDrive(t, 60)
	job, err := snapshotOnto(t, drive, map[string]string{"huge.bin": strings.Repeat("h", 1000)})
	if !errors.Is(err, ErrNotEnoughSpace) {
		t.Fatalf("SnapshotBackup = %v, want ErrNotEnoughSpace", err)
	}
	if job.Status != BackupStatusFailed || !strings.Contains(job.ErrorMsg, "not enough space on Backup") ||
		!strings.Contains(job.ErrorMsg, "delete old backups or use a bigger drive") || job.FilesCopied != 0 {
		t.Errorf("job = %s %q, %d copied; want it failed naming the drive and the fix", job.Status, job.ErrorMsg, job.FilesCopied)
	}
	entries, err := drive.List(t.Context(), BackupsDir, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Errorf("backups/ = %+v, want the three runs untouched and no partial run", entries)
	}
}

// fixedFree is a disk-backed drive that reports free bytes free.
type fixedFree struct {
	*vfs.LocalVFS
	free uint64
}

func (f fixedFree) FreeSpace(context.Context) (uint64, error) { return f.free, nil }

// A run on a drive that links needs room only for what it copies: nothing
// when no file changed, and a changed file's bytes otherwise.
func TestSnapshotBackup_NeedsRoomOnlyForWhatItCopies(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"big.bin": strings.Repeat("b", 1000)})
	target := makeTarget(t)
	snapshot(t, target.VFS, src)
	tight := fixedFree{LocalVFS: target.VFS.(*vfs.LocalVFS), free: 10}

	job := newJob("BK")
	if err := SnapshotBackup(t.Context(), SnapshotBackupParams{Job: job}, []SourceDevice{src}, tight); err != nil {
		t.Fatalf("an unchanged run on a nearly full drive: %v", err)
	}
	if job.FilesSkipped != 1 {
		t.Errorf("linked %d files, want 1", job.FilesSkipped)
	}

	if err := os.WriteFile(filepath.Join(hostRoot(t, src.Files), "big.bin"), []byte(strings.Repeat("c", 1001)), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := SnapshotBackup(t.Context(), SnapshotBackupParams{Job: newJob("BK")}, []SourceDevice{src}, tight); !errors.Is(err, ErrNotEnoughSpace) {
		t.Errorf("a changed file on a nearly full drive = %v, want ErrNotEnoughSpace", err)
	}
}

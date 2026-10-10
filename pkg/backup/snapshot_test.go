package backup

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func makeSource(t *testing.T, name, serial string, files map[string]string) SourceDevice {
	t.Helper()
	dir := t.TempDir()
	for path, content := range files {
		full := filepath.Join(dir, path)
		os.MkdirAll(filepath.Dir(full), 0755)
		os.WriteFile(full, []byte(content), 0644)
	}
	return SourceDevice{Name: name, Serial: serial, Files: localFS(t, dir)}
}

// localTarget is a disk-backed target namespace and the directory under it.
type localTarget struct {
	vfs.VFS
	FilesDir string
}

func makeTarget(t *testing.T) localTarget {
	t.Helper()
	dir := t.TempDir()
	return localTarget{VFS: localFS(t, dir), FilesDir: dir}
}

func newJob(targetSerial string) *BackupJob {
	return &BackupJob{
		ID:                 "test-job-1",
		Status:             BackupStatusPending,
		TargetDeviceSerial: targetSerial,
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}
}

func TestSnapshotBackup_MultiSource(t *testing.T) {
	src1 := makeSource(t, "Drive A", "SERIAL-A", map[string]string{
		"photos/a.jpg": "photo-a",
		"docs/a.txt":   "doc-a",
	})
	src2 := makeSource(t, "Drive B", "SERIAL-B", map[string]string{
		"photos/b.jpg": "photo-b",
	})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
	}, []SourceDevice{src1, src2}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	// Verify files are namespaced by device.
	assertFileContent(t, filepath.Join(target.FilesDir, "Drive A_SERIAL-A", "photos/a.jpg"), "photo-a")
	assertFileContent(t, filepath.Join(target.FilesDir, "Drive A_SERIAL-A", "docs/a.txt"), "doc-a")
	assertFileContent(t, filepath.Join(target.FilesDir, "Drive B_SERIAL-B", "photos/b.jpg"), "photo-b")

	if job.Status != BackupStatusCompleted {
		t.Errorf("expected COMPLETED, got %s", job.Status)
	}
	if job.FilesCopied != 3 {
		t.Errorf("expected 3 files copied, got %d", job.FilesCopied)
	}
	if job.TotalFiles != 3 {
		t.Errorf("expected 3 total files, got %d", job.TotalFiles)
	}
}

func TestSnapshotBackup_InternalDevice(t *testing.T) {
	src := makeSource(t, "Pi Storage", "", map[string]string{
		"data.txt": "internal-data",
	})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
	}, []SourceDevice{src}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	assertFileContent(t, filepath.Join(target.FilesDir, "internal", "data.txt"), "internal-data")
}

func TestSnapshotBackup_SmartSkip(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{
		"file.txt": "content",
	})
	target := makeTarget(t)

	// Pre-populate target with matching file.
	destDir := filepath.Join(target.FilesDir, "Drive_SER1")
	os.MkdirAll(destDir, 0755)
	destFile := filepath.Join(destDir, "file.txt")
	os.WriteFile(destFile, []byte("content"), 0644)
	// Set mtime to match source.
	srcInfo, _ := src.Files.Stat(t.Context(), "file.txt")
	os.Chtimes(destFile, srcInfo.ModTime, srcInfo.ModTime)

	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
	}, []SourceDevice{src}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	if job.FilesSkipped != 1 {
		t.Errorf("expected 1 file skipped, got %d", job.FilesSkipped)
	}
	if job.FilesCopied != 0 {
		t.Errorf("expected 0 files copied, got %d", job.FilesCopied)
	}
}

func TestSnapshotBackup_OverwriteStale(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{
		"file.txt": "new-content",
	})
	target := makeTarget(t)

	// Pre-populate target with smaller (stale) file.
	destDir := filepath.Join(target.FilesDir, "Drive_SER1")
	os.MkdirAll(destDir, 0755)
	os.WriteFile(filepath.Join(destDir, "file.txt"), []byte("old"), 0644)

	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
	}, []SourceDevice{src}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	if job.FilesCopied != 1 {
		t.Errorf("expected 1 file copied (overwrite stale), got %d", job.FilesCopied)
	}
	assertFileContent(t, filepath.Join(destDir, "file.txt"), "new-content")
}

func TestSnapshotBackup_EmptySource(t *testing.T) {
	src := makeSource(t, "Empty", "SER1", map[string]string{})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
	}, []SourceDevice{src}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	if job.Status != BackupStatusCompleted {
		t.Errorf("expected COMPLETED, got %s", job.Status)
	}
	if job.TotalFiles != 0 {
		t.Errorf("expected 0 total files, got %d", job.TotalFiles)
	}
}

func TestSnapshotBackup_Cancellation(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{
		"a.txt": "a",
		"b.txt": "b",
		"c.txt": "c",
	})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately.

	err := SnapshotBackup(ctx, SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
	}, []SourceDevice{src}, target.VFS)

	if err == nil {
		t.Error("expected error from cancelled context")
	}
	if job.Status != BackupStatusFailed {
		t.Errorf("expected FAILED status, got %s", job.Status)
	}
}

func TestSnapshotBackup_EventBusPublish(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{
		"file.txt": "data",
	})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	bus := eventbus.New()
	ch, unsub := bus.Subscribe("test")
	defer unsub()

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
		EventBus:           bus,
	}, []SourceDevice{src}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	// Should receive at least backup_started and backup_completed.
	gotStarted := false
	gotCompleted := false
	for {
		select {
		case evt := <-ch:
			if evt.Kind == eventbus.EventBackupStarted {
				gotStarted = true
			}
			if evt.Kind == eventbus.EventBackupCompleted {
				gotCompleted = true
			}
		default:
			goto done
		}
	}
done:
	if !gotStarted {
		t.Error("expected backup_started event")
	}
	if !gotCompleted {
		t.Error("expected backup_completed event")
	}
}

func TestDeviceDirName(t *testing.T) {
	tests := []struct {
		name, serial, want string
	}{
		{"My Drive", "ABCDEF123456", "My Drive_ABCDEF12"},
		{"Drive", "SHORT", "Drive_SHORT"},
		{"", "SER", "device_SER"},
		{"Pi Storage", "", "internal"},
		{"Bad/Name:Here", "SER1", "Bad_Name_Here_SER1"},
	}
	for _, tt := range tests {
		got := deviceDirName(tt.name, tt.serial)
		if got != tt.want {
			t.Errorf("deviceDirName(%q, %q) = %q, want %q", tt.name, tt.serial, got, tt.want)
		}
	}
}

func TestSanitizeName(t *testing.T) {
	tests := []struct {
		input, want string
	}{
		{"normal", "normal"},
		{"has/slash", "has_slash"},
		{"has:colon", "has_colon"},
		{"a*b?c", "a_b_c"},
		{"  spaces  ", "spaces"},
	}
	for _, tt := range tests {
		got := sanitizeName(tt.input)
		if got != tt.want {
			t.Errorf("sanitizeName(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func assertFileContent(t *testing.T, path, expected string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read %s: %v", path, err)
	}
	if string(data) != expected {
		t.Errorf("file %s: expected %q, got %q", path, expected, string(data))
	}
}

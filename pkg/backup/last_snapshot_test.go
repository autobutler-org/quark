package backup

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLastSnapshot_NoRecord(t *testing.T) {
	at, err := LastSnapshot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if !at.IsZero() {
		t.Errorf("LastSnapshot = %v, want the zero time", at)
	}
}

func TestLastSnapshot_UnreadableRecordIsNoRecord(t *testing.T) {
	dataDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dataDir, lastSnapshotFilename), []byte("not a time"), 0o644); err != nil {
		t.Fatal(err)
	}
	at, err := LastSnapshot(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	if !at.IsZero() {
		t.Errorf("LastSnapshot = %v, want the zero time", at)
	}
}

func TestRecordSnapshot_RoundTrip(t *testing.T) {
	dataDir := t.TempDir()
	want := time.Date(2026, 10, 9, 12, 30, 0, 0, time.UTC)
	if err := RecordSnapshot(dataDir, want); err != nil {
		t.Fatal(err)
	}
	got, err := LastSnapshot(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Equal(want) {
		t.Errorf("LastSnapshot = %v, want %v", got, want)
	}
}

func TestSnapshotBackup_RecordsCompletion(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"file.txt": "data"})
	target := makeTarget(t)
	job := newJob("TARGET")
	dataDir := t.TempDir()

	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		DataDir:            dataDir,
	}, []SourceDevice{src}, target); err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	got, err := LastSnapshot(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	// The record keeps whole seconds.
	if want := job.CompletedAt.Truncate(time.Second); !got.Equal(want) {
		t.Errorf("LastSnapshot = %v, want the job's completion time %v", got, want)
	}
}

func TestSnapshotBackup_FailedBackupRecordsNothing(t *testing.T) {
	src := makeSource(t, "Drive", "SER1", map[string]string{"file.txt": "data"})
	target := makeTarget(t)
	job := newJob("TARGET")
	dataDir := t.TempDir()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := SnapshotBackup(ctx, SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		DataDir:            dataDir,
	}, []SourceDevice{src}, target); err == nil {
		t.Fatal("SnapshotBackup succeeded with a canceled context")
	}

	got, err := LastSnapshot(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	if !got.IsZero() {
		t.Errorf("LastSnapshot = %v after a failed backup, want the zero time", got)
	}
}

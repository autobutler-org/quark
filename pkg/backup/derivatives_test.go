package backup

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
)

// thumbRel is where a/clip.mov's thumbnail sits, relative to its files
// directory.
var thumbRel = filepath.Join("a", derivativeutil.DirName, "clip.mov", "thumbnail.jpg")

func TestSnapshotBackup_CarriesDerivatives(t *testing.T) {
	src := makeSource(t, "Pi Storage", "", map[string]string{
		"a/clip.mov": "video",
		thumbRel:     "jpeg",
	})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	if err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET", Job: job, Store: store,
	}, []SourceDevice{src}, target); err != nil {
		t.Fatalf("SnapshotBackup failed: %v", err)
	}

	// The thumbnail sits beside its file in the backup too, so the backed-up
	// file finds it by the same rule.
	restored := filepath.Join(target.FilesDir, "internal", "a", "clip.mov")
	assertFileContent(t, derivativeutil.Path(restored, derivativeutil.KindThumbnail), "jpeg")
}

func TestSyncWorker_SyncPath_CopiesDerivatives(t *testing.T) {
	w, srcDir, dstDir := newTestSyncWorker(t)
	writeTestFile(t, srcDir, "a/clip.mov", "video")
	writeTestFile(t, srcDir, thumbRel, "jpeg")

	w.syncPath(context.Background(), "a/clip.mov")

	if got := readTestFile(t, dstDir, thumbRel); got != "jpeg" {
		t.Errorf("expected the thumbnail on the target, got %q", got)
	}
}

func TestSyncWorker_MovePath_MovesDerivatives(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "a/clip.mov", "video")
	writeTestFile(t, dstDir, thumbRel, "jpeg")

	w.movePath(context.Background(), "a/clip.mov", "b/clip.mov")

	moved := filepath.Join(dstDir, "b", "clip.mov")
	assertFileContent(t, derivativeutil.Path(moved, derivativeutil.KindThumbnail), "jpeg")
	if _, err := os.Stat(filepath.Join(dstDir, thumbRel)); !os.IsNotExist(err) {
		t.Error("the thumbnail should have left the old path")
	}
}

func TestSyncWorker_DeletePath_RemovesDerivatives(t *testing.T) {
	w, _, dstDir := newTestSyncWorker(t)
	writeTestFile(t, dstDir, "a/clip.mov", "video")
	writeTestFile(t, dstDir, thumbRel, "jpeg")

	w.deletePath(context.Background(), "a/clip.mov", "")

	if _, err := os.Stat(filepath.Join(dstDir, thumbRel)); !os.IsNotExist(err) {
		t.Error("the thumbnail should be deleted with its file")
	}
}

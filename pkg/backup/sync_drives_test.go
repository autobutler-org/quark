package backup

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// drives is three files directories: the internal drive, the default-storage
// drive live sync mirrors it onto, and one more plugged-in drive (#2791).
type drives struct {
	internal, target, other string
}

const otherSerial = "other-drive"

// newDrivesWorker returns a sync worker wired to three temp-dir drives.
func newDrivesWorker(t *testing.T) (*SyncWorker, *eventbus.Bus, drives) {
	t.Helper()
	d := drives{internal: t.TempDir(), target: t.TempDir(), other: t.TempDir()}
	w := newSyncWorker(localNamespaces(t, map[string]string{
		"": d.internal, targetSerial: d.target, otherSerial: d.other,
	}), targetSerial)
	return w, w.bus, d
}

// runEvents publishes events to a started worker and returns once the worker has
// handled them all: the worker reads one channel in order, so a barrier upload
// published last reaching the target means everything before it was handled.
func runEvents(t *testing.T, w *SyncWorker, bus *eventbus.Bus, d drives, events ...eventbus.Event) {
	t.Helper()
	w.Start()
	defer w.Stop()

	barrier := fmt.Sprintf("barrier-%d.txt", time.Now().UnixNano())
	writeTestFile(t, d.internal, barrier, "barrier")
	for _, evt := range events {
		bus.Publish(evt)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: barrier})

	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, err := os.Stat(filepath.Join(d.target, barrier)); err == nil {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for the sync worker")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// trash moves relPath into filesDir's trash the way fileutil.DeleteFiles does
// and returns the delete event DeleteFiles publishes for it.
func trash(t *testing.T, filesDir, serial, relPath string) (eventbus.Event, storageutil.TrashedItem) {
	t.Helper()
	res, err := storageutil.TrashFilesImpl(storageutil.TrashFilesParams{
		FilePaths:    []string{relPath},
		DeviceSerial: serial,
	}, filesDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Trashed) != 1 {
		t.Fatalf("trashed %d items, want 1", len(res.Trashed))
	}
	return eventbus.Event{Kind: eventbus.EventDelete, Path: relPath, DeviceSerial: serial}, res.Trashed[0]
}

func assertContent(t *testing.T, dir, rel, want string) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, rel))
	if err != nil {
		t.Errorf("%s in %s: %v", rel, dir, err)
		return
	}
	if string(data) != want {
		t.Errorf("%s in %s = %q, want %q", rel, dir, data, want)
	}
}

func assertMissing(t *testing.T, dir, rel string) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(dir, rel)); !os.IsNotExist(err) {
		t.Errorf("%s in %s should not exist (err=%v)", rel, dir, err)
	}
}

// Moving a file to the Trash on the internal drive must not touch the
// same-named file on any USB drive, whether or not it is the mirror's copy.
func TestSyncWorker_TrashOnInternal_KeepsFilesOnOtherDrives(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	const rel = "photos/a.jpg"
	writeTestFile(t, d.internal, rel, "internal")
	writeTestFile(t, d.target, rel, "internal") // the mirror's copy
	writeTestFile(t, d.other, rel, "unrelated") // a different file, same name

	evt, _ := trash(t, d.internal, "", rel)
	runEvents(t, w, bus, d, evt)

	assertMissing(t, d.internal, rel)
	assertContent(t, d.target, rel, "internal")
	assertContent(t, d.other, rel, "unrelated")
}

// Moving a file to the Trash on a USB drive must not touch the internal drive
// or any other USB drive.
func TestSyncWorker_TrashOnUSB_KeepsFilesOnOtherDrives(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	const rel = "docs/report.pdf"
	writeTestFile(t, d.internal, rel, "internal")
	writeTestFile(t, d.target, rel, "target")
	writeTestFile(t, d.other, rel, "other")

	evt, _ := trash(t, d.other, otherSerial, rel)
	runEvents(t, w, bus, d, evt)

	assertContent(t, d.internal, rel, "internal")
	assertContent(t, d.target, rel, "target")
	assertMissing(t, d.other, rel)
}

func TestSyncWorker_TrashFolder_KeepsFoldersOnOtherDrives(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	for _, dir := range []string{d.internal, d.target, d.other} {
		writeTestFile(t, dir, "trip/a.jpg", "a")
		writeTestFile(t, dir, "trip/b.jpg", "b")
	}
	writeTestFile(t, d.other, "trip/only-here.jpg", "only")

	evt, _ := trash(t, d.internal, "", "trip")
	runEvents(t, w, bus, d, evt)

	assertMissing(t, d.internal, "trip")
	for _, dir := range []string{d.target, d.other} {
		assertContent(t, dir, "trip/a.jpg", "a")
		assertContent(t, dir, "trip/b.jpg", "b")
	}
	assertContent(t, d.other, "trip/only-here.jpg", "only")
}

// Trash then restore on the internal drive leaves the mirror holding the file,
// and the unrelated drive untouched throughout.
func TestSyncWorker_RestoreFromTrash_OnInternal(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	const rel = "notes.txt"
	writeTestFile(t, d.internal, rel, "mine")
	writeTestFile(t, d.target, rel, "mine")
	writeTestFile(t, d.other, rel, "unrelated")

	del, item := trash(t, d.internal, "", rel)
	if _, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: item.TrashName}},
	}, d.internal); err != nil {
		t.Fatal(err)
	}
	// The event trashutil.Restore publishes for a restored file.
	restored := eventbus.Event{Kind: eventbus.EventUpload, Path: rel}
	runEvents(t, w, bus, d, del, restored)

	assertContent(t, d.internal, rel, "mine")
	assertContent(t, d.target, rel, "mine")
	assertContent(t, d.other, rel, "unrelated")
}

// A restore on a USB drive is not a change to the internal drive, so the
// internal drive's same-named file must not be copied over the target's.
func TestSyncWorker_RestoreFromTrash_OnUSB_LeavesTarget(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	const rel = "notes.txt"
	writeTestFile(t, d.internal, rel, "internal")
	writeTestFile(t, d.target, rel, "target")
	writeTestFile(t, d.other, rel, "other")

	del, item := trash(t, d.other, otherSerial, rel)
	if _, err := storageutil.RestoreTrashImpl(storageutil.RestoreTrashParams{
		Items: []storageutil.TrashRef{{TrashName: item.TrashName}},
	}, d.other); err != nil {
		t.Fatal(err)
	}
	restored := eventbus.Event{Kind: eventbus.EventUpload, Path: rel, DeviceSerial: otherSerial}
	runEvents(t, w, bus, d, del, restored)

	assertContent(t, d.internal, rel, "internal")
	assertContent(t, d.target, rel, "target")
	assertContent(t, d.other, rel, "other")
}

// A rename on a USB drive must not rename the target's same-named file.
func TestSyncWorker_MoveOnUSB_LeavesTarget(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	writeTestFile(t, d.target, "old.txt", "target")
	writeTestFile(t, d.other, "new.txt", "other")

	runEvents(t, w, bus, d, eventbus.Event{
		Kind: eventbus.EventMove, Path: "old.txt", NewPath: "new.txt", DeviceSerial: otherSerial,
	})

	assertContent(t, d.target, "old.txt", "target")
	assertMissing(t, d.target, "new.txt")
}

// A rename on the internal drive must not overwrite a file already sitting at
// the new name on the target.
func TestSyncWorker_Move_DoesNotOverwriteTarget(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	writeTestFile(t, d.internal, "new.txt", "renamed")
	writeTestFile(t, d.target, "old.txt", "renamed")
	writeTestFile(t, d.target, "new.txt", "already there")

	runEvents(t, w, bus, d, eventbus.Event{Kind: eventbus.EventMove, Path: "old.txt", NewPath: "new.txt"})

	assertContent(t, d.target, "new.txt", "already there")
	assertContent(t, d.target, "old.txt", "renamed")
}

// A rename on the internal drive follows on the target.
func TestSyncWorker_MoveOnInternal_RenamesOnTarget(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	writeTestFile(t, d.internal, "dir/new.txt", "data")
	writeTestFile(t, d.target, "old.txt", "data")
	writeTestFile(t, d.other, "old.txt", "other")

	runEvents(t, w, bus, d, eventbus.Event{Kind: eventbus.EventMove, Path: "old.txt", NewPath: "dir/new.txt"})

	assertMissing(t, d.target, "old.txt")
	assertContent(t, d.target, "dir/new.txt", "data")
	assertContent(t, d.other, "old.txt", "other")
}

// An upload on a USB drive must not copy the internal drive's same-named file
// over the target's.
func TestSyncWorker_UploadOnUSB_LeavesTarget(t *testing.T) {
	w, bus, d := newDrivesWorker(t)
	writeTestFile(t, d.internal, "a.txt", "internal")
	writeTestFile(t, d.target, "a.txt", "target")
	writeTestFile(t, d.other, "a.txt", "uploaded")

	runEvents(t, w, bus, d, eventbus.Event{Kind: eventbus.EventUpload, Path: "a.txt", DeviceSerial: otherSerial})

	assertContent(t, d.target, "a.txt", "target")
}

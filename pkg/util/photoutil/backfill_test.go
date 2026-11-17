package photoutil_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// backfillLibrary writes files under a USB device's files directory and
// returns params for a backfill over it.
func backfillLibrary(t *testing.T, files map[string][]byte) photoutil.BackfillHashesParams {
	t.Helper()
	const serial = "USB-PHOTOS"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	for name, data := range files {
		full := filepath.Join(filesDir, name)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return photoutil.BackfillHashesParams{
		Ctx:      context.Background(),
		Queries:  dbtest.NewDB(t).Queries,
		Registry: deviceRegistry(t, storageutil.NewStorageService(usbDetector{mountPoint: mountPoint, serial: serial})),
	}
}

// waitFor polls cond until it holds, failing the test after five seconds.
func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func indexStatus(t *testing.T, control *photoutil.IndexControl) photoutil.IndexStatusResult {
	t.Helper()
	status, err := photoutil.IndexStatus(photoutil.IndexStatusParams{Control: control})
	if err != nil {
		t.Fatal(err)
	}
	return status
}

// TestBackfillHashes_PausesBetweenFilesAndYieldsItsSlot: a paused pass reads
// no photo and holds no IO slot, so foreground requests get every one, and on
// resume it carries on and finishes the library (#3556).
func TestBackfillHashes_PausesBetweenFilesAndYieldsItsSlot(t *testing.T) {
	params := backfillLibrary(t, map[string][]byte{
		"a.jpg": photoJPEG(t, 1), "b.jpg": photoJPEG(t, 2), "c.jpg": photoJPEG(t, 3),
	})
	sem := iosemutil.NewWithConcurrency(3)
	control := photoutil.NewIndexControl()
	params.IOSemaphore, params.Control = sem, control
	if _, err := photoutil.PauseIndex(photoutil.PauseIndexParams{Control: control}); err != nil {
		t.Fatal(err)
	}

	// Watch the semaphore for as long as the pass runs: it never holds more
	// than one slot.
	var fewest atomic.Int64
	fewest.Store(int64(sem.Cap()))
	stop := make(chan struct{})
	watched := make(chan struct{})
	go func() {
		defer close(watched)
		for {
			select {
			case <-stop:
				return
			default:
			}
			if n := int64(sem.Available()); n < fewest.Load() {
				fewest.Store(n)
			}
		}
	}()

	done := make(chan photoutil.BackfillHashesResult)
	go func() {
		res, err := photoutil.BackfillHashes(params)
		if err != nil {
			t.Error(err)
		}
		done <- res
	}()

	waitFor(t, "the pass to list the library", func() bool { return indexStatus(t, control).Total == 3 })
	time.Sleep(50 * time.Millisecond)
	status := indexStatus(t, control)
	if !status.Running || !status.Paused || status.Hashed != 0 {
		t.Fatalf("paused status = %+v, want running and paused with nothing hashed", status)
	}
	if sem.Available() != sem.Cap() {
		t.Fatalf("paused pass holds %d IO slots, want none", sem.Cap()-sem.Available())
	}

	resumed, err := photoutil.ResumeIndex(photoutil.ResumeIndexParams{Control: control})
	if err != nil {
		t.Fatal(err)
	}
	if resumed.Paused {
		t.Errorf("resume returned %+v, want not paused", resumed)
	}
	var res photoutil.BackfillHashesResult
	select {
	case res = <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("the resumed pass never finished")
	}
	close(stop)
	<-watched

	if res != (photoutil.BackfillHashesResult{Scanned: 3, Hashed: 3}) {
		t.Errorf("result = %+v, want 3 scanned and hashed", res)
	}
	if got := sem.Cap() - int(fewest.Load()); got > 1 {
		t.Errorf("the pass held %d IO slots at once, want at most one", got)
	}
	final := indexStatus(t, control)
	if final.Running || final.Total != 3 || final.Hashed != 3 || final.DatesRead != 3 || final.Failed != 0 || final.LastRunAt == nil {
		t.Errorf("final status = %+v, want 3 of 3 hashed and dated, a last run time, not running", final)
	}
}

// TestBackfillHashes_PausedPassStopsOnCancel: a pass paused at shutdown
// returns instead of waiting forever for a resume.
func TestBackfillHashes_PausedPassStopsOnCancel(t *testing.T) {
	params := backfillLibrary(t, map[string][]byte{"a.jpg": photoJPEG(t, 1)})
	ctx, cancel := context.WithCancel(context.Background())
	params.Ctx = ctx
	params.Control = photoutil.NewIndexControl()
	if _, err := photoutil.PauseIndex(photoutil.PauseIndexParams{Control: params.Control}); err != nil {
		t.Fatal(err)
	}
	done := make(chan error)
	go func() {
		_, err := photoutil.BackfillHashes(params)
		done <- err
	}()
	waitFor(t, "the pass to list the library", func() bool { return indexStatus(t, params.Control).Total == 1 })
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Errorf("err = %v, want context.Canceled", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("a canceled, paused pass never returned")
	}
	if status := indexStatus(t, params.Control); status.Running {
		t.Errorf("status = %+v, want not running", status)
	}
}

// TestBackfillHashes_ListsFailuresByReason: a photo that will not decode is
// counted as failed and listed with its reason, rather than counted hashed
// while its row stays incomplete (#3556).
func TestBackfillHashes_ListsFailuresByReason(t *testing.T) {
	params := backfillLibrary(t, map[string][]byte{
		"good.jpg":   photoJPEG(t, 1),
		"broken.jpg": []byte("not a jpeg"),
	})
	params.Control = photoutil.NewIndexControl()
	res, err := photoutil.BackfillHashes(params)
	if err != nil {
		t.Fatal(err)
	}
	if res != (photoutil.BackfillHashesResult{Scanned: 2, Hashed: 1, Failed: 1}) {
		t.Errorf("result = %+v, want 1 hashed and 1 failed", res)
	}
	status := indexStatus(t, params.Control)
	if status.Hashed != 1 || status.Failed != 1 || len(status.Failures) != 1 {
		t.Fatalf("status = %+v, want 1 hashed and broken.jpg failed", status)
	}
	if got := status.Failures[0]; got.RelPath != "broken.jpg" || got.Serial != "USB-PHOTOS" || got.Reason != photoutil.IndexFailureUndecodable {
		t.Errorf("failure = %+v, want broken.jpg undecodable", got)
	}
}

// TestBackfillHashes_PublishesIndexEvents: the pass announces its start and
// its finish, and pause and resume announce themselves, so an open status
// view fetches the status again.
func TestBackfillHashes_PublishesIndexEvents(t *testing.T) {
	params := backfillLibrary(t, map[string][]byte{"a.jpg": photoJPEG(t, 1)})
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	defer unsubscribe()
	params.Control, params.EventBus = photoutil.NewIndexControl(), bus

	if _, err := photoutil.PauseIndex(photoutil.PauseIndexParams{Control: params.Control, EventBus: bus}); err != nil {
		t.Fatal(err)
	}
	if _, err := photoutil.ResumeIndex(photoutil.ResumeIndexParams{Control: params.Control, EventBus: bus}); err != nil {
		t.Fatal(err)
	}
	if _, err := photoutil.BackfillHashes(params); err != nil {
		t.Fatal(err)
	}
	// Pause, resume, the pass starting, and the pass finishing.
	for i := range 4 {
		select {
		case evt := <-events:
			if evt.Kind != eventbus.EventPhotoIndexChanged || evt.Path != "" || evt.Data != nil {
				t.Errorf("event %d = %+v, want a bare photo_index_changed", i, evt)
			}
		case <-time.After(5 * time.Second):
			t.Fatalf("got %d events, want 4", i)
		}
	}
}

// TestBackfillHashes_HandsEveryLibraryPhotoToWarm: the backfill is where an
// existing library's grid thumbnails are queued (#4219). Every photo it
// lists, hashed already or not, reaches Warm once the pass is done; nothing
// in the trash does.
func TestBackfillHashes_HandsEveryLibraryPhotoToWarm(t *testing.T) {
	params := backfillLibrary(t, map[string][]byte{
		"a.jpg": photoJPEG(t, 1), "Camera/b.jpg": photoJPEG(t, 2), ".trash/1-c/c.jpg": photoJPEG(t, 3),
	})
	if _, err := photoutil.BackfillHashes(params); err != nil {
		t.Fatal(err)
	}
	var warmed []string
	params.Warm = func(photo photoutil.DuplicatePhoto) {
		warmed = append(warmed, photo.DeviceSerial+":"+photo.RelPath)
	}
	// The second pass hashes nothing, and still hands every photo over.
	if _, err := photoutil.BackfillHashes(params); err != nil {
		t.Fatal(err)
	}
	slices.Sort(warmed)
	want := []string{"USB-PHOTOS:Camera/b.jpg", "USB-PHOTOS:a.jpg"}
	if !slices.Equal(warmed, want) {
		t.Errorf("Warm heard %v, want %v", warmed, want)
	}
}

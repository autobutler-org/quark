package downloadutil_test

import (
	"context"
	"runtime"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/downloadutil"
)

func TestDefaultZipSlots_HalfTheCoresAtLeastOne(t *testing.T) {
	if got, want := downloadutil.DefaultZipSlots(), max(1, runtime.NumCPU()/2); got != want {
		t.Errorf("DefaultZipSlots() = %d, want %d", got, want)
	}
	if got := downloadutil.NewZipSlots(downloadutil.ZipSlotsParams{}).Cap(); got != downloadutil.DefaultZipSlots() {
		t.Errorf("zero params Cap() = %d, want the default", got)
	}
}

// A full ZipSlots turns the next caller away after the wait, and a released
// slot is free again.
func TestZipSlots_WaitsThenGivesUp(t *testing.T) {
	z := downloadutil.NewZipSlots(downloadutil.ZipSlotsParams{Slots: 1, Wait: 20 * time.Millisecond})
	release, ok := z.Acquire(context.Background())
	if !ok {
		t.Fatal("first Acquire failed")
	}
	if _, ok := z.Acquire(context.Background()); ok {
		t.Fatal("second Acquire succeeded past the cap")
	}
	release()
	if z.Available() != 1 {
		t.Errorf("Available() = %d after release, want 1", z.Available())
	}
}

// A caller whose request ends stops waiting at once, not at the timeout.
func TestZipSlots_ContextEndsTheWait(t *testing.T) {
	z := downloadutil.NewZipSlots(downloadutil.ZipSlotsParams{Slots: 1, Wait: time.Hour})
	release, _ := z.Acquire(context.Background())
	defer release()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, ok := z.Acquire(ctx); ok {
		t.Fatal("Acquire succeeded on a canceled context")
	}
}

func TestZipSlots_NilCapsNothing(t *testing.T) {
	var z *downloadutil.ZipSlots
	release, ok := z.Acquire(context.Background())
	if !ok {
		t.Fatal("nil ZipSlots refused")
	}
	release()
}

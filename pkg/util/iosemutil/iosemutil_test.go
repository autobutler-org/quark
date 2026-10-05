package iosemutil_test

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/iosemutil"
)

func TestNew(t *testing.T) {
	s := iosemutil.New()
	if s == nil {
		t.Fatal("New() returned nil")
	}
	total := 0
	for _, c := range iosemutil.Classes() {
		total += s.For(c).Cap()
	}
	if got := s.Cap(); got != total {
		t.Errorf("Cap() = %d, want the classes' total %d", got, total)
	}
	if got := s.Available(); got != total {
		t.Errorf("Available() = %d before any acquires, want %d", got, total)
	}
}

// One class running flat out must not cost another its slots (#2762): a
// backup holding every copy slot used to leave thumbnails waiting 30 s for a
// 503.
func TestNew_ClassesAreIsolated(t *testing.T) {
	s := iosemutil.New()
	ctx := context.Background()
	for _, busy := range iosemutil.Classes() {
		held := s.For(busy)
		for range held.Cap() {
			if !held.Acquire(ctx, time.Second) {
				t.Fatalf("%v: could not fill its own slots", busy)
			}
		}
		if held.Acquire(ctx, 10*time.Millisecond) {
			t.Fatalf("%v: acquired past its cap of %d", busy, held.Cap())
		}
		for _, other := range iosemutil.Classes() {
			if other == busy {
				continue
			}
			if !s.For(other).Acquire(ctx, 10*time.Millisecond) {
				t.Errorf("%v is starved while %v is full", other, busy)
				continue
			}
			s.For(other).Release()
		}
		for range held.Cap() {
			held.Release()
		}
	}
}

func TestNew_EveryClassHasASlot(t *testing.T) {
	s := iosemutil.New()
	for _, c := range iosemutil.Classes() {
		if s.For(c).Cap() < 1 {
			t.Errorf("%v has no slots", c)
		}
	}
}

// A semaphore built with NewWithConcurrency has no classes, so every class
// shares it: that is what a test injecting one semaphore expects.
func TestNewWithConcurrency_ForIsItself(t *testing.T) {
	s := iosemutil.NewWithConcurrency(2)
	for _, c := range iosemutil.Classes() {
		if s.For(c) != s {
			t.Errorf("For(%v) on a classless semaphore should be the semaphore itself", c)
		}
	}
}

func TestFor_NilIsNil(t *testing.T) {
	var s *iosemutil.Semaphore
	if s.For(iosemutil.Decode) != nil {
		t.Error("For on a nil semaphore should be nil, so callers' nil checks keep working")
	}
}

func TestNewWithConcurrency(t *testing.T) {
	s := iosemutil.NewWithConcurrency(3)
	if s.Cap() != 3 {
		t.Errorf("Cap() = %d, want 3", s.Cap())
	}
}

func TestNewWithConcurrencyPanic(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Error("expected panic for concurrency < 1")
		}
	}()
	iosemutil.NewWithConcurrency(0)
}

func TestAcquireAndRelease(t *testing.T) {
	s := iosemutil.NewWithConcurrency(2)
	ctx := context.Background()

	if !s.Acquire(ctx, time.Second) {
		t.Fatal("first Acquire should succeed")
	}
	if s.Available() != 1 {
		t.Errorf("Available() = %d after one acquire, want 1", s.Available())
	}

	s.Release()
	if s.Available() != 2 {
		t.Errorf("Available() = %d after release, want 2", s.Available())
	}
}

func TestAcquireDefault(t *testing.T) {
	s := iosemutil.NewWithConcurrency(1)
	ctx := context.Background()
	if !s.AcquireDefault(ctx) {
		t.Fatal("AcquireDefault should succeed on empty semaphore")
	}
	s.Release()
}

func TestAcquireTimeout(t *testing.T) {
	s := iosemutil.NewWithConcurrency(1)
	ctx := context.Background()

	if !s.Acquire(ctx, time.Second) {
		t.Fatal("first Acquire should succeed")
	}
	// Second acquire should time out quickly
	if s.Acquire(ctx, 10*time.Millisecond) {
		t.Error("second Acquire should have timed out")
	}
	s.Release()
}

func TestAcquireContextCancelled(t *testing.T) {
	s := iosemutil.NewWithConcurrency(1)
	ctx, cancel := context.WithCancel(context.Background())

	if !s.Acquire(ctx, time.Second) {
		t.Fatal("first Acquire should succeed")
	}

	cancel() // cancel the context
	if s.Acquire(ctx, time.Second) {
		t.Error("Acquire with cancelled context should fail")
	}
	s.Release()
}

func TestConcurrentLimit(t *testing.T) {
	const limit = 3
	s := iosemutil.NewWithConcurrency(limit)
	ctx := context.Background()

	var mu sync.Mutex
	maxConcurrent := 0
	current := 0

	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if !s.Acquire(ctx, 5*time.Second) {
				t.Errorf("Acquire timed out unexpectedly")
				return
			}
			defer s.Release()

			mu.Lock()
			current++
			if current > maxConcurrent {
				maxConcurrent = current
			}
			if current > limit {
				t.Errorf("concurrent holders = %d, exceeds limit %d", current, limit)
			}
			mu.Unlock()

			time.Sleep(5 * time.Millisecond) // simulate IO

			mu.Lock()
			current--
			mu.Unlock()
		}()
	}
	wg.Wait()

	if maxConcurrent > limit {
		t.Errorf("peak concurrency %d exceeded limit %d", maxConcurrent, limit)
	}
}

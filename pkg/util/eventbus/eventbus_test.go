package eventbus_test

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func TestSubscribeAndPublish(t *testing.T) {
	bus := eventbus.New()
	ch, unsub := bus.Subscribe("test-1")
	defer unsub()

	evt := eventbus.Event{Kind: eventbus.EventUpload, Path: "/foo.txt"}
	bus.Publish(evt)

	select {
	case got := <-ch:
		if got.Kind != eventbus.EventUpload {
			t.Errorf("expected kind %q, got %q", eventbus.EventUpload, got.Kind)
		}
		if got.Path != "/foo.txt" {
			t.Errorf("expected path %q, got %q", "/foo.txt", got.Path)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("timed out waiting for event")
	}
}

func TestMultipleSubscribers(t *testing.T) {
	bus := eventbus.New()

	var wg sync.WaitGroup
	received := make([]int, 3)
	for i := range received {
		i := i
		ch, unsub := bus.Subscribe(string(rune('a' + i)))
		defer unsub()
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case <-ch:
				received[i] = 1
			case <-time.After(200 * time.Millisecond):
			}
		}()
	}

	bus.Publish(eventbus.Event{Kind: eventbus.EventDelete, Path: "/bar.txt"})
	wg.Wait()

	for i, v := range received {
		if v != 1 {
			t.Errorf("subscriber %d did not receive event", i)
		}
	}
}

func TestUnsubscribeClosesChannel(t *testing.T) {
	bus := eventbus.New()
	_, unsub := bus.Subscribe("unsub-test")
	unsub()

	// Should not panic — publishing to a bus with no subscribers is a no-op.
	bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: "/dir"})
}

func TestPublishDoesNotBlockOnFullBuffer(t *testing.T) {
	bus := eventbus.New()
	// Subscribe but never drain the channel — buffer will fill
	_, unsub := bus.Subscribe("slow")
	defer unsub()

	// Fill the 16-slot buffer + one extra; Publish must not block
	done := make(chan struct{})
	go func() {
		for i := 0; i < 20; i++ {
			bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "/x"})
		}
		close(done)
	}()

	select {
	case <-done:
		// pass — Publish returned without blocking
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Publish blocked on full subscriber buffer")
	}
}

func TestMoveEventHasNewPath(t *testing.T) {
	bus := eventbus.New()
	ch, unsub := bus.Subscribe("move-test")
	defer unsub()

	bus.Publish(eventbus.Event{
		Kind:    eventbus.EventMove,
		Path:    "/old.txt",
		NewPath: "/new.txt",
	})

	select {
	case got := <-ch:
		if got.NewPath != "/new.txt" {
			t.Errorf("expected NewPath %q, got %q", "/new.txt", got.NewPath)
		}
	case <-time.After(100 * time.Millisecond):
		t.Fatal("timed out waiting for move event")
	}
}

func TestNoEventAfterUnsubscribe(t *testing.T) {
	bus := eventbus.New()
	ch, unsub := bus.Subscribe("gone")

	// Drain and unsubscribe
	unsub()

	// Publish after unsubscribe — channel should be closed, no new events
	bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: "/late.txt"})

	// Channel is closed; any read will return zero-value immediately
	select {
	case _, ok := <-ch:
		if ok {
			t.Error("expected channel to be closed, got value")
		}
	default:
		// closed channel is drained — acceptable
	}
}

// A subscriber that falls behind must still see every event, in order (#2753).
func TestSubscribeDeliversEveryEventToASlowSubscriber(t *testing.T) {
	bus := eventbus.New()
	ch, unsub := bus.Subscribe("slow")
	defer unsub()

	const n = 100
	for i := 0; i < n; i++ {
		bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: fmt.Sprintf("/f%d", i)})
	}
	for i := 0; i < n; i++ {
		got := receive(t, ch)
		if want := fmt.Sprintf("/f%d", i); got.Path != want {
			t.Fatalf("event %d: got %q, want %q", i, got.Path, want)
		}
	}
}

// A lossy subscriber that falls behind loses its backlog and hears a resync
// instead, so it knows to refresh.
func TestSubscribeLossyReplacesBacklogWithResync(t *testing.T) {
	bus := eventbus.New()
	ch, unsub := bus.SubscribeLossy("client")
	defer unsub()

	for i := 0; i < 17; i++ {
		bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: fmt.Sprintf("/f%d", i)})
	}
	got := receive(t, ch)
	if got.Kind != eventbus.EventResync {
		t.Fatalf("got %q, want %q", got.Kind, eventbus.EventResync)
	}
	if r, ok := got.Data.(eventbus.Resync); !ok || r.Dropped != 17 {
		t.Fatalf("got data %#v, want Resync{Dropped: 17}", got.Data)
	}

	bus.Publish(eventbus.Event{Kind: eventbus.EventDelete, Path: "/after"})
	if got := receive(t, ch); got.Path != "/after" {
		t.Fatalf("got %q after the resync, want /after", got.Path)
	}
}

// Publishers race a subscriber that is slower than all of them; once they
// stop, what the subscriber applied must match what was published last for
// every path. Run under -race.
func TestSlowSubscriberSeesFinalStateAfterBurst(t *testing.T) {
	bus := eventbus.New()
	ch, unsub := bus.Subscribe("slow")
	defer unsub()

	const publishers, paths, rounds = 4, 50, 5
	present := map[string]bool{}
	applied := make(chan struct{})
	go func() {
		defer close(applied)
		for evt := range ch {
			time.Sleep(100 * time.Microsecond)
			switch evt.Kind {
			case eventbus.EventUpload:
				present[evt.Path] = true
			case eventbus.EventDelete:
				present[evt.Path] = false
			case eventbus.EventResync:
				t.Errorf("unexpected resync: %#v", evt.Data)
			case eventbus.EventNewFolder:
				return
			}
		}
	}()

	var wg sync.WaitGroup
	want := map[string]bool{}
	for p := 0; p < publishers; p++ {
		for i := 0; i < paths; i++ {
			// Each publisher owns its paths; an odd path ends deleted.
			want[fmt.Sprintf("/p%d/f%d", p, i)] = i%2 == 0
		}
		wg.Add(1)
		go func(p int) {
			defer wg.Done()
			for r := 0; r < rounds; r++ {
				for i := 0; i < paths; i++ {
					path := fmt.Sprintf("/p%d/f%d", p, i)
					bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: path})
					if i%2 == 1 || r < rounds-1 {
						bus.Publish(eventbus.Event{Kind: eventbus.EventDelete, Path: path})
					}
				}
			}
			for i := 0; i < paths; i += 2 {
				bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: fmt.Sprintf("/p%d/f%d", p, i)})
			}
		}(p)
	}
	wg.Wait()
	bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: "/done"})

	select {
	case <-applied:
	case <-time.After(10 * time.Second):
		t.Fatal("subscriber never reached the end of the burst")
	}
	for path, w := range want {
		if present[path] != w {
			t.Errorf("%s: present = %v, want %v", path, present[path], w)
		}
	}
}

func receive(t *testing.T, ch <-chan eventbus.Event) eventbus.Event {
	t.Helper()
	select {
	case got, ok := <-ch:
		if !ok {
			t.Fatal("channel closed")
		}
		return got
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for event")
	}
	return eventbus.Event{}
}

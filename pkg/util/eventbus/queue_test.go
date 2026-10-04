package eventbus

import (
	"fmt"
	"testing"
	"time"
)

// fill publishes enough events to fill a subscriber's channel, so what comes
// next has to queue.
func fill(bus *Bus) {
	for i := 0; i < subscriberBuffer; i++ {
		bus.Publish(Event{Kind: EventDelete, Path: fmt.Sprintf("/fill%d", i)})
	}
}

func receive(t *testing.T, ch <-chan Event) Event {
	t.Helper()
	select {
	case got := <-ch:
		return got
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for event")
	}
	return Event{}
}

// A queue past its bound swaps its backlog for one resync, then carries on
// with what comes after it.
func TestSubscribeOverflowBecomesResync(t *testing.T) {
	bus := New()
	bus.maxPending = 8
	ch, unsub := bus.Subscribe("slow")
	defer unsub()

	fill(bus)
	for i := 0; i < 40; i++ {
		bus.Publish(Event{Kind: EventUpload, Path: fmt.Sprintf("/f%d", i)})
	}
	bus.Publish(Event{Kind: EventDelete, Path: "/after"})

	// The channel's worth, then at most the one the pump held, then the
	// resync.
	var got Event
	for i := 0; ; i++ {
		if got = receive(t, ch); got.Kind == EventResync {
			break
		}
		if i > subscriberBuffer {
			t.Fatalf("no resync after %d events", i)
		}
	}
	if r := got.Data.(Resync); r.Dropped == 0 {
		t.Fatalf("resync reports no drops")
	}
	// It stands in for the newest event it dropped (#2764): everything after
	// it was published later.
	if got.Seq == 0 {
		t.Fatalf("resync carries no Seq")
	}
	var rest []string
	for {
		e := receive(t, ch)
		if e.Seq <= got.Seq {
			t.Fatalf("event %q after the resync has Seq %d, not after its %d", e.Path, e.Seq, got.Seq)
		}
		rest = append(rest, e.Path)
		if e.Path == "/after" {
			break
		}
	}
	if len(rest) > bus.maxPending {
		t.Fatalf("got %d events after the resync, more than the bound %d", len(rest), bus.maxPending)
	}
}

// Nothing merges across a move: an upload before it and one after it are
// both delivered, either side of it.
func TestSubscribeDoesNotCoalesceAcrossMove(t *testing.T) {
	bus := New()
	ch, unsub := bus.Subscribe("slow")
	defer unsub()

	fill(bus)
	bus.Publish(Event{Kind: EventUpload, Path: "/a"})
	bus.Publish(Event{Kind: EventMove, Path: "/a", NewPath: "/b"})
	bus.Publish(Event{Kind: EventUpload, Path: "/a"})

	for i := 0; i < subscriberBuffer; i++ {
		receive(t, ch)
	}
	for _, want := range []EventKind{EventUpload, EventMove, EventUpload} {
		if got := receive(t, ch); got.Kind != want {
			t.Fatalf("got %q, want %q", got.Kind, want)
		}
	}
}

// Unsubscribing closes the channel even while the pump is mid-handoff.
func TestUnsubscribeClosesQueuedChannel(t *testing.T) {
	bus := New()
	ch, unsub := bus.Subscribe("gone")
	bus.Publish(Event{Kind: EventUpload, Path: "/x"})
	unsub()
	unsub()
	deadline := time.After(time.Second)
	for {
		select {
		case _, ok := <-ch:
			if !ok {
				return
			}
		case <-deadline:
			t.Fatal("channel never closed")
		}
	}
}

// Repeats of one event for one path collapse to the latest once the
// subscriber is behind, so a burst over the same files costs one queue entry
// per file.
func TestSubscribeCoalescesRepeatedEvents(t *testing.T) {
	bus := New()
	ch, unsub := bus.Subscribe("slow")
	defer unsub()

	fill(bus)
	for i := 0; i < 50; i++ {
		bus.Publish(Event{Kind: EventUpload, Path: "/a"})
	}
	bus.Publish(Event{Kind: EventDelete, Path: "/end"})

	uploads := 0
	for {
		got := receive(t, ch)
		if got.Path == "/end" {
			break
		}
		if got.Path == "/a" {
			uploads++
		}
	}
	// One may already be on its way to the channel when the rest coalesce.
	if uploads == 0 || uploads > 2 {
		t.Fatalf("got %d uploads of /a, want 1 or 2", uploads)
	}
}

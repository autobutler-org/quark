package eventbus

import (
	"container/list"
	"sync"
)

// defaultMaxPending bounds a Subscribe queue. Entries are coalesced per path,
// so this many is a bulk operation over thousands of distinct files while the
// subscriber is busy; at a couple of hundred bytes each it stays around a
// megabyte.
const defaultMaxPending = 4096

// subscriberBuffer is every subscriber's channel capacity.
const subscriberBuffer = 16

type subscriber interface {
	channel() <-chan Event
	deliver(e Event)
	close()
}

// eventKey identifies the events that coalesce: the same kind on the same
// path of the same device. Upload, new folder and delete each apply what is
// on disk now (or remove it), so a later one does everything an earlier one
// would have.
type eventKey struct {
	kind   EventKind
	serial string
	path   string
}

// queuedSubscriber is a Subscribe subscriber. Events go straight into out
// while it keeps up; once out is full they wait in an ordered, coalescing
// queue that its own goroutine drains into out.
type queuedSubscriber struct {
	mu      sync.Mutex
	pending *list.List                 // of Event, oldest first
	byKey   map[eventKey]*list.Element // pending entries that may coalesce
	max     int
	// resync is set when the queue overflowed; it goes out before pending,
	// which holds only what came after the overflow.
	resync  bool
	dropped int
	// inFlight is set while pump holds an event it took off pending, so a
	// newer one cannot overtake it straight into out.
	inFlight bool
	closed   bool

	wake     chan struct{}
	done     chan struct{}
	out      chan Event
	shutdown sync.Once
}

func newQueuedSubscriber(maxPending int) *queuedSubscriber {
	s := &queuedSubscriber{
		pending: list.New(),
		byKey:   map[eventKey]*list.Element{},
		max:     maxPending,
		wake:    make(chan struct{}, 1),
		done:    make(chan struct{}),
		out:     make(chan Event, subscriberBuffer),
	}
	go s.pump()
	return s
}

func (s *queuedSubscriber) deliver(e Event) {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return
	}
	if !s.inFlight && !s.resync && s.pending.Len() == 0 {
		select {
		case s.out <- e:
			s.mu.Unlock()
			return
		default:
		}
	}
	switch key, ok := coalesceKey(e); {
	case ok:
		if el, found := s.byKey[key]; found {
			s.pending.Remove(el)
		}
		s.byKey[key] = s.pending.PushBack(e)
	case e.Kind == EventMove:
		// A move changes what the paths around it mean, so nothing queued
		// before it may merge with anything after it.
		clear(s.byKey)
		s.pending.PushBack(e)
	default:
		s.pending.PushBack(e)
	}
	if s.pending.Len() > s.max {
		s.resync = true
		s.dropped += s.pending.Len()
		s.pending.Init()
		clear(s.byKey)
	}
	s.mu.Unlock()
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

// next takes the oldest queued event, waiting for one; false means the
// subscriber was closed.
func (s *queuedSubscriber) next() (Event, bool) {
	for {
		s.mu.Lock()
		if s.resync {
			e := Event{Kind: EventResync, Data: Resync{Dropped: s.dropped}}
			s.resync, s.dropped, s.inFlight = false, 0, true
			s.mu.Unlock()
			return e, true
		}
		if front := s.pending.Front(); front != nil {
			e := s.pending.Remove(front).(Event)
			if key, ok := coalesceKey(e); ok && s.byKey[key] == front {
				delete(s.byKey, key)
			}
			s.inFlight = true
			s.mu.Unlock()
			return e, true
		}
		s.mu.Unlock()
		select {
		case <-s.wake:
		case <-s.done:
			return Event{}, false
		}
	}
}

func (s *queuedSubscriber) pump() {
	defer func() {
		s.mu.Lock()
		s.closed = true
		close(s.out)
		s.mu.Unlock()
	}()
	for {
		e, ok := s.next()
		if !ok {
			return
		}
		select {
		case s.out <- e:
		case <-s.done:
			return
		}
		s.mu.Lock()
		s.inFlight = false
		s.mu.Unlock()
	}
}

func (s *queuedSubscriber) channel() <-chan Event { return s.out }

func (s *queuedSubscriber) close() { s.shutdown.Do(func() { close(s.done) }) }

// lossySubscriber is a SubscribeLossy subscriber.
type lossySubscriber struct {
	mu     sync.Mutex
	ch     chan Event
	closed bool
}

func newLossySubscriber() *lossySubscriber {
	return &lossySubscriber{ch: make(chan Event, subscriberBuffer)}
}

func (s *lossySubscriber) deliver(e Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	select {
	case s.ch <- e:
		return
	default:
	}
	// Full: everything buffered is stale once the app reloads, so swap it
	// all for one resync. Only this method sends, under mu, so the slot
	// freed here stays free.
	dropped := 1
	for drained := false; !drained; {
		select {
		case old := <-s.ch:
			if r, ok := old.Data.(Resync); ok && old.Kind == EventResync {
				dropped += r.Dropped
			} else {
				dropped++
			}
		default:
			drained = true
		}
	}
	s.ch <- Event{Kind: EventResync, Data: Resync{Dropped: dropped}}
}

func (s *lossySubscriber) channel() <-chan Event { return s.ch }

func (s *lossySubscriber) close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.closed {
		s.closed = true
		close(s.ch)
	}
}

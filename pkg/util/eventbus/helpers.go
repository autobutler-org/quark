package eventbus

// add registers s under id, replacing and closing any subscriber already
// there, and returns its channel and unsubscribe func.
func (b *Bus) add(id string, s subscriber) (<-chan Event, func()) {
	b.mu.Lock()
	if old, ok := b.subscribers[id]; ok {
		old.close()
	}
	b.subscribers[id] = s
	b.mu.Unlock()
	return s.channel(), func() {
		b.mu.Lock()
		if b.subscribers[id] == s {
			delete(b.subscribers, id)
		}
		b.mu.Unlock()
		s.close()
	}
}

// coalesceKey reports the key under which e merges with an earlier queued
// event, and false for kinds that never merge.
func coalesceKey(e Event) (eventKey, bool) {
	switch e.Kind {
	case EventUpload, EventNewFolder, EventDelete:
		return eventKey{kind: e.Kind, serial: e.DeviceSerial, path: e.Path}, true
	}
	return eventKey{}, false
}

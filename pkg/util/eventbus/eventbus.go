package eventbus

import "sync"

type EventKind string

const (
	EventUpload    EventKind = "upload"
	EventDelete    EventKind = "delete"
	EventMove      EventKind = "move"
	EventNewFolder EventKind = "new_folder"
	// EventTrashChanged fires whenever a device's trash gains or loses items:
	// a delete, a restore, a permanent delete, emptying it, or the hourly
	// purge. DeviceSerial names the device; Path is empty.
	EventTrashChanged EventKind = "trash_changed"

	EventBackupStarted   EventKind = "backup_started"
	EventBackupProgress  EventKind = "backup_progress"
	EventBackupCompleted EventKind = "backup_completed"
	EventBackupFailed    EventKind = "backup_failed"

	// Background job lifecycle (jobutil). Data is the jobutil.Job as it stands
	// after the change; Path is empty. A job that changes the file tree also
	// publishes the file event for what it changed.
	EventJobQueued    EventKind = "job_queued"
	EventJobStarted   EventKind = "job_started"
	EventJobProgress  EventKind = "job_progress"
	EventJobCompleted EventKind = "job_completed"
	EventJobFailed    EventKind = "job_failed"
	EventJobCanceled  EventKind = "job_canceled"

	EventVaultDeviceDisconnected EventKind = "vault_device_disconnected"
	EventVaultDeviceReconnected  EventKind = "vault_device_reconnected"
	EventVaultStorageChanged     EventKind = "vault_storage_changed"

	// EventAccountChanged fires when an account's role changes (promoted or
	// demoted), so signed-in apps refetch what they are allowed to show.
	EventAccountChanged EventKind = "account_changed"
)

type Event struct {
	Kind         EventKind   `json:"kind"`
	Path         string      `json:"path,omitempty"`
	NewPath      string      `json:"newPath,omitempty"`
	Data         interface{} `json:"data,omitempty"`
	DeviceSerial string      `json:"deviceSerial,omitempty"` // serial of the device this event originated from; empty = internal
}

type Bus struct {
	mu          sync.RWMutex
	subscribers map[string]chan Event
}

func New() *Bus { return &Bus{subscribers: map[string]chan Event{}} }

// Subscribe registers a subscriber and returns its channel and an unsubscribe func.
func (b *Bus) Subscribe(id string) (<-chan Event, func()) {
	ch := make(chan Event, 16)
	b.mu.Lock()
	b.subscribers[id] = ch
	b.mu.Unlock()
	return ch, func() {
		b.mu.Lock()
		delete(b.subscribers, id)
		close(ch)
		b.mu.Unlock()
	}
}

// Publish sends an event to all subscribers (non-blocking; drops if buffer full).
func (b *Bus) Publish(e Event) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	for _, ch := range b.subscribers {
		select {
		case ch <- e:
		default:
		}
	}
}

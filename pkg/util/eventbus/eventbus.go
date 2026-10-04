// Package eventbus is the in-process publish/subscribe bus behind /api/v0/events. Anything that changes the file
// tree publishes an Event, and each connected client holds a subscription.
package eventbus

import (
	"sync"
	"sync/atomic"
)

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

	// EventFeatureFlagChanged fires when an admin turns a beta feature flag on
	// or off (#2542), so every signed-in app reloads /settings/features and
	// hides or shows the feature. Path is empty.
	EventFeatureFlagChanged EventKind = "feature_flag_changed"

	// EventPublicSettingsChanged fires when an admin changes something
	// GET /settings/public reports, such as the Quark's theme color (#2740), so
	// every signed-in app fetches it again. Path and Data are empty.
	EventPublicSettingsChanged EventKind = "public_settings_changed"

	// EventAccessChanged fires when access rows moved with a path or were
	// deleted with it (#1905). Path and DeviceSerial name where the rows are
	// now, or where they were deleted from.
	EventAccessChanged EventKind = "access_changed"

	// EventChatChannelChanged fires when a chat channel is created, renamed,
	// deleted, or its members change (#2415). Data is a ChatChannelChanged;
	// Path is empty.
	EventChatChannelChanged EventKind = "chat_channel_changed"

	// EventChatKeyNeeded fires when a channel has members waiting for a key
	// grant, or its key needs rotating (#2417). Data is a ChatChannelChanged
	// whose Audience is the members who hold a version and can fill it.
	EventChatKeyNeeded EventKind = "chat_key_needed"

	// EventChatKeyGranted fires when grants were stored for members (#2417).
	// Data is a ChatChannelChanged whose Audience is the recipients.
	EventChatKeyGranted EventKind = "chat_key_granted"

	// EventChatMessageCreated fires when a chat message is posted (#2418).
	// Data is a ChatMessageChanged carrying the stored ciphertext row.
	EventChatMessageCreated EventKind = "chat_message_created"
	// EventChatMessageDeleted fires when a chat message is deleted (#2418).
	// Data is a ChatMessageChanged with no Message.
	EventChatMessageDeleted EventKind = "chat_message_deleted"
	// EventChatReactionChanged fires when a reaction is added to or removed
	// from a chat message (#2426). Data is a ChatReactionChanged.
	EventChatReactionChanged EventKind = "chat_reaction_changed"

	// EventResync tells a subscriber it missed events and should refetch or
	// reconcile everything it holds (#2753). Data is a Resync; Path is empty.
	EventResync EventKind = "resync"

	// EventCalendarChanged fires when a calendar event is created, updated
	// or deleted. Data is the event's id; Path is empty. The calendar is
	// shared by every account (#1144), so every client hears it.
	EventCalendarChanged EventKind = "calendar_changed"
)

// ChatChannelChanged is the data of a chat_channel_changed, chat_key_needed or
// chat_key_granted event. It lives here
// rather than in chatutil so accessutil can filter on it without importing the
// package that imports accessutil.
type ChatChannelChanged struct {
	ChannelID int64 `json:"channelId"`
	// Audience is every account with a non-empty set on the channel before
	// the change or after it, the only non-admins who hear the event. It is
	// never sent.
	Audience []int64 `json:"-"`
}

// ChatMessageChanged is the data of a chat_message_created or
// chat_message_deleted event. Unlike every other chat event it reaches only
// the channel's members, admins included: an admin who isn't a member hears
// nothing.
type ChatMessageChanged struct {
	ChannelID int64 `json:"channelId"`
	MessageID int64 `json:"messageId"`
	// Message is the stored row, a chatutil.Message, on chat_message_created.
	// It is ciphertext and capped at 16 KiB, so it rides the event whole.
	Message any `json:"message,omitempty"`
	// Audience is the channel's readers, the accounts holding read_messages.
	// It is never sent.
	Audience []int64 `json:"-"`
}

// ChatReactionChanged is the data of a chat_reaction_changed event. Like a
// message event it reaches only the channel's readers.
type ChatReactionChanged struct {
	ChannelID  int64 `json:"channelId"`
	MessageID  int64 `json:"messageId"`
	ReactionID int64 `json:"reactionId"`
	// Reaction is the stored row, a chatutil.Reaction, when it was added, and
	// absent when it was removed.
	Reaction any `json:"reaction,omitempty"`
	// Audience is the channel's readers, the accounts holding read_messages.
	// It is never sent.
	Audience []int64 `json:"-"`
}

type Event struct {
	Kind         EventKind   `json:"kind"`
	Path         string      `json:"path,omitempty"`
	NewPath      string      `json:"newPath,omitempty"`
	Data         interface{} `json:"data,omitempty"`
	DeviceSerial string      `json:"deviceSerial,omitempty"` // serial of the device this event originated from; empty = internal
	// Seq is the bus's sequence number for the event, stamped by Publish. A
	// resync carries the newest Seq of the events it stands in for. A
	// subscriber compares it with [Bus.Seq] read before it loaded something,
	// to know whether what it loaded already reflects the event (#2764). It is
	// never sent.
	Seq uint64 `json:"-"`
}

// Resync is the data of a resync event: how many events the subscriber missed.
type Resync struct {
	Dropped int `json:"dropped"`
}

// Bus fans every published Event out to its subscribers. Publish never
// blocks; what happens to a subscriber that falls behind depends on how it
// subscribed.
type Bus struct {
	mu          sync.RWMutex
	subscribers map[string]subscriber
	// maxPending bounds each Subscribe queue; tests lower it.
	maxPending int
	seq        atomic.Uint64
}

// Seq is the sequence number of the newest event published. A publisher
// commits its change before it publishes, so whatever is read from the
// database after Seq returns n reflects every event up to n.
func (b *Bus) Seq() uint64 { return b.seq.Load() }

func New() *Bus { return &Bus{subscribers: map[string]subscriber{}, maxPending: defaultMaxPending} }

// Subscribe registers a subscriber that must not lose a change: backup sync,
// the indexers, caches. Its events queue in order however far it falls
// behind, and repeats of one event for one path collapse into the latest, so
// the queue holds at most one entry per changed path. If it still outgrows
// its bound, the backlog is replaced by one EventResync, and the subscriber
// must reconcile from what is on disk.
//
// It returns the subscriber's channel and an unsubscribe func that closes it.
func (b *Bus) Subscribe(id string) (<-chan Event, func()) {
	return b.add(id, newQueuedSubscriber(b.maxPending))
}

// SubscribeLossy registers a subscriber that would rather skip ahead than
// hold events: an app's socket, which can refetch. It gets a small buffer;
// when that is full, the backlog is discarded and replaced by one
// EventResync carrying how many events were dropped, so the app refreshes
// once instead of going quietly stale.
func (b *Bus) SubscribeLossy(id string) (<-chan Event, func()) {
	return b.add(id, newLossySubscriber())
}

// Publish stamps an event with the next sequence number and hands it to every
// subscriber. It never blocks.
func (b *Bus) Publish(e Event) {
	e.Seq = b.seq.Add(1)
	b.mu.RLock()
	defer b.mu.RUnlock()
	for _, s := range b.subscribers {
		s.deliver(e)
	}
}

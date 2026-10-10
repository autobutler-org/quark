package chatutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func (f fixture) markRead(as string, channelID, messageID int64) (chatutil.MarkReadResult, error) {
	return chatutil.MarkRead(chatutil.MarkReadParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, MessageID: messageID,
	})
}

// unread is the account's unread count on a channel in its list, all=1 for an
// admin, and -1 when the channel isn't listed.
func (f fixture) unread(t *testing.T, as string, channelID int64) int64 {
	t.Helper()
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as), All: as == "admin",
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, channel := range result.Channels {
		if channel.ID == channelID {
			return channel.UnreadCount
		}
	}
	return -1
}

// postN has an account post n messages and returns their ids.
func (f fixture) postN(t *testing.T, as string, channelID int64, nonce byte, n int) []int64 {
	t.Helper()
	ids := make([]int64, 0, n)
	for i := range n {
		result, err := f.post(as, channelID, sealedMessage(nonce+byte(i), 'm'))
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, result.Message.ID)
	}
	return ids
}

// readMarkerEvents drains a subscription up to a marker event and returns the
// chat_read_marker_changed events before it.
func (f fixture) readMarkerEvents(events <-chan eventbus.Event) []eventbus.ChatReadMarkerChanged {
	const marker = "read-marker-test-drained"
	f.bus.Publish(eventbus.Event{Kind: eventbus.EventResync, Path: marker})
	var heard []eventbus.ChatReadMarkerChanged
	for evt := range events {
		if evt.Kind == eventbus.EventResync && evt.Path == marker {
			break
		}
		if data, ok := evt.Data.(eventbus.ChatReadMarkerChanged); ok && evt.Kind == eventbus.EventChatReadMarkerChanged {
			heard = append(heard, data)
		}
	}
	return heard
}

// TestReadMarkerNeverMovesBackward checks a marker only moves forward
// (#2424): an earlier or equal id leaves it where it is, answers with the
// standing marker, and announces nothing.
func TestReadMarkerNeverMovesBackward(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	ids := f.postN(t, "bob", room, 'a', 3)
	events, unsubscribe := f.bus.Subscribe("read-marker-test")
	defer unsubscribe()

	result, err := f.markRead("carol", room, ids[2])
	if err != nil || result != (chatutil.MarkReadResult{ChannelID: room, LastReadMessageID: ids[2]}) {
		t.Fatalf("mark read 3 = %+v, %v", result, err)
	}
	want := eventbus.ChatReadMarkerChanged{ChannelID: room, LastReadMessageID: ids[2], UserID: f.users["carol"]}
	if heard := f.readMarkerEvents(events); len(heard) != 1 || heard[0] != want {
		t.Fatalf("events after a move = %+v, want %+v", heard, want)
	}

	for _, id := range []int64{ids[0], ids[2]} {
		result, err = f.markRead("carol", room, id)
		if err != nil || result.LastReadMessageID != ids[2] || result.UnreadCount != 0 {
			t.Errorf("mark read %d after %d = %+v, %v", id, ids[2], result, err)
		}
	}
	if heard := f.readMarkerEvents(events); len(heard) != 0 {
		t.Errorf("events after no move = %+v", heard)
	}
	if got := f.unread(t, "carol", room); got != 0 {
		t.Errorf("unread = %d, want 0", got)
	}
}

// TestUnreadCounts counts what someone else wrote after the marker and nobody
// deleted, per account.
func TestUnreadCounts(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	other := f.keyedOther(t)
	bobs := f.postN(t, "bob", room, 'a', 3)
	f.postN(t, "carol", room, 'k', 2)

	// Each counts the other's messages, never their own.
	if got := f.unread(t, "carol", room); got != 3 {
		t.Errorf("carol unread = %d, want 3", got)
	}
	if got := f.unread(t, "bob", room); got != 2 {
		t.Errorf("bob unread = %d, want 2", got)
	}
	if got := f.unread(t, "bob", other); got != 0 {
		t.Errorf("unread in a quiet channel = %d, want 0", got)
	}

	// A marker partway leaves the rest unread, and a tombstone stops counting.
	result, err := f.markRead("carol", room, bobs[0])
	if err != nil || result.UnreadCount != 2 {
		t.Fatalf("mark read 1 = %+v, %v", result, err)
	}
	if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as("bob"), MessageID: bobs[1],
	}); err != nil {
		t.Fatal(err)
	}
	if got := f.unread(t, "carol", room); got != 1 {
		t.Errorf("unread after a delete = %d, want 1", got)
	}

	// Reading to a deleted message's id is fine, and to the end clears it.
	if result, err = f.markRead("carol", room, bobs[1]); err != nil || result.UnreadCount != 1 {
		t.Errorf("mark read at a tombstone = %+v, %v", result, err)
	}
	if result, err = f.markRead("carol", room, bobs[2]); err != nil || result.UnreadCount != 0 {
		t.Errorf("mark read at the end = %+v, %v", result, err)
	}
	// Bob's count is his own.
	if got := f.unread(t, "bob", room); got != 2 {
		t.Errorf("bob unread after carol read = %d, want 2", got)
	}

	f.postN(t, "bob", room, 'x', 1)
	if got := f.unread(t, "carol", room); got != 1 {
		t.Errorf("unread after a new message = %d, want 1", got)
	}
}

// keyedOther is a second channel of bob's with a key and one message of
// carol's, which bob then reads.
func (f fixture) keyedOther(t *testing.T) int64 {
	t.Helper()
	other := f.create(t, "bob", "other")
	if _, err := f.createVersion("bob", other.ID, 1); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", other.ID, f.users["carol"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	ids := f.postN(t, "carol", other.ID, 'o', 1)
	if _, err := f.markRead("bob", other.ID, ids[0]); err != nil {
		t.Fatal(err)
	}
	return other.ID
}

// TestReadMarkersRespectPermissions keeps markers and counts to holders of
// read_messages: a delegated manager and an admin who isn't a member can't
// mark the channel read and count nothing in it, a message from another
// channel moves nothing, and losing read_messages zeroes the count.
func TestReadMarkersRespectPermissions(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	other := f.keyedOther(t)
	if err := f.set(t, "bob", room, f.users["dave"], 0, chatutil.PermManageMembers); err != nil {
		t.Fatal(err)
	}
	ids := f.postN(t, "bob", room, 'a', 2)

	for _, name := range []string{"dave", "admin"} {
		if _, err := f.markRead(name, room, ids[0]); !errors.Is(err, chatutil.ErrChannelNotFound) {
			t.Errorf("mark read as %s = %v, want ErrChannelNotFound", name, err)
		}
		if got := f.unread(t, name, room); got != 0 {
			t.Errorf("%s unread = %d, want 0", name, got)
		}
	}

	otherMessages, err := chatutil.ListMessages(chatutil.ListMessagesParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), ChannelID: other,
	})
	if err != nil || len(otherMessages.Messages) != 1 {
		t.Fatalf("other's messages = %+v, %v", otherMessages, err)
	}
	for _, id := range []int64{otherMessages.Messages[0].ID, 0, -1, 1 << 40} {
		if _, err := f.markRead("carol", room, id); !errors.Is(err, chatutil.ErrMessageNotFound) {
			t.Errorf("mark read at %d = %v, want ErrMessageNotFound", id, err)
		}
	}

	if got := f.unread(t, "carol", room); got != 2 {
		t.Fatalf("carol unread = %d, want 2", got)
	}
	if err := f.set(t, "bob", room, f.users["carol"], 0, chatutil.PermManageMembers); err != nil {
		t.Fatal(err)
	}
	if got := f.unread(t, "carol", room); got != 0 {
		t.Errorf("unread without read_messages = %d, want 0", got)
	}
}

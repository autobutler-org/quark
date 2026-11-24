package chatutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func (f fixture) markBranchRead(as string, rootID, messageID int64) (chatutil.MarkReadResult, error) {
	return chatutil.MarkBranchRead(chatutil.MarkBranchReadParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		RootID: rootID, MessageID: messageID,
	})
}

// branchCounts is the account's two branch counts on a channel in its list.
func (f fixture) branchCounts(t *testing.T, as string, channelID int64) [2]int64 {
	t.Helper()
	channel, _ := f.listed(t, as, channelID)
	return [2]int64{channel.BranchUnreadCount, channel.OtherBranchUnreadCount}
}

// branchAs is the Branch on rootID in the account's page of the channel.
func (f fixture) branchAs(t *testing.T, as string, channelID, rootID int64) chatutil.Branch {
	t.Helper()
	page, err := chatutil.ListMessages(chatutil.ListMessagesParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as), ChannelID: channelID,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range page.Messages {
		if m.ID == rootID && m.Branch != nil {
			return *m.Branch
		}
	}
	t.Fatalf("root %d has no branch in %s's page", rootID, as)
	return chatutil.Branch{}
}

// TestBranchUnread counts a side conversation's unread replies per account
// (#4349): toward the channel's branch count for the root's author and for
// anyone who replied, toward the other count for everyone else, never an
// account's own replies, and only past its marker, which moves forward alone.
func TestBranchUnread(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	if err := f.set(t, "bob", room, f.users["dave"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	f.publishKeys(t, "dave")
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	var replies []int64
	for _, fill := range []byte{'a', 'b'} {
		reply, err := f.reply("carol", room, root.Message.ID, sealedMessage(fill, fill))
		if err != nil {
			t.Fatal(err)
		}
		replies = append(replies, reply.Message.ID)
	}

	for _, tc := range []struct {
		as       string
		counts   [2]int64
		unread   int64
		involved bool
	}{
		{as: "bob", counts: [2]int64{2, 0}, unread: 2, involved: true},
		{as: "carol", counts: [2]int64{0, 0}, unread: 0, involved: true},
		{as: "dave", counts: [2]int64{0, 2}, unread: 2},
	} {
		if got := f.branchCounts(t, tc.as, room); got != tc.counts {
			t.Errorf("%s's branch counts = %v, want %v", tc.as, got, tc.counts)
		}
		if got := f.branchAs(t, tc.as, room, root.Message.ID); got.UnreadCount != tc.unread || got.Involved != tc.involved {
			t.Errorf("%s's branch = %+v, want %d unread, involved %v", tc.as, got, tc.unread, tc.involved)
		}
	}
	if got := f.unread(t, "bob", room); got != 0 {
		t.Errorf("bob's channel unread = %d, want 0: replies stay out of it", got)
	}

	events, unsubscribe := f.bus.Subscribe("branch-read-marker-test")
	defer unsubscribe()
	result, err := f.markBranchRead("bob", root.Message.ID, replies[0])
	want := chatutil.MarkReadResult{ChannelID: room, RootID: root.Message.ID, LastReadMessageID: replies[0], UnreadCount: 1}
	if err != nil || result != want {
		t.Fatalf("mark branch read = %+v, %v; want %+v", result, err, want)
	}
	heard := f.readMarkerEvents(events)
	wantEvent := eventbus.ChatReadMarkerChanged{
		ChannelID: room, RootID: root.Message.ID, LastReadMessageID: replies[0], UnreadCount: 1, UserID: f.users["bob"],
	}
	if len(heard) != 1 || heard[0] != wantEvent {
		t.Errorf("events after a move = %+v, want %+v", heard, wantEvent)
	}
	if got := f.branchCounts(t, "bob", room); got != [2]int64{1, 0} {
		t.Errorf("bob's branch counts after reading one = %v, want [1 0]", got)
	}

	// Backward and in place change nothing and announce nothing.
	if result, err = f.markBranchRead("bob", root.Message.ID, replies[0]); err != nil || result != want {
		t.Errorf("mark branch read again = %+v, %v", result, err)
	}
	if heard := f.readMarkerEvents(events); len(heard) != 0 {
		t.Errorf("events after no move = %+v", heard)
	}
	if result, err = f.markBranchRead("bob", root.Message.ID, replies[1]); err != nil || result.UnreadCount != 0 {
		t.Errorf("mark branch read to the end = %+v, %v", result, err)
	}
	if result, err = f.markBranchRead("bob", root.Message.ID, replies[0]); err != nil || result.LastReadMessageID != replies[1] {
		t.Errorf("mark branch read backward = %+v, %v; want the marker left at %d", result, err, replies[1])
	}

	// Replying makes dave involved, and his own reply is never unread.
	if _, err := f.reply("dave", room, root.Message.ID, sealedMessage('d', 'd')); err != nil {
		t.Fatal(err)
	}
	if got := f.branchCounts(t, "dave", room); got != [2]int64{2, 0} {
		t.Errorf("dave's branch counts after replying = %v, want [2 0]", got)
	}
	if got := f.branchCounts(t, "bob", room); got != [2]int64{1, 0} {
		t.Errorf("bob's branch counts after dave replied = %v, want [1 0]", got)
	}
}

// TestBranchReadMarkerRefusals answers a root the caller can't read, and an
// id that is no reply to it, with ErrMessageNotFound, and drops an account's
// markers with the account (#4349).
func TestBranchReadMarkerRefusals(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	if err := f.set(t, "bob", room, f.users["dave"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	root, err := f.post("bob", room, sealedMessage('r', 'r'))
	if err != nil {
		t.Fatal(err)
	}
	other, err := f.post("bob", room, sealedMessage('o', 'o'))
	if err != nil {
		t.Fatal(err)
	}
	reply, err := f.reply("carol", room, root.Message.ID, sealedMessage('a', 'a'))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name          string
		as            string
		root, message int64
	}{
		{name: "non-member admin", as: "admin", root: root.Message.ID, message: reply.Message.ID},
		{name: "the root itself", as: "bob", root: root.Message.ID, message: root.Message.ID},
		{name: "another channel message", as: "bob", root: root.Message.ID, message: other.Message.ID},
		{name: "a reply to another root", as: "bob", root: other.Message.ID, message: reply.Message.ID},
		{name: "a reply as the root", as: "bob", root: reply.Message.ID, message: reply.Message.ID},
		{name: "no such root", as: "bob", root: 1 << 40, message: reply.Message.ID},
	} {
		if _, err := f.markBranchRead(tc.as, tc.root, tc.message); !errors.Is(err, chatutil.ErrMessageNotFound) {
			t.Errorf("%s = %v, want ErrMessageNotFound", tc.name, err)
		}
	}

	if _, err := f.markBranchRead("dave", root.Message.ID, reply.Message.ID); err != nil {
		t.Fatal(err)
	}
	markers := func() (n int) {
		t.Helper()
		if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM chat_branch_read_markers WHERE user_id = ?`, f.users["dave"]).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	if got := markers(); got != 1 {
		t.Fatalf("dave's markers = %d, want 1", got)
	}
	if err := f.database.Queries.DeleteUser(context.Background(), f.users["dave"]); err != nil {
		t.Fatal(err)
	}
	if got := markers(); got != 0 {
		t.Errorf("dave's markers after deleting the account = %d, want 0", got)
	}
}

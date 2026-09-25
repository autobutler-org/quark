package accessutil_test

import (
	"encoding/json"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func TestFilterEvent(t *testing.T) {
	f := newFixture(t)
	admin := f.load(t, accessutil.System)
	stranger := f.load(t, accessutil.Principal{UserID: createUser(t, f.database, "carol")})
	f.grant(t, f.userID, "", "shared", accessutil.Read)
	before := f.load(t, accessutil.Principal{UserID: f.userID})
	f.grant(t, f.userID, "", "moved/deep", accessutil.Read)
	after := f.load(t, accessutil.Principal{UserID: f.userID})

	move := func(from, to string) eventbus.Event {
		return eventbus.Event{Kind: eventbus.EventMove, Path: from, NewPath: to}
	}
	for _, tc := range []struct {
		name     string
		access   accessutil.Access
		previous accessutil.Access
		event    eventbus.Event
		want     *eventbus.Event
	}{
		{name: "admin hears backups", access: admin, event: eventbus.Event{Kind: eventbus.EventBackupStarted}},
		{name: "admin hears a private move", access: admin, event: move("private/a", "private/b")},
		{name: "trash changed", access: before, event: eventbus.Event{Kind: eventbus.EventTrashChanged, DeviceSerial: "USB-1"}},
		{name: "account changed", access: before, event: eventbus.Event{Kind: eventbus.EventAccountChanged}},
		{name: "backup dropped", access: before, event: eventbus.Event{Kind: eventbus.EventBackupProgress}, want: &eventbus.Event{}},
		{name: "vault dropped", access: before, event: eventbus.Event{Kind: eventbus.EventVaultStorageChanged}, want: &eventbus.Event{}},
		{name: "readable upload", access: before, event: eventbus.Event{Kind: eventbus.EventUpload, Path: "shared/sub"}},
		{name: "unreadable upload", access: before, event: eventbus.Event{Kind: eventbus.EventUpload, Path: "private"}, want: &eventbus.Event{}},
		{name: "upload at the root", access: before, event: eventbus.Event{Kind: eventbus.EventUpload}, want: &eventbus.Event{}},
		{name: "unknown serial", access: before, event: eventbus.Event{Kind: eventbus.EventDelete, Path: "shared/a", DeviceSerial: "USB-9"}, want: &eventbus.Event{}},
		{name: "move within readable", access: before, event: move("shared/a", "shared/b")},
		{
			name: "move into readable is an upload", access: before, event: move("private/a", "shared/sub/b"),
			want: &eventbus.Event{Kind: eventbus.EventUpload, Path: "shared/sub"},
		},
		{
			name: "move out of readable is a delete", access: before, event: move("shared/a", "private/b"),
			want: &eventbus.Event{Kind: eventbus.EventDelete, Path: "shared/a"},
		},
		{name: "move within unreadable", access: before, event: move("private/a", "b"), want: &eventbus.Event{}},
		{
			name: "access gained beneath", access: after, previous: before,
			event: eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "moved"},
		},
		{
			name: "access lost", access: stranger, previous: before,
			event: eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "shared"},
		},
		{
			name: "access changed with no path", access: stranger, previous: stranger,
			event: eventbus.Event{Kind: eventbus.EventAccessChanged},
		},
		{
			name: "access changed elsewhere", access: after, previous: before,
			event: eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "private"}, want: &eventbus.Event{},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := accessutil.FilterEvent(accessutil.FilterEventParams{Access: tc.access, Previous: tc.previous, Event: tc.event})
			want := tc.event
			if tc.want != nil {
				want = *tc.want
			}
			deliver := want.Kind != ""
			if got.Deliver != deliver || (deliver && got.Event != want) {
				t.Errorf("FilterEvent = %+v (deliver %v), want %+v (deliver %v)", got.Event, got.Deliver, want, deliver)
			}
		})
	}
}

// TestFilterEventChatChannelChanged passes chat_channel_changed only to its
// audience and to admins, and never sends the audience itself.
func TestFilterEventChatChannelChanged(t *testing.T) {
	f := newFixture(t)
	carol := createUser(t, f.database, "carol")
	member := f.load(t, accessutil.Principal{UserID: f.userID})
	stranger := f.load(t, accessutil.Principal{UserID: carol})
	admin := f.load(t, accessutil.Principal{UserID: createUser(t, f.database, "root"), IsAdmin: true})
	evt := eventbus.Event{
		Kind: eventbus.EventChatChannelChanged,
		Data: eventbus.ChatChannelChanged{ChannelID: 7, Audience: []int64{f.userID}},
	}

	for _, tc := range []struct {
		name   string
		access accessutil.Access
		event  eventbus.Event
		want   bool
	}{
		{name: "member", access: member, event: evt, want: true},
		{name: "admin", access: admin, event: evt, want: true},
		{name: "non-member", access: stranger, event: evt},
		{name: "no data", access: member, event: eventbus.Event{Kind: eventbus.EventChatChannelChanged}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := accessutil.FilterEvent(accessutil.FilterEventParams{Access: tc.access, Event: tc.event})
			if got.Deliver != tc.want {
				t.Errorf("Deliver = %v, want %v", got.Deliver, tc.want)
			}
		})
	}

	body, err := json.Marshal(evt)
	if err != nil {
		t.Fatal(err)
	}
	if want := `{"kind":"chat_channel_changed","data":{"channelId":7}}`; string(body) != want {
		t.Errorf("event JSON = %s, want %s", body, want)
	}
}

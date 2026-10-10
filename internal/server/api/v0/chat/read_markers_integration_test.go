package v0_chat_test

import (
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// unreadCount is the channel's unreadCount in the account's channel list.
func (h harness) unreadCount(t *testing.T, as string, channelID int64) int64 {
	t.Helper()
	var result chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", as, "", &result)
	for _, channel := range result.Channels {
		if channel.ID == channelID {
			return channel.UnreadCount
		}
	}
	t.Fatalf("%s doesn't list channel %d", as, channelID)
	return 0
}

func readBody(messageID int64) string {
	return `{"messageId":` + strconv.FormatInt(messageID, 10) + `}`
}

// TestChatReadMarkers_MarkReadClearsUnread posts as bob, has carol read
// (#2424), and checks the count in her channel list, the response's field
// names, the marker never moving backward, and the event her other sessions
// hear.
func TestChatReadMarkers_MarkReadClearsUnread(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	posted := make([]chatutil.Message, 3)
	for i, fill := range []byte{'1', '2', '3'} {
		h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob", messageBody(fill, 64, 1), &posted[i])
	}
	h.drain()

	if got := h.unreadCount(t, "carol", roomID); got != 3 {
		t.Fatalf("carol unreadCount = %d, want 3", got)
	}
	if got := h.unreadCount(t, "bob", roomID); got != 0 {
		t.Errorf("bob unreadCount of his own messages = %d, want 0", got)
	}

	code, body := h.do(t, http.MethodPut, room+"/read", "carol", readBody(posted[1].ID))
	want := `{"channelId":` + strconv.FormatInt(roomID, 10) + `,"lastReadMessageId":` + strconv.FormatInt(posted[1].ID, 10) + `,"unreadCount":1}`
	if code != http.StatusOK || strings.TrimSpace(body) != want {
		t.Fatalf("PUT read = %d %s, want 200 %s", code, body, want)
	}
	if got := h.unreadCount(t, "carol", roomID); got != 1 {
		t.Errorf("carol unreadCount after reading = %d, want 1", got)
	}
	var heard []eventbus.ChatReadMarkerChanged
	for _, evt := range h.drain() {
		if data, ok := evt.Data.(eventbus.ChatReadMarkerChanged); ok && evt.Kind == eventbus.EventChatReadMarkerChanged {
			heard = append(heard, data)
		}
	}
	wantEvent := eventbus.ChatReadMarkerChanged{ChannelID: roomID, LastReadMessageID: posted[1].ID, UnreadCount: 1, UserID: h.users["carol"]}
	if len(heard) != 1 || heard[0] != wantEvent {
		t.Errorf("events = %+v, want %+v", heard, wantEvent)
	}

	// An earlier id answers with the marker where it stands and says nothing.
	var result chatutil.MarkReadResult
	h.expect(t, http.StatusOK, http.MethodPut, room+"/read", "carol", readBody(posted[0].ID), &result)
	if result.LastReadMessageID != posted[1].ID || result.UnreadCount != 1 {
		t.Errorf("backward PUT = %+v, want the marker at %d", result, posted[1].ID)
	}
	if events := h.drain(); len(events) != 0 {
		t.Errorf("backward PUT published %+v", events)
	}

	h.expect(t, http.StatusOK, http.MethodPut, room+"/read", "carol", readBody(posted[2].ID), &result)
	if result.UnreadCount != 0 || h.unreadCount(t, "carol", roomID) != 0 {
		t.Errorf("reading to the end left %+v", result)
	}
}

// TestChatReadMarkers_Refusals checks who can't mark a channel read and what
// isn't a marker.
func TestChatReadMarkers_Refusals(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	// dave manages the channel without reading it.
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["dave"], "manage_members"), nil)
	var posted chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob", messageBody('1', 64, 1), &posted)

	for _, name := range []string{"dave", "admin"} {
		h.expect(t, http.StatusNotFound, http.MethodPut, room+"/read", name, readBody(posted.ID), nil)
	}
	if got := h.unreadCount(t, "dave", roomID); got != 0 {
		t.Errorf("a manager who can't read counts %d unread, want 0", got)
	}
	h.expect(t, http.StatusNotFound, http.MethodPut, "/chat/channels/999/read", "carol", readBody(posted.ID), nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, room+"/read", "carol", readBody(posted.ID+100), nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, room+"/read", "carol", `{}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, room+"/read", "carol", `not json`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, room+"/read", "carol", `{"messageId":"three"}`, nil)
	h.expect(t, http.StatusUnauthorized, http.MethodPut, room+"/read", "nobody", readBody(posted.ID), nil)
	if got := h.unreadCount(t, "carol", roomID); got != 1 {
		t.Errorf("carol unreadCount after refusals = %d, want 1", got)
	}
}

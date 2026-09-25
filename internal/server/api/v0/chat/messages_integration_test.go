package v0_chat_test

import (
	"encoding/base64"
	"net/http"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// messageBody is a post of n bytes of fill under keyVersion.
func messageBody(fill byte, n int, keyVersion int64) string {
	return `{"keyVersion":` + strconv.FormatInt(keyVersion, 10) + `,"ciphertext":"` + b64(fill, n) + `"}`
}

// roomWithKey has bob create a channel with key version 1 and returns its
// path.
func roomWithKey(t *testing.T, h harness) (int64, string) {
	t.Helper()
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "bob", keysBody('b', false), nil)
	var room chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"room"}`, &room)
	path := "/chat/channels/" + strconv.FormatInt(room.ID, 10)
	create := `{"version":1,"sealedKey":"` + b64('b', chatutil.SealedKeyBytes) + `","signature":"` + b64('b', chatutil.SignatureBytes) + `"}`
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys", "bob", create, nil)
	return room.ID, path
}

// ids lists a page's message ids.
func ids(page chatutil.ListMessagesResult) []int64 {
	out := make([]int64, 0, len(page.Messages))
	for _, m := range page.Messages {
		out = append(out, m.ID)
	}
	return out
}

// drainMessages empties the bus and returns the chat_message_created events
// it held, in order.
func (h harness) drainMessages() []eventbus.ChatMessageChanged {
	var heard []eventbus.ChatMessageChanged
	for {
		select {
		case evt := <-h.events:
			if data, ok := evt.Data.(eventbus.ChatMessageChanged); ok && evt.Kind == eventbus.EventChatMessageCreated {
				heard = append(heard, data)
			}
		default:
			return heard
		}
	}
}

// TestChatMessages_PostPageDelete posts, pages both ways, enforces the cap and
// levels, and tombstones.
func TestChatMessages_PostPageDelete(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	messages := room + "/messages"
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], "read"), nil)
	h.drainMessages()

	posted := make([]chatutil.Message, 0, 3)
	for _, fill := range []byte{'1', '2', '3'} {
		var m chatutil.Message
		h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody(fill, 64, 1), &m)
		posted = append(posted, m)
	}
	if m := posted[0]; m.ChannelID != roomID || m.AuthorID != h.users["bob"] || m.KeyVersion != 1 ||
		base64.StdEncoding.EncodeToString(m.Ciphertext) != b64('1', 64) {
		t.Errorf("stored = %+v", m)
	}
	heard := h.drainMessages()
	if len(heard) != 3 || heard[0].MessageID != posted[0].ID || heard[0].Message.(chatutil.Message).ID != posted[0].ID {
		t.Fatalf("heard = %+v", heard)
	}
	if audience := heard[0].Audience; len(audience) != 2 {
		t.Errorf("audience = %v, want bob and carol", audience)
	}
	for _, id := range heard[0].Audience {
		if id == h.users["admin"] {
			t.Errorf("admin is in the audience: %v", heard[0].Audience)
		}
	}

	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?limit=2", "carol", "", &page)
	if got := ids(page); len(got) != 2 || got[0] != posted[1].ID || got[1] != posted[2].ID {
		t.Errorf("newest page = %v", got)
	}
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?limit=2&before="+strconv.FormatInt(posted[1].ID, 10), "carol", "", &page)
	if got := ids(page); len(got) != 1 || got[0] != posted[0].ID {
		t.Errorf("older page = %v", got)
	}
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after="+strconv.FormatInt(posted[0].ID, 10), "carol", "", &page)
	if got := ids(page); len(got) != 2 || got[0] != posted[1].ID {
		t.Errorf("after page = %v", got)
	}
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0&limit=1", "carol", "", &page)
	if got := ids(page); len(got) != 1 || got[0] != posted[0].ID {
		t.Errorf("first page = %v", got)
	}

	// Levels: carol reads but can't post; a non-member admin gets 404.
	h.expect(t, http.StatusForbidden, http.MethodPost, messages, "carol", messageBody('c', 64, 1), nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, messages, "admin", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodPost, messages, "admin", messageBody('a', 64, 1), nil)

	// The cap, whether the service or the body reader catches it.
	h.expect(t, http.StatusRequestEntityTooLarge, http.MethodPost, messages, "bob", messageBody('x', chatutil.MaxCiphertextBytes+1, 1), nil)
	h.expect(t, http.StatusRequestEntityTooLarge, http.MethodPost, messages, "bob", messageBody('x', 64<<10, 1), nil)
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody('x', chatutil.MaxCiphertextBytes, 1), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, messages, "bob", messageBody('x', 64, 2), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, messages, "bob", messageBody('x', 8, 1), nil)

	// Deleting: the author or an owner, nobody else.
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], "write"), nil)
	var carols chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "carol", messageBody('c', 64, 1), &carols)
	bobs := "/chat/messages/" + strconv.FormatInt(posted[0].ID, 10)
	h.expect(t, http.StatusForbidden, http.MethodDelete, bobs, "carol", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, bobs, "admin", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/messages/999999", "bob", "", nil)
	var tomb chatutil.Message
	h.expect(t, http.StatusOK, http.MethodDelete, bobs, "bob", "", &tomb)
	if tomb.DeletedAt == nil || tomb.Ciphertext != nil {
		t.Errorf("tombstone = %+v", tomb)
	}
	h.expect(t, http.StatusOK, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(carols.ID, 10), "carol", "", nil)
	var paged chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0&limit=1", "carol", "", &paged)
	if got := paged.Messages; len(got) != 1 || got[0].DeletedAt == nil || got[0].Ciphertext != nil {
		t.Errorf("paged tombstone = %+v", got)
	}

	// Deleting the channel deletes its messages.
	h.expect(t, http.StatusNoContent, http.MethodDelete, room, "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(posted[1].ID, 10), "bob", "", nil)
}

// TestChatMessages_BurstCatchUp posts more messages than a subscriber's
// 16-slot buffer holds without reading any, so the bus drops some, and then
// catches up the way the app does: ?after= the last id it heard.
func TestChatMessages_BurstCatchUp(t *testing.T) {
	h := newHarness(t)
	_, room := roomWithKey(t, h)
	messages := room + "/messages"
	h.drainMessages()

	const burst = 20
	want := make([]int64, 0, burst)
	for i := range burst {
		var m chatutil.Message
		h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody(byte('a'+i), 64, 1), &m)
		want = append(want, m.ID)
	}
	heard := h.drainMessages()
	if len(heard) >= burst {
		t.Fatalf("heard all %d; the bus should have dropped some", len(heard))
	}
	got := map[int64]bool{}
	last := int64(0)
	for _, data := range heard {
		got[data.MessageID] = true
		last = max(last, data.MessageID)
	}
	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after="+strconv.FormatInt(last, 10), "bob", "", &page)
	for _, id := range ids(page) {
		got[id] = true
	}
	for _, id := range want {
		if !got[id] {
			t.Errorf("message %d missing after catch-up", id)
		}
	}
}

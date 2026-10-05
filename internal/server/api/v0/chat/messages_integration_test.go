package v0_chat_test

import (
	"encoding/base64"
	"net/http"
	"strconv"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
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
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys", "bob", createKeyBody('b', room.ID, 1, h.users["bob"]), nil)
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
	for _, evt := range h.drain() {
		if data, ok := evt.Data.(eventbus.ChatMessageChanged); ok && evt.Kind == eventbus.EventChatMessageCreated {
			heard = append(heard, data)
		}
	}
	return heard
}

// TestChatMessages_PostPageDelete posts, pages both ways, enforces the cap and
// permissions, and tombstones.
func TestChatMessages_PostPageDelete(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	messages := room + "/messages"
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	// dave manages the channel without reading it: he sees it and its members,
	// and none of its messages.
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["dave"], "manage_members"), nil)
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
		if id == h.users["admin"] || id == h.users["dave"] {
			t.Errorf("admin or the delegated manager is in the audience: %v", heard[0].Audience)
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

	// Permissions: carol reads but can't post; a non-member admin and the
	// delegated manager get 404, though dave still sees the channel.
	h.expect(t, http.StatusForbidden, http.MethodPost, messages, "carol", messageBody('c', 64, 1), nil)
	for _, as := range []string{"admin", "dave"} {
		h.expect(t, http.StatusNotFound, http.MethodGet, messages, as, "", nil)
		h.expect(t, http.StatusNotFound, http.MethodPost, messages, as, messageBody('a', 64, 1), nil)
		h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(posted[2].ID, 10), as, "", nil)
	}
	h.expect(t, http.StatusOK, http.MethodGet, room+"/members", "dave", "", nil)

	// The cap, whether the service or the body reader catches it.
	h.expect(t, http.StatusRequestEntityTooLarge, http.MethodPost, messages, "bob", messageBody('x', chatutil.MaxCiphertextBytes+1, 1), nil)
	h.expect(t, http.StatusRequestEntityTooLarge, http.MethodPost, messages, "bob", messageBody('x', 64<<10, 1), nil)
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody('x', chatutil.MaxCiphertextBytes, 1), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, messages, "bob", messageBody('x', 64, 2), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, messages, "bob", messageBody('x', 8, 1), nil)

	// Deleting: the author, or a holder of delete_messages, nobody else.
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], member...), nil)
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
	// A moderator deletes someone else's message.
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], append(member, "delete_messages")...), nil)
	h.expect(t, http.StatusOK, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(posted[1].ID, 10), "carol", "", nil)
	// An author demoted to a manage-only set can't reach back in.
	var carolsLast chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "carol", messageBody('d', 64, 1), &carolsLast)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], "manage_members"), nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(carolsLast.ID, 10), "carol", "", nil)
	var paged chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0&limit=1", "bob", "", &paged)
	if got := paged.Messages; len(got) != 1 || got[0].DeletedAt == nil || got[0].Ciphertext != nil {
		t.Errorf("paged tombstone = %+v", got)
	}

	// Deleting the channel deletes its messages.
	h.expect(t, http.StatusNoContent, http.MethodDelete, room, "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(posted[1].ID, 10), "bob", "", nil)
}

// TestChatMessages_BurstCatchUp posts more messages than an app socket's
// 16-slot buffer holds without reading any, so the bus swaps the backlog for
// a resync (#2753), and then catches up the way the app does after one: the
// whole page again.
func TestChatMessages_BurstCatchUp(t *testing.T) {
	h := newHarness(t)
	_, room := roomWithKey(t, h)
	messages := room + "/messages"
	socket, unsub := h.deps.EventBus().SubscribeLossy("burst-catch-up")
	defer unsub()

	const burst = 20
	want := make([]int64, 0, burst)
	for i := range burst {
		var m chatutil.Message
		h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody(byte('a'+i), 64, 1), &m)
		want = append(want, m.ID)
	}
	resynced, heard := false, 0
	for drained := false; !drained; {
		select {
		case evt := <-socket:
			switch evt.Kind {
			case eventbus.EventResync:
				resynced = true
			case eventbus.EventChatMessageCreated:
				heard++
			}
		default:
			drained = true
		}
	}
	if !resynced || heard >= burst {
		t.Fatalf("resync = %v after hearing %d of %d; the socket should have fallen behind", resynced, heard, burst)
	}
	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0", "bob", "", &page)
	got := map[int64]bool{}
	for _, id := range ids(page) {
		got[id] = true
	}
	for _, id := range want {
		if !got[id] {
			t.Errorf("message %d missing after catch-up", id)
		}
	}
}

// TestChatWrites_RateLimited gives bob a two-request budget per route and
// checks the third write is a 429, that each route has its own bucket, and
// that carol's budget isn't bob's (#2485).
func TestChatWrites_RateLimited(t *testing.T) {
	h := newHarness(t)
	roomID, path := roomWithKey(t, h)
	h.deps.WithChatRateLimiter(ratelimitutil.NewWithRate(0, 2))
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "carol", keysBody('c', false), nil)
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "bob", userBody(h.users["carol"], "read_messages", "send_messages"), nil)

	for i := range 2 {
		h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "bob", messageBody(byte('m'+i), 64, 1), nil)
	}
	h.expect(t, http.StatusTooManyRequests, http.MethodPost, path+"/messages", "bob", messageBody('o', 64, 1), nil)
	h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "carol", messageBody('o', 64, 1), nil)

	grants := `{"grants":[` + grantBody('b', roomID, 1, h.users["carol"], 'x') + `]}`
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys/grants", "bob", grants, nil)
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys/grants", "bob", grants, nil)
	h.expect(t, http.StatusTooManyRequests, http.MethodPost, path+"/keys/grants", "bob", grants, nil)

	create := createKeyBody('b', roomID, 2, h.users["bob"])
	h.expect(t, http.StatusConflict, http.MethodPost, path+"/keys", "bob", create, nil)
	h.expect(t, http.StatusConflict, http.MethodPost, path+"/keys", "bob", create, nil)
	h.expect(t, http.StatusTooManyRequests, http.MethodPost, path+"/keys", "bob", create, nil)
}

// TestChatMessages_ReplayConflicts posts a ciphertext and replays it (#2487):
// the author repeating the exact post gets the stored message back with 200,
// and another member replaying it, including many at once, gets 409.
func TestChatMessages_ReplayConflicts(t *testing.T) {
	h := newHarness(t)
	_, room := roomWithKey(t, h)
	messages := room + "/messages"
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], member...), nil)

	var first, again chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody('r', 64, 1), &first)
	h.expect(t, http.StatusOK, http.MethodPost, messages, "bob", messageBody('r', 64, 1), &again)
	if again.ID != first.ID {
		t.Errorf("repeated post = message %d, want %d", again.ID, first.ID)
	}
	h.expect(t, http.StatusConflict, http.MethodPost, messages, "carol", messageBody('r', 64, 1), nil)
	// The nonce is the first 24 bytes, so a longer body of the same fill
	// reuses it.
	h.expect(t, http.StatusConflict, http.MethodPost, messages, "bob", messageBody('r', 80, 1), nil)

	var wg sync.WaitGroup
	codes := make([]int, 8)
	for i := range codes {
		wg.Go(func() { codes[i], _ = h.do(t, http.MethodPost, messages, "carol", messageBody('s', 64, 1)) })
	}
	wg.Wait()
	created := 0
	for _, code := range codes {
		switch code {
		case http.StatusCreated:
			created++
		case http.StatusOK, http.StatusConflict:
		default:
			t.Errorf("concurrent replay = %d", code)
		}
	}
	if created != 1 {
		t.Errorf("concurrent replays created %d messages, want 1 (%v)", created, codes)
	}
	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages, "bob", "", &page)
	if len(page.Messages) != 2 {
		t.Errorf("channel holds %d messages, want 2", len(page.Messages))
	}
}

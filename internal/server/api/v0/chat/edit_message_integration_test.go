package v0_chat_test

import (
	"bytes"
	"net/http"
	"slices"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// TestChatMessages_Edit edits as the author alone, while they still read the
// channel, tells the readers with the edited row, keeps the nonce rules, and
// refuses deleted messages and polls (#2426).
func TestChatMessages_Edit(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	messages := room + "/messages"
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], append(member, "delete_messages")...), nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["dave"], "manage_members"), nil)
	var original, other chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "carol", messageBody('m', 64, 1), &original)
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody('o', 64, 1), &other)
	path := "/chat/messages/" + strconv.FormatInt(original.ID, 10)
	h.drain()

	// The author edits: new ciphertext, editedAt set, readers hear the row.
	var edited chatutil.Message
	h.expect(t, http.StatusOK, http.MethodPut, path, "carol", messageBody('e', 64, 1), &edited)
	if edited.ID != original.ID || edited.EditedAt == nil || !bytes.Equal(edited.Ciphertext, bytes.Repeat([]byte{'e'}, 64)) {
		t.Fatalf("edited = %+v", edited)
	}
	var heard []eventbus.ChatMessageChanged
	for _, evt := range h.drain() {
		if data, ok := evt.Data.(eventbus.ChatMessageChanged); ok && evt.Kind == eventbus.EventChatMessageEdited {
			heard = append(heard, data)
		}
	}
	if len(heard) != 1 || heard[0].ChannelID != roomID || heard[0].Message.(chatutil.Message).EditedAt == nil {
		t.Fatalf("heard = %+v", heard)
	}
	if audience := heard[0].Audience; slices.Contains(audience, h.users["dave"]) || slices.Contains(audience, h.users["admin"]) {
		t.Errorf("audience = %v, want readers alone", audience)
	}
	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0", "bob", "", &page)
	if page.Messages[0].EditedAt == nil || !bytes.Equal(page.Messages[0].Ciphertext, edited.Ciphertext) {
		t.Errorf("page = %+v", page.Messages[0])
	}

	// Only the author: not another reader, even one holding delete_messages
	// or every permission, and a non-reader or admin not at all.
	h.expect(t, http.StatusForbidden, http.MethodPut, "/chat/messages/"+strconv.FormatInt(other.ID, 10), "carol", messageBody('x', 64, 1), nil)
	h.expect(t, http.StatusForbidden, http.MethodPut, path, "bob", messageBody('x', 64, 1), nil)
	for _, as := range []string{"admin", "dave"} {
		h.expect(t, http.StatusNotFound, http.MethodPut, path, as, messageBody('x', 64, 1), nil)
	}

	// A read-only author still edits: editing is authorship, not
	// send_messages. One who lost read_messages cannot reach back in.
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	h.expect(t, http.StatusOK, http.MethodPut, path, "carol", messageBody('v', 64, 1), nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], "manage_members"), nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, path, "carol", messageBody('w', 64, 1), nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], member...), nil)

	// Ciphertext rules: size, key version, and another message's nonce.
	h.expect(t, http.StatusBadRequest, http.MethodPut, path, "carol", messageBody('s', 8, 1), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, path, "carol", messageBody('k', 64, 2), nil)
	h.expect(t, http.StatusRequestEntityTooLarge, http.MethodPut, path, "carol", messageBody('l', chatutil.MaxCiphertextBytes+1, 1), nil)
	h.expect(t, http.StatusConflict, http.MethodPut, path, "carol", messageBody('o', 64, 1), nil)
	// The message's own nonce again is a retry of the same edit.
	h.expect(t, http.StatusOK, http.MethodPut, path, "carol", messageBody('v', 64, 1), nil)
	// What it says now is held to the index: a post repeating it is refused.
	h.expect(t, http.StatusConflict, http.MethodPost, messages, "bob", messageBody('v', 64, 1), nil)

	// A poll keeps the question its answers were given to.
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "carol", pollBody('p', `{"allowChange":true}`), &poll)
	h.expect(t, http.StatusConflict, http.MethodPut, "/chat/messages/"+strconv.FormatInt(poll.ID, 10), "carol", messageBody('q', 64, 1), nil)

	// A deleted message stays a tombstone.
	h.expect(t, http.StatusOK, http.MethodDelete, path, "carol", "", nil)
	h.expect(t, http.StatusConflict, http.MethodPut, path, "carol", messageBody('d', 64, 1), nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, "/chat/messages/999999", "carol", messageBody('d', 64, 1), nil)
}

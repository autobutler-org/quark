package v0_chat_test

import (
	"net/http"
	"slices"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// drainReactions empties the bus and returns the chat_reaction_changed events
// it held, in order.
func (h harness) drainReactions() []eventbus.ChatReactionChanged {
	var heard []eventbus.ChatReactionChanged
	for _, evt := range h.drain() {
		if data, ok := evt.Data.(eventbus.ChatReactionChanged); ok && evt.Kind == eventbus.EventChatReactionChanged {
			heard = append(heard, data)
		}
	}
	return heard
}

// TestChatReactions_AddListRemove adds and removes reactions, enforces
// add_reactions and manage_reactions, delivers events to readers alone, pages
// reactions with their messages, and drops them with a deleted message.
func TestChatReactions_AddListRemove(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	messages := room + "/messages"
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], member...), nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["dave"], "manage_members"), nil)
	var message chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody('m', 64, 1), &message)
	reactions := "/chat/messages/" + strconv.FormatInt(message.ID, 10) + "/reactions"
	h.drainReactions()

	var carols chatutil.Reaction
	h.expect(t, http.StatusCreated, http.MethodPost, reactions, "carol", messageBody('r', 48, 1), &carols)
	if carols.MessageID != message.ID || carols.UserID != h.users["carol"] || carols.KeyVersion != 1 {
		t.Errorf("stored = %+v", carols)
	}
	heard := h.drainReactions()
	if len(heard) != 1 || heard[0].ChannelID != roomID || heard[0].ReactionID != carols.ID ||
		heard[0].Reaction.(chatutil.Reaction).ID != carols.ID {
		t.Fatalf("heard = %+v", heard)
	}
	if audience := heard[0].Audience; len(audience) != 2 ||
		slices.Contains(audience, h.users["admin"]) || slices.Contains(audience, h.users["dave"]) {
		t.Errorf("audience = %v, want bob and carol", audience)
	}

	// Catch-up: a page carries each message's reactions.
	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0", "bob", "", &page)
	if len(page.Messages) != 1 || len(page.Messages[0].Reactions) != 1 || page.Messages[0].Reactions[0].ID != carols.ID {
		t.Errorf("page = %+v", page.Messages)
	}

	// Validation: size, key version, and the per-account cap.
	h.expect(t, http.StatusBadRequest, http.MethodPost, reactions, "carol", messageBody('r', 8, 1), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, reactions, "carol", messageBody('r', chatutil.MaxReactionCiphertextBytes+1, 1), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, reactions, "carol", messageBody('r', 48, 2), nil)
	for range chatutil.MaxReactionsPerUser - 1 {
		h.expect(t, http.StatusCreated, http.MethodPost, reactions, "carol", messageBody('r', 48, 1), nil)
	}
	h.expect(t, http.StatusConflict, http.MethodPost, reactions, "carol", messageBody('r', 48, 1), nil)

	// Who may react: not a delegated manager or a non-member admin (404), not
	// a reader without add_reactions (403).
	for _, as := range []string{"admin", "dave"} {
		h.expect(t, http.StatusNotFound, http.MethodPost, reactions, as, messageBody('r', 48, 1), nil)
		h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/reactions/"+strconv.FormatInt(carols.ID, 10), as, "", nil)
	}
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	h.expect(t, http.StatusForbidden, http.MethodPost, reactions, "carol", messageBody('r', 48, 1), nil)
	h.expect(t, http.StatusForbidden, http.MethodDelete, "/chat/reactions/"+strconv.FormatInt(carols.ID, 10), "carol", "", nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], member...), nil)

	// Removing: your own with add_reactions; someone else's needs
	// manage_reactions.
	var bobs chatutil.Reaction
	h.expect(t, http.StatusCreated, http.MethodPost, reactions, "bob", messageBody('b', 48, 1), &bobs)
	h.expect(t, http.StatusForbidden, http.MethodDelete, "/chat/reactions/"+strconv.FormatInt(bobs.ID, 10), "carol", "", nil)
	h.drainReactions()
	h.expect(t, http.StatusOK, http.MethodDelete, "/chat/reactions/"+strconv.FormatInt(carols.ID, 10), "carol", "", nil)
	if heard := h.drainReactions(); len(heard) != 1 || heard[0].ReactionID != carols.ID || heard[0].Reaction != nil {
		t.Errorf("removal heard = %+v", heard)
	}
	h.expect(t, http.StatusNotFound, http.MethodDelete, "/chat/reactions/"+strconv.FormatInt(carols.ID, 10), "carol", "", nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], append(member, "manage_reactions")...), nil)
	h.expect(t, http.StatusOK, http.MethodDelete, "/chat/reactions/"+strconv.FormatInt(bobs.ID, 10), "carol", "", nil)
	// manage_reactions without read_messages is an incoherent set.
	h.expect(t, http.StatusUnprocessableEntity, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], "manage_reactions"), nil)

	// Deleting the message drops its reactions, and it takes no new ones.
	h.expect(t, http.StatusOK, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(message.ID, 10), "bob", "", nil)
	var after chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages+"?after=0", "bob", "", &after)
	if len(after.Messages) != 1 || after.Messages[0].DeletedAt == nil || after.Messages[0].Reactions != nil {
		t.Errorf("tombstone = %+v", after.Messages)
	}
	h.expect(t, http.StatusConflict, http.MethodPost, reactions, "bob", messageBody('b', 48, 1), nil)
	h.expect(t, http.StatusNotFound, http.MethodPost, "/chat/messages/999999/reactions", "bob", messageBody('b', 48, 1), nil)
}

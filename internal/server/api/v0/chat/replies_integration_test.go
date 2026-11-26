package v0_chat_test

import (
	"context"
	"net/http"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// replyBody is a post of n bytes of fill under key version 1, as a reply in
// rootID's side conversation, with extra JSON fields after it.
func replyBody(fill byte, rootID int64, extra string) string {
	return `{"keyVersion":1,"ciphertext":"` + b64(fill, 64) + `","rootId":` + strconv.FormatInt(rootID, 10) + extra + `}`
}

// TestChatReplies_PostAndPage posts into a side conversation over HTTP, pages
// it, keeps it out of the channel's page, and answers each refusal with its
// own status (#4345).
func TestChatReplies_PostAndPage(t *testing.T) {
	h := newHarness(t)
	_, room := roomWithKey(t, h)
	messages := room + "/messages"
	var other chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"other"}`, &other)
	otherPath := "/chat/channels/" + strconv.FormatInt(other.ID, 10)
	h.expect(t, http.StatusOK, http.MethodPost, otherPath+"/keys", "bob", createKeyBody('b', other.ID, 1, h.users["bob"]), nil)
	var root, elsewhere, reply chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", messageBody('r', 64, 1), &root)
	h.expect(t, http.StatusCreated, http.MethodPost, otherPath+"/messages", "bob", messageBody('e', 64, 1), &elsewhere)
	h.expect(t, http.StatusCreated, http.MethodPost, messages, "bob", replyBody('a', root.ID, ""), &reply)
	if reply.RootID != root.ID {
		t.Errorf("stored rootId = %d, want %d", reply.RootID, root.ID)
	}

	h.expect(t, http.StatusNotFound, http.MethodPost, messages, "bob", replyBody('x', elsewhere.ID, ""), nil)
	h.expect(t, http.StatusConflict, http.MethodPost, messages, "bob", replyBody('y', reply.ID, ""), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, messages, "bob", replyBody('z', root.ID, `,"poll":{}`), nil)

	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, messages, "bob", "", &page)
	if got := ids(page); len(got) != 1 || got[0] != root.ID {
		t.Errorf("channel page = %v, want only the root %d", got, root.ID)
	}
	replies := "/chat/messages/" + strconv.FormatInt(root.ID, 10) + "/replies"
	h.expect(t, http.StatusOK, http.MethodGet, replies, "bob", "", &page)
	if got := ids(page); len(got) != 1 || got[0] != reply.ID {
		t.Errorf("replies = %v, want %d", got, reply.ID)
	}
	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/messages/999999/replies", "bob", "", nil)
}

// TestChatReplies_DirectMessageKeepsAdminOut checks a non-member admin gets
// 404 on the replies route of a direct message, and that the event for a
// reply there never reaches the admin's stream (#4345).
func TestChatReplies_DirectMessageKeepsAdminOut(t *testing.T) {
	h := newHarness(t)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "bob", keysBody('b', false), nil)
	var dm chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/dms", "bob", `{"userIds":[`+strconv.FormatInt(h.users["carol"], 10)+`]}`, &dm)
	path := "/chat/channels/" + strconv.FormatInt(dm.ID, 10)
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys", "bob", createKeyBody('b', dm.ID, 1, h.users["bob"]), nil)
	var root, reply chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "bob", messageBody('r', 64, 1), &root)
	h.drain()
	h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "bob", replyBody('a', root.ID, ""), &reply)

	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/messages/"+strconv.FormatInt(root.ID, 10)+"/replies", "admin", "", nil)

	admin, err := accessutil.Load(accessutil.LoadParams{
		Ctx: context.Background(), Principal: accessutil.Principal{UserID: h.users["admin"], IsAdmin: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	heard := 0
	for _, evt := range h.drain() {
		changed, ok := evt.Data.(eventbus.ChatMessageChanged)
		if !ok || evt.Kind != eventbus.EventChatMessageCreated {
			continue
		}
		heard++
		if changed.RootID != root.ID {
			t.Errorf("event rootId = %d, want %d", changed.RootID, root.ID)
		}
		if accessutil.FilterEvent(accessutil.FilterEventParams{Access: admin.Access, Event: evt}).Deliver {
			t.Errorf("the admin's event stream delivers a reply in a direct message: %+v", changed)
		}
	}
	if heard != 1 {
		t.Errorf("heard %d chat_message_created events for the reply, want 1", heard)
	}
}

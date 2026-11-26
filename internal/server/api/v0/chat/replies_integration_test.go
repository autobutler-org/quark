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
	if got := page.Messages[0].Branch; got == nil || got.ReplyCount != 1 || !got.LastReplyAt.Equal(reply.CreatedAt) {
		t.Errorf("root's branch = %+v, want 1 reply at %v (#4346)", got, reply.CreatedAt)
	}
	replies := "/chat/messages/" + strconv.FormatInt(root.ID, 10) + "/replies"
	h.expect(t, http.StatusOK, http.MethodGet, replies, "bob", "", &page)
	if got := ids(page); len(got) != 1 || got[0] != reply.ID {
		t.Errorf("replies = %v, want %d", got, reply.ID)
	}
	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/messages/999999/replies", "bob", "", nil)

	var branches chatutil.ListBranchesResult
	h.expect(t, http.StatusOK, http.MethodGet, room+"/branches", "bob", "", &branches)
	if got := branches.Messages; len(got) != 1 || got[0].ID != root.ID || got[0].Branch == nil || got[0].Branch.ReplyCount != 1 {
		t.Errorf("branches = %+v, want the root %d with 1 reply (#4351)", got, root.ID)
	}
}

// TestChatReplies_DirectMessageKeepsAdminOut checks a non-member admin gets
// 404 on the replies and branches routes of a direct message (#4351), and that the event for a
// reply there, and the root's chat_branch_changed, never reach the admin's
// stream (#4345, #4346).
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
	h.expect(t, http.StatusNotFound, http.MethodGet, path+"/branches", "admin", "", nil)

	admin, err := accessutil.Load(accessutil.LoadParams{
		Ctx: context.Background(), Principal: accessutil.Principal{UserID: h.users["admin"], IsAdmin: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	heard, branched := 0, 0
	for _, evt := range h.drain() {
		if evt.Kind == eventbus.EventChatBranchChanged {
			branched++
			if accessutil.FilterEvent(accessutil.FilterEventParams{Access: admin.Access, Event: evt}).Deliver {
				t.Errorf("the admin's event stream delivers a direct message's branch: %+v", evt.Data)
			}
			continue
		}
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
	if heard != 1 || branched != 1 {
		t.Errorf("heard %d chat_message_created and %d chat_branch_changed for the reply, want 1 each", heard, branched)
	}
}

// TestChatReplies_BranchReadMarker reads a direct message's side conversation
// over HTTP (#4349): carol, who is not involved, sees its reply in her other
// branch count, and reading it clears the count and tells her own sessions
// alone. A non-member admin gets 404 and hears nothing.
func TestChatReplies_BranchReadMarker(t *testing.T) {
	h := newHarness(t)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "bob", keysBody('b', false), nil)
	var dm chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/dms", "bob", `{"userIds":[`+strconv.FormatInt(h.users["carol"], 10)+`]}`, &dm)
	path := "/chat/channels/" + strconv.FormatInt(dm.ID, 10)
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys", "bob", createKeyBody('b', dm.ID, 1, h.users["bob"]), nil)
	var root, reply chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "bob", messageBody('r', 64, 1), &root)
	h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "bob", replyBody('a', root.ID, ""), &reply)

	branchCounts := func(as string) [2]int64 {
		t.Helper()
		var list chatutil.ListChannelsResult
		h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", as, "", &list)
		for _, c := range list.Channels {
			if c.ID == dm.ID {
				return [2]int64{c.BranchUnreadCount, c.OtherBranchUnreadCount}
			}
		}
		return [2]int64{-1, -1}
	}
	if got := branchCounts("carol"); got != [2]int64{0, 1} {
		t.Fatalf("carol's branch counts = %v, want [0 1]", got)
	}
	h.drain()

	read := "/chat/messages/" + strconv.FormatInt(root.ID, 10) + "/read"
	body := `{"messageId":` + strconv.FormatInt(reply.ID, 10) + `}`
	h.expect(t, http.StatusNotFound, http.MethodPut, read, "admin", body, nil)
	var marker chatutil.MarkReadResult
	h.expect(t, http.StatusOK, http.MethodPut, read, "carol", body, &marker)
	if want := (chatutil.MarkReadResult{ChannelID: dm.ID, RootID: root.ID, LastReadMessageID: reply.ID}); marker != want {
		t.Errorf("marker = %+v, want %+v", marker, want)
	}
	if got := branchCounts("carol"); got != [2]int64{0, 0} {
		t.Errorf("carol's branch counts after reading = %v, want [0 0]", got)
	}

	load := func(name string) accessutil.Access {
		t.Helper()
		loaded, err := accessutil.Load(accessutil.LoadParams{
			Ctx: context.Background(), Principal: accessutil.Principal{UserID: h.users[name], IsAdmin: name == "admin"},
		})
		if err != nil {
			t.Fatal(err)
		}
		return loaded.Access
	}
	heard := 0
	for _, evt := range h.drain() {
		if evt.Kind != eventbus.EventChatReadMarkerChanged {
			continue
		}
		heard++
		for name, want := range map[string]bool{"carol": true, "bob": false, "admin": false} {
			if got := accessutil.FilterEvent(accessutil.FilterEventParams{Access: load(name), Event: evt}).Deliver; got != want {
				t.Errorf("%s hears the branch marker = %v, want %v", name, got, want)
			}
		}
	}
	if heard != 1 {
		t.Errorf("heard %d chat_read_marker_changed, want 1", heard)
	}
}

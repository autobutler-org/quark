package v0_chat_test

import (
	"net/http"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
)

// TestChatTyping_Ephemeral sends typing from senders alone, to the other
// readers alone, stores nothing, and is rate-limited (#2426).
func TestChatTyping_Ephemeral(t *testing.T) {
	h := newHarness(t)
	roomID, room := roomWithKey(t, h)
	typing := room + "/typing"
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["dave"], "manage_members"), nil)
	h.drain()

	heard := func() []eventbus.ChatTyping {
		var got []eventbus.ChatTyping
		for _, evt := range h.drain() {
			if data, ok := evt.Data.(eventbus.ChatTyping); ok && evt.Kind == eventbus.EventChatTyping {
				got = append(got, data)
			}
		}
		return got
	}

	h.expect(t, http.StatusNoContent, http.MethodPost, typing, "bob", "", nil)
	got := heard()
	if len(got) != 1 || got[0].ChannelID != roomID || got[0].UserID != h.users["bob"] {
		t.Fatalf("heard = %+v", got)
	}
	// carol reads; bob typed, and dave and admin don't read.
	if audience := got[0].Audience; !slices.Equal(audience, []int64{h.users["carol"]}) {
		t.Errorf("audience = %v, want carol alone", audience)
	}

	// A reader without send_messages can't type, a non-reader can't see it.
	h.expect(t, http.StatusForbidden, http.MethodPost, typing, "carol", "", nil)
	for _, as := range []string{"admin", "dave"} {
		h.expect(t, http.StatusNotFound, http.MethodPost, typing, as, "", nil)
	}
	if got := heard(); len(got) != 0 {
		t.Errorf("refused typing was heard: %+v", got)
	}

	// Nothing is stored: the channel has no messages after it.
	var page struct {
		Messages []any `json:"messages"`
	}
	h.expect(t, http.StatusOK, http.MethodGet, room+"/messages?after=0", "bob", "", &page)
	if len(page.Messages) != 0 {
		t.Errorf("messages = %v", page.Messages)
	}

	// The chat limiter on Dependencies bounds it per account.
	h.deps.WithChatRateLimiter(ratelimitutil.NewWithRate(0, 2))
	for range 2 {
		h.expect(t, http.StatusNoContent, http.MethodPost, typing, "bob", "", nil)
	}
	h.expect(t, http.StatusTooManyRequests, http.MethodPost, typing, "bob", "", nil)
	if got := heard(); len(got) != 2 {
		t.Errorf("heard %d, want the 2 the limiter let through", len(got))
	}
}

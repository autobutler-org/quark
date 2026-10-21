package v0_chat_test

import (
	"net/http"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
)

// stuckGeneral publishes keys for every account and has bob, alone, start
// general's key: the channel #3455 describes, where bob signs out and
// everyone else waits on him. It returns general's id and keys path.
func stuckGeneral(t *testing.T, h harness) (int64, string) {
	t.Helper()
	for name, fill := range map[string]byte{"admin": 'a', "bob": 'b', "carol": 'c', "dave": 'd'} {
		h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", name, keysBody(fill, false), nil)
	}
	var channels chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", "bob", "", &channels)
	general := channels.Channels[0].ID
	keysPath := "/chat/channels/" + strconv.FormatInt(general, 10) + "/keys"
	h.expect(t, http.StatusOK, http.MethodPost, keysPath, "bob", createKeyBody('b', general, 1, h.users["bob"]), nil)
	return general, keysPath
}

// TestChatChannelKeys_AdminRegenerates walks #3455: with bob, the only
// holder, away, a non-admin can't regenerate, an admin can, once, and the
// admin then grants the new version to every member with keys, bob included.
func TestChatChannelKeys_AdminRegenerates(t *testing.T) {
	h := newHarness(t)
	general, keysPath := stuckGeneral(t, h)
	regenerate := keysPath + "/regenerate"

	// Nobody but an admin, however much they hold in the channel.
	h.expect(t, http.StatusForbidden, http.MethodPost, regenerate, "carol", createKeyBody('c', general, 2, h.users["carol"]), nil)
	// The ordinary route still refuses a version nobody needs.
	h.expect(t, http.StatusConflict, http.MethodPost, keysPath, "admin", createKeyBody('a', general, 2, h.users["admin"]), nil)
	// The version must be the next one.
	h.expect(t, http.StatusConflict, http.MethodPost, regenerate, "admin", createKeyBody('a', general, 1, h.users["admin"]), nil)

	h.drain()
	var created chatutil.CreateKeyVersionResult
	h.expect(t, http.StatusOK, http.MethodPost, regenerate, "admin", createKeyBody('a', general, 2, h.users["admin"]), &created)
	if created.Version.Version != 2 || created.Grant.UserID != h.users["admin"] {
		t.Fatalf("regenerated = %+v", created)
	}
	if created.Event.Kind != chatutil.EventKeyCreated || created.Event.ActorID != h.users["admin"] ||
		created.Event.Payload != `{"version":2,"regenerated":true}` {
		t.Errorf("event = %+v, want admin's key_created with regenerated", created.Event)
	}
	needed := false
	for _, evt := range h.drain() {
		needed = needed || evt.Kind == eventbus.EventChatKeyNeeded
	}
	if !needed {
		t.Error("regenerating didn't send chat_key_needed")
	}

	// Holding the current version now, the admin can't regenerate again.
	h.expect(t, http.StatusConflict, http.MethodPost, regenerate, "admin", createKeyBody('a', general, 3, h.users["admin"]), nil)

	// The admin fills version 2 for everyone with keys, the away holder too.
	var pending chatutil.ListPendingGrantsResult
	h.expect(t, http.StatusOK, http.MethodGet, keysPath+"/pending", "admin", "", &pending)
	want := map[int64]bool{h.users["bob"]: true, h.users["carol"]: true, h.users["dave"]: true}
	grants := ""
	for _, p := range pending.Pending {
		if p.Version != 2 || !want[p.UserID] {
			t.Fatalf("admin's pending = %+v", pending.Pending)
		}
		delete(want, p.UserID)
		if grants != "" {
			grants += ","
		}
		grants += grantBody('a', general, 2, p.UserID, 'x')
	}
	if len(want) != 0 {
		t.Fatalf("admin's pending = %+v, missing %v", pending.Pending, want)
	}
	h.expect(t, http.StatusOK, http.MethodPost, keysPath+"/grants", "admin", `{"grants":[`+grants+`]}`, nil)
	for _, as := range []string{"bob", "carol", "dave"} {
		var keys chatutil.GetChannelKeysResult
		h.expect(t, http.StatusOK, http.MethodGet, keysPath, as, "", &keys)
		if keys.CurrentVersion != 2 || !hasGrant(keys.Grants, 2, h.users["admin"]) {
			t.Errorf("%s's keys = %+v, want version 2 from admin", as, keys)
		}
	}
	// Version 1 is still bob's alone to share.
	h.expect(t, http.StatusOK, http.MethodGet, keysPath+"/pending", "bob", "", &pending)
	if len(pending.Pending) != 3 {
		t.Errorf("bob's pending = %+v, want version 1 for admin, carol and dave", pending.Pending)
	}

	// Every member sees who regenerated, and the admin can sign it.
	var events chatutil.ListEventsResult
	h.expect(t, http.StatusOK, http.MethodGet, keysPath[:len(keysPath)-len("/keys")]+"/events", "carol", "", &events)
	last := events.Events[len(events.Events)-1]
	if last.ID != created.Event.ID || last.ActorID != h.users["admin"] {
		t.Errorf("carol's events = %+v", events.Events)
	}
	signPath := keysPath[:len(keysPath)-len("/keys")] + "/events/" + strconv.FormatInt(created.Event.ID, 10) + "/signature"
	h.expect(t, http.StatusOK, http.MethodPut, signPath, "admin", `{"signature":"`+b64('s', chatutil.SignatureBytes)+`"}`, nil)
}

// TestChatChannelKeys_RegenerateNeedsReadMessages keeps the route from
// letting an admin into a channel: one who doesn't read it gets 404, as on
// every other key route.
func TestChatChannelKeys_RegenerateNeedsReadMessages(t *testing.T) {
	h := newHarness(t)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "admin", keysBody('a', false), nil)
	var private chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"secret"}`, &private)
	path := "/chat/channels/" + strconv.FormatInt(private.ID, 10) + "/keys/regenerate"
	h.expect(t, http.StatusNotFound, http.MethodPost, path, "admin", createKeyBody('a', private.ID, 1, h.users["admin"]), nil)
}

// TestChatChannelKeys_RegenerateRateLimited spends the key-creation bucket
// on POST /keys and finds regenerating shares it (#2485).
func TestChatChannelKeys_RegenerateRateLimited(t *testing.T) {
	h := newHarness(t)
	general, keysPath := stuckGeneral(t, h)
	h.deps.WithChatRateLimiter(ratelimitutil.NewWithRate(0, 2))
	create := createKeyBody('a', general, 2, h.users["admin"])
	h.expect(t, http.StatusConflict, http.MethodPost, keysPath, "admin", create, nil)
	h.expect(t, http.StatusConflict, http.MethodPost, keysPath, "admin", create, nil)
	h.expect(t, http.StatusTooManyRequests, http.MethodPost, keysPath+"/regenerate", "admin", create, nil)
}

// hasGrant is whether grants carry version from granter.
func hasGrant(grants []chatutil.KeyGrant, version, granter int64) bool {
	for _, g := range grants {
		if g.Version == version && g.GrantedBy == granter {
			return true
		}
	}
	return false
}

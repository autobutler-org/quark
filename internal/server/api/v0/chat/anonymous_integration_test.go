package v0_chat_test

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

// leakedIDs walks a JSON document, and any JSON string inside it that is
// itself an object (an event's payload), and returns every value of a field
// that names an account and is one of accounts.
func leakedIDs(t *testing.T, body string, accounts map[int64]string) []string {
	t.Helper()
	var doc any
	if err := json.Unmarshal([]byte(body), &doc); err != nil {
		t.Fatalf("decode %s: %v", body, err)
	}
	accountFields := map[string]bool{
		"userId": true, "authorId": true, "actorId": true, "createdBy": true, "grantedBy": true,
		"selfId": true, "pseudonymId": true,
	}
	var leaks []string
	var walk func(v any, inUsers bool)
	walk = func(v any, inUsers bool) {
		switch v := v.(type) {
		case map[string]any:
			for key, value := range v {
				if n, ok := value.(float64); ok && (accountFields[key] || (inUsers && key == "id")) {
					if name, found := accounts[int64(n)]; found {
						leaks = append(leaks, key+"="+name)
					}
				}
				if s, ok := value.(string); ok && strings.HasPrefix(s, "{") {
					var inner any
					if json.Unmarshal([]byte(s), &inner) == nil {
						walk(inner, false)
					}
				}
				walk(value, key == "users")
			}
		case []any:
			for _, each := range v {
				walk(each, inUsers)
			}
		}
	}
	walk(doc, false)
	for _, name := range accounts {
		if strings.Contains(body, `"`+name+`"`) {
			leaks = append(leaks, "username "+name)
		}
	}
	return leaks
}

// channelKeysBody is a PUT /keys/me body for an anonymous channel: a box key
// filled with fill and signer(fill)'s signing key.
func channelKeysBody(fill byte) string {
	return `{"boxPublicKey":"` + b64(fill, 32) + `","signPublicKey":"` +
		base64.StdEncoding.EncodeToString(signer(fill).Public().(ed25519.PublicKey)) + `"}`
}

// TestChatAnonymous_MembersSeeOnlyPseudonyms has bob run an anonymous channel
// (#2949) with carol and dave in it, and checks that carol, who holds no
// manage_members, never gets an account id or username in anything she reads
// or hears there: the channel list, members, messages, reactions, poll
// answers, typing, events, keys and pending grants. Bob and an admin see who
// is behind each pseudonym and may rename one; carol may not, and she leaves
// by her own pseudonym.
func TestChatAnonymous_MembersSeeOnlyPseudonyms(t *testing.T) {
	h := newHarness(t)
	for name, fill := range map[string]byte{"bob": 'b', "carol": 'c', "dave": 'd', "admin": 'a'} {
		h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", name, keysBody(fill, false), nil)
	}
	accounts := map[int64]string{}
	for name, id := range h.users {
		accounts[id] = name
	}

	var room chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"masks","anonymous":true}`, &room)
	if !room.Anonymous || room.SelfID >= 0 || room.CreatedBy != h.users["bob"] {
		t.Fatalf("created %+v, want anonymous with a negative selfId and bob as creator to bob", room)
	}
	path := "/chat/channels/" + strconv.FormatInt(room.ID, 10)
	// Each member's app publishes keys for this channel alone, which every
	// grant and event there is sealed to and signed with: bob's are 'B'.
	var self chatutil.PutChannelKeysResult
	h.expect(t, http.StatusOK, http.MethodPut, path+"/keys/me", "bob", channelKeysBody('B'), &self)
	if self.SelfID != room.SelfID {
		t.Errorf("bob's selfId from publishing = %d, want %d", self.SelfID, room.SelfID)
	}
	h.expect(t, http.StatusOK, http.MethodPut, path+"/keys/me", "bob", channelKeysBody('B'), nil)
	h.expect(t, http.StatusConflict, http.MethodPut, path+"/keys/me", "bob", channelKeysBody('X'), nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, path+"/keys/me", "dave", channelKeysBody('D'), nil)
	var adminSelf chatutil.PutChannelKeysResult
	h.expect(t, http.StatusOK, http.MethodPut, path+"/keys/me", "admin", channelKeysBody('A'), &adminSelf)
	if adminSelf.SelfID >= 0 {
		t.Errorf("an admin outside the channel publishes as %d, want a pseudonym", adminSelf.SelfID)
	}
	// The own grant of a new version is signed over the pseudonym with the
	// channel key; an account id or the account key is refused.
	h.expect(t, http.StatusBadRequest, http.MethodPost, path+"/keys", "bob", createKeyBody('B', room.ID, 1, h.users["bob"]), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, path+"/keys", "bob", createKeyBody('b', room.ID, 1, room.SelfID), nil)
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys", "bob", createKeyBody('B', room.ID, 1, room.SelfID), nil)
	for _, who := range []string{"carol", "dave"} {
		h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "bob", userBody(h.users[who], member...), nil)
	}
	// carol and dave have account keys, but are pending only once they have
	// published channel keys.
	var none chatutil.ListPendingGrantsResult
	h.expect(t, http.StatusOK, http.MethodGet, path+"/keys/pending", "bob", "", &none)
	if len(none.Pending) != 0 {
		t.Errorf("pending before carol and dave publish = %+v, want none", none.Pending)
	}
	h.expect(t, http.StatusOK, http.MethodPut, path+"/keys/me", "carol", channelKeysBody('C'), nil)
	h.expect(t, http.StatusOK, http.MethodPut, path+"/keys/me", "dave", channelKeysBody('D'), nil)

	// bob fills the grants by pseudonym; an account id is refused.
	var pending chatutil.ListPendingGrantsResult
	h.expect(t, http.StatusOK, http.MethodGet, path+"/keys/pending", "bob", "", &pending)
	if len(pending.Pending) != 2 {
		t.Fatalf("pending = %+v, want carol and dave", pending)
	}
	h.expect(t, http.StatusBadRequest, http.MethodPost, path+"/keys/grants", "bob",
		`{"grants":[`+grantBody('B', room.ID, 1, h.users["carol"], 'x')+`]}`, nil)
	grants := []string{}
	for _, p := range pending.Pending {
		if p.UserID >= 0 {
			t.Fatalf("pending names an account: %+v", p)
		}
		h.expect(t, http.StatusBadRequest, http.MethodPost, path+"/keys/grants", "bob",
			`{"grants":[`+grantBody('b', room.ID, 1, p.UserID, 'x')+`]}`, nil)
		grants = append(grants, grantBody('B', room.ID, 1, p.UserID, 'x'))
	}
	h.expect(t, http.StatusOK, http.MethodPost, path+"/keys/grants", "bob", `{"grants":[`+strings.Join(grants, ",")+`]}`, nil)

	// admin joins, so carol, who holds version 1, has a grant to fill.
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "bob", userBody(h.users["admin"], member...), nil)
	h.drain()

	// What carol hears while dave writes, reacts, polls and types.
	msg := postMsg(t, h, path+"/messages", "dave", 'm')
	addReact(t, h, msg.ID, "dave", 'r')
	var poll chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, path+"/messages", "dave",
		pollBody('p', `{"allowChange":false,"anonymous":false,"resultsAfterClose":false}`), &poll)
	h.expect(t, http.StatusOK, http.MethodPut, pollPath(poll.ID, "/answer"), "dave", answerBody('a'), nil)
	h.expect(t, http.StatusNoContent, http.MethodPost, path+"/typing", "dave", "", nil)
	for _, evt := range h.drain() {
		data, err := json.Marshal(evt.Data)
		if err != nil {
			t.Fatal(err)
		}
		if leaks := leakedIDs(t, string(data), accounts); len(leaks) > 0 {
			t.Errorf("%s event leaks %v: %s", evt.Kind, leaks, data)
		}
	}

	// What carol reads.
	var channels chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", "carol", "", &channels)
	var carolSelf int64
	for _, c := range channels.Channels {
		if c.ID == room.ID {
			carolSelf = c.SelfID
		}
	}
	if carolSelf >= 0 {
		t.Fatalf("carol's selfId = %d, want a pseudonym", carolSelf)
	}
	var keys chatutil.GetChannelKeysResult
	h.expect(t, http.StatusOK, http.MethodGet, path+"/keys", "carol", "", &keys)
	if len(keys.Grants) != 1 || keys.Grants[0].UserID != carolSelf || keys.Grants[0].GrantedBy != room.SelfID {
		t.Errorf("carol's grants = %+v, want hers from bob, by pseudonym", keys.Grants)
	}
	for _, route := range []string{"/chat/channels", path + "/members", path + "/messages", path + "/keys",
		path + "/keys/pending", path + "/events", pollPath(poll.ID, "/answers")} {
		code, body := h.do(t, http.MethodGet, route, "carol", "")
		if code != http.StatusOK {
			t.Fatalf("GET %s as carol = %d %s", route, code, body)
		}
		if leaks := leakedIDs(t, body, accounts); len(leaks) > 0 {
			t.Errorf("GET %s as carol leaks %v: %s", route, leaks, body)
		}
	}

	// bob and an admin see the accounts behind the pseudonyms.
	for _, as := range []string{"bob", "admin"} {
		var members chatutil.ListMembersResult
		h.expect(t, http.StatusOK, http.MethodGet, path+"/members", as, "", &members)
		for _, m := range members.Members {
			if m.UserID <= 0 || accounts[m.UserID] != m.Name || m.PseudonymID >= 0 || m.Alias == "" {
				t.Errorf("%s sees %+v, want the account beside its pseudonym", as, m)
			}
		}
	}

	// Aliases: bob by account id, admin by pseudonym, carol her own by
	// pseudonym but nobody else's; a taken alias is a conflict, and a channel
	// that isn't anonymous has none.
	h.drain()
	var renamed chatutil.ListMembersResult
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members/alias", "bob", `{"userId":`+strconv.FormatInt(h.users["dave"], 10)+`,"alias":"Fox"}`, &renamed)
	if h.heard(room.ID) == 0 {
		t.Error("setting an alias published no chat_channel_changed")
	}
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members/alias", "admin", `{"userId":`+strconv.FormatInt(carolSelf, 10)+`,"alias":"Owl"}`, nil)
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members/alias", "carol", `{"userId":`+strconv.FormatInt(carolSelf, 10)+`,"alias":"Wren"}`, nil)
	h.expect(t, http.StatusForbidden, http.MethodPut, path+"/members/alias", "carol", `{"userId":`+strconv.FormatInt(room.SelfID, 10)+`,"alias":"Mask"}`, nil)
	h.expect(t, http.StatusConflict, http.MethodPut, path+"/members/alias", "bob", `{"userId":`+strconv.FormatInt(carolSelf, 10)+`,"alias":"Fox"}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, path+"/members/alias", "bob", `{"userId":`+strconv.FormatInt(carolSelf, 10)+`,"alias":" "}`, nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, path+"/members/alias", "bob", `{"userId":-1,"alias":"Ghost"}`, nil)
	var plain chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"plain"}`, &plain)
	h.expect(t, http.StatusBadRequest, http.MethodPut, "/chat/channels/"+strconv.FormatInt(plain.ID, 10)+"/members/alias", "bob",
		`{"userId":`+strconv.FormatInt(h.users["bob"], 10)+`,"alias":"Fox"}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, "/chat/channels/"+strconv.FormatInt(plain.ID, 10)+"/keys/me", "bob", channelKeysBody('B'), nil)

	var members chatutil.ListMembersResult
	h.expect(t, http.StatusOK, http.MethodGet, path+"/members", "carol", "", &members)
	aliases := []string{}
	for _, m := range members.Members {
		aliases = append(aliases, m.Name)
	}
	if !strings.Contains(strings.Join(aliases, ","), "Fox") || !strings.Contains(strings.Join(aliases, ","), "Wren") {
		t.Errorf("carol sees %v, want Fox and Wren among them", aliases)
	}

	// carol leaves by her pseudonym.
	h.expect(t, http.StatusOK, http.MethodDelete, path+"/members", "carol", `{"userId":`+strconv.FormatInt(carolSelf, 10)+`}`, nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, path+"/members", "carol", "", nil)
}

// TestChatAnonymous_GroupsAliasesAndSteppingDown checks the edges of an
// anonymous channel (#2949) over HTTP: a member without manage_members gets
// every account a group reaches as an account row and no group's users, an
// alias is unique whatever its case and is never a username, and a manager
// who leaves reads the answer as the stranger they now are.
func TestChatAnonymous_GroupsAliasesAndSteppingDown(t *testing.T) {
	h := newHarness(t)
	var room chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"masks","anonymous":true}`, &room)
	path := "/chat/channels/" + strconv.FormatInt(room.ID, 10)
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "bob", `{"groupId":`+strconv.FormatInt(h.everyone, 10)+`,"permissions":["read_messages"]}`, nil)

	code, body := h.do(t, http.MethodGet, path+"/members", "carol", "")
	if code != http.StatusOK || strings.Contains(body, `"users"`) {
		t.Errorf("carol's members = %d %s, want no group's users", code, body)
	}
	var members chatutil.ListMembersResult
	if err := json.Unmarshal([]byte(body), &members); err != nil {
		t.Fatal(err)
	}
	accounts := 0
	for _, m := range members.Members {
		if m.GroupID == 0 {
			accounts++
		}
	}
	if accounts != len(h.users) {
		t.Errorf("carol sees %d accounts, want all %d everyone reaches", accounts, len(h.users))
	}

	rename := func(who, alias string) string {
		return `{"userId":` + strconv.FormatInt(h.users[who], 10) + `,"alias":"` + alias + `"}`
	}
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members/alias", "bob", rename("dave", "Fox"), nil)
	h.expect(t, http.StatusConflict, http.MethodPut, path+"/members/alias", "bob", rename("carol", "FOX"), nil)
	h.expect(t, http.StatusConflict, http.MethodPut, path+"/members/alias", "bob", rename("carol", "Dave"), nil)

	h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "bob", userBody(h.users["carol"], owner...), nil)
	var left chatutil.ListMembersResult
	h.expect(t, http.StatusOK, http.MethodDelete, path+"/members", "carol", userBody(h.users["carol"]), &left)
	for _, m := range left.Members {
		if m.UserID > 0 || m.Users != nil {
			t.Errorf("carol, gone, reads %+v", m)
		}
	}
}

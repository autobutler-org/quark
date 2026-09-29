package v0_chat_test

import (
	"encoding/base64"
	"net/http"
	"strconv"
	"strings"
	"testing"
)

// keysBody is a well-formed PUT /chat/keys/me body whose bytes are all fill.
func keysBody(fill byte, withPhrase bool) string {
	b := func(n int) string {
		return base64.StdEncoding.EncodeToString([]byte(strings.Repeat(string(rune(fill)), n)))
	}
	body := `{"boxPublicKey":"` + b(32) + `","signPublicKey":"` + b(32) +
		`","wrappedByPassword":"` + b(104) + `","saltPw":"` + b(16) + `"`
	if withPhrase {
		body += `,"wrappedByPhrase":"` + b(104) + `","saltRp":"` + b(16) + `"`
	}
	return body + `,"kdfParams":{"alg":"argon2id13","opsLimit":3,"memLimit":67108864}}`
}

func TestChatKeys_MineAndOthers(t *testing.T) {
	h := newHarness(t)

	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/keys/me", "bob", "", nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, "/chat/keys/me", "bob", `{"boxPublicKey":"AAAA"}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, "/chat/keys/me", "bob",
		`{"pad":"`+strings.Repeat("x", 9<<10)+`"}`, nil)

	var stored map[string]any
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "bob", keysBody('b', true), &stored)
	var mine map[string]any
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/keys/me", "bob", "", &mine)
	for _, field := range []string{"boxPublicKey", "signPublicKey", "wrappedByPassword", "saltPw", "wrappedByPhrase", "saltRp", "kdfParams"} {
		if mine[field] == nil {
			t.Errorf("GET /chat/keys/me lacks %s: %v", field, mine)
		}
	}
	if params, _ := mine["kdfParams"].(map[string]any); params["alg"] != "argon2id13" {
		t.Errorf("kdfParams = %v, want the object that was stored", mine["kdfParams"])
	}

	// Another account sees the public half and nothing wrapped.
	var theirs map[string]any
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/keys/"+strconv.FormatInt(h.users["bob"], 10), "carol", "", &theirs)
	if len(theirs) != 3 || theirs["boxPublicKey"] != mine["boxPublicKey"] || theirs["signPublicKey"] != mine["signPublicKey"] {
		t.Errorf("carol's view of bob's keys = %v, want only userId and the two public keys", theirs)
	}
	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/keys/"+strconv.FormatInt(h.users["carol"], 10), "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/keys/nope", "bob", "", nil)

	// A caller with no account can't have keys.
	h.expect(t, http.StatusUnauthorized, http.MethodGet, "/chat/keys/me", "stranger", "", nil)
}

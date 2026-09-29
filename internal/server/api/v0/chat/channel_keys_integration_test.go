package v0_chat_test

import (
	"crypto/ed25519"
	"encoding/base64"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

func b64(fill byte, n int) string {
	return base64.StdEncoding.EncodeToString([]byte(strings.Repeat(string(rune(fill)), n)))
}

// signer is the Ed25519 key keysBody(fill) publishes.
func signer(fill byte) ed25519.PrivateKey {
	return ed25519.NewKeyFromSeed([]byte(strings.Repeat(string(rune(fill)), ed25519.SeedSize)))
}

// grantSignature is the account with keysBody(by)'s signature over a grant
// of a sealed key of fill bytes, the way the app signs one.
func grantSignature(by byte, channelID, version, userID int64, fill byte) string {
	sealed := []byte(strings.Repeat(string(rune(fill)), chatutil.SealedKeyBytes))
	return base64.StdEncoding.EncodeToString(ed25519.Sign(signer(by), chatutil.GrantMessage(channelID, version, userID, sealed)))
}

// grantBody is one grant in an upload, signed by the account with
// keysBody(by).
func grantBody(by byte, channelID, version, userID int64, fill byte) string {
	return `{"version":` + strconv.FormatInt(version, 10) + `,"userId":` + strconv.FormatInt(userID, 10) +
		`,"sealedKey":"` + b64(fill, chatutil.SealedKeyBytes) + `","signature":"` + grantSignature(by, channelID, version, userID, fill) + `"}`
}

// createKeyBody is a POST /keys body for version, with the caller's own grant
// signed by keysBody(by).
func createKeyBody(by byte, channelID, version, userID int64) string {
	return `{"version":` + strconv.FormatInt(version, 10) + `,"sealedKey":"` + b64(by, chatutil.SealedKeyBytes) +
		`","signature":"` + grantSignature(by, channelID, version, userID, by) + `"}`
}

// TestChatChannelKeys_Distribution walks general's key from bob starting it
// to carol receiving it, and keeps a non-member out of a private channel.
func TestChatChannelKeys_Distribution(t *testing.T) {
	h := newHarness(t)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "bob", keysBody('b', false), nil)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "carol", keysBody('c', false), nil)

	var channels chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", "bob", "", &channels)
	general := channels.Channels[0].ID
	keysPath := "/chat/channels/" + strconv.FormatInt(general, 10) + "/keys"

	var keys chatutil.GetChannelKeysResult
	h.expect(t, http.StatusOK, http.MethodGet, keysPath, "bob", "", &keys)
	if keys.CurrentVersion != 0 {
		t.Fatalf("general starts with keys: %+v", keys)
	}
	// A signature that isn't the caller's is refused before anything else.
	h.expect(t, http.StatusBadRequest, http.MethodPost, keysPath, "bob", createKeyBody('c', general, 1, h.users["bob"]), nil)
	var created chatutil.CreateKeyVersionResult
	h.expect(t, http.StatusOK, http.MethodPost, keysPath, "bob", createKeyBody('b', general, 1, h.users["bob"]), &created)
	h.expect(t, http.StatusConflict, http.MethodPost, keysPath, "carol", createKeyBody('c', general, 1, h.users["carol"]), nil)

	var pending chatutil.ListPendingGrantsResult
	h.expect(t, http.StatusOK, http.MethodGet, keysPath+"/pending", "bob", "", &pending)
	if len(pending.Pending) != 1 || pending.Pending[0].UserID != h.users["carol"] {
		t.Fatalf("pending = %+v, want carol", pending)
	}
	h.expect(t, http.StatusForbidden, http.MethodPost, keysPath+"/grants", "carol",
		`{"grants":[`+grantBody('c', general, 1, h.users["bob"], 'c')+`]}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, keysPath+"/grants", "bob",
		`{"grants":[`+grantBody('b', general+1, 1, h.users["carol"], 'x')+`]}`, nil)
	h.expect(t, http.StatusOK, http.MethodPost, keysPath+"/grants", "bob",
		`{"grants":[`+grantBody('b', general, 1, h.users["carol"], 'x')+`]}`, nil)
	h.expect(t, http.StatusOK, http.MethodGet, keysPath, "carol", "", &keys)
	if len(keys.Grants) != 1 || keys.Grants[0].GrantedBy != h.users["bob"] {
		t.Errorf("carol's grants = %+v", keys.Grants)
	}

	// carol rejects her grant: she is pending again, and only once.
	h.expect(t, http.StatusOK, http.MethodDelete, keysPath+"/grants/1", "carol", "", nil)
	h.expect(t, http.StatusOK, http.MethodGet, keysPath, "carol", "", &keys)
	if len(keys.Grants) != 0 {
		t.Errorf("carol's grants after rejecting = %+v", keys.Grants)
	}
	h.expect(t, http.StatusNotFound, http.MethodDelete, keysPath+"/grants/1", "carol", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, keysPath+"/grants/x", "carol", "", nil)
	h.expect(t, http.StatusOK, http.MethodGet, keysPath+"/pending", "bob", "", &pending)
	if len(pending.Pending) != 1 || pending.Pending[0].UserID != h.users["carol"] {
		t.Errorf("pending after carol rejected = %+v, want carol", pending)
	}

	eventPath := "/chat/channels/" + strconv.FormatInt(channels.Channels[0].ID, 10) + "/events"
	signature := `{"signature":"` + b64('s', chatutil.SignatureBytes) + `"}`
	signPath := eventPath + "/" + strconv.FormatInt(created.Event.ID, 10) + "/signature"
	h.expect(t, http.StatusNotFound, http.MethodPut, signPath, "carol", signature, nil)
	h.heard(channels.Channels[0].ID)
	h.expect(t, http.StatusOK, http.MethodPut, signPath, "bob", signature, nil)
	if h.heard(channels.Channels[0].ID) == 0 {
		t.Error("signing an event wasn't announced to the members")
	}
	h.expect(t, http.StatusConflict, http.MethodPut, signPath, "bob", signature, nil)
	var events chatutil.ListEventsResult
	h.expect(t, http.StatusOK, http.MethodGet, eventPath, "carol", "", &events)
	if len(events.Events) != 1 || events.Events[0].Kind != chatutil.EventKeyCreated || events.Events[0].Signature == nil {
		t.Errorf("events = %+v", events.Events)
	}

	var private chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"secret"}`, &private)
	privatePath := "/chat/channels/" + strconv.FormatInt(private.ID, 10)
	for _, as := range []string{"carol", "admin"} {
		h.expect(t, http.StatusNotFound, http.MethodGet, privatePath+"/keys", as, "", nil)
		h.expect(t, http.StatusNotFound, http.MethodGet, privatePath+"/keys/pending", as, "", nil)
		h.expect(t, http.StatusNotFound, http.MethodGet, privatePath+"/events", as, "", nil)
		h.expect(t, http.StatusNotFound, http.MethodPost, privatePath+"/keys/grants", as,
			`{"grants":[`+grantBody('c', private.ID, 1, h.users["bob"], 'c')+`]}`, nil)
	}
}

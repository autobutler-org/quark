package v0_chat_test

import (
	"net/http"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
)

// The QA findings #2516 maps to this package that had no test of their own.
// The rest are pinned where their fixes landed: TestChatWrites_RateLimited
// (#2485), TestChatChannelKeys_Distribution (#2486),
// TestChatMessages_ReplayConflicts (#2487) and TestChat_AdminListsEveryChannel
// (#2488).

// TestChatWrites_BurstIsLimitedNotFailed is the burst half of #2485: more
// posts than bob's budget arrive at once, exactly the budget lands, and every
// other one is a 429, never a 5xx.
func TestChatWrites_BurstIsLimitedNotFailed(t *testing.T) {
	h := newHarness(t)
	_, path := roomWithKey(t, h)
	const budget = 4
	h.deps.WithChatRateLimiter(ratelimitutil.NewWithRate(0, budget))

	var wg sync.WaitGroup
	codes := make([]int, 4*budget)
	for i := range codes {
		wg.Go(func() {
			codes[i], _ = h.do(t, http.MethodPost, path+"/messages", "bob", messageBody(byte('a'+i), 64, 1))
		})
	}
	wg.Wait()
	created := 0
	for _, code := range codes {
		switch code {
		case http.StatusCreated:
			created++
		case http.StatusTooManyRequests:
		default:
			t.Errorf("burst post = %d, want 201 or 429", code)
		}
	}
	if created != budget {
		t.Errorf("a burst of %d posts created %d messages, want %d (%v)", len(codes), created, budget, codes)
	}
}

// TestChatGrants_GarbageSignatureLeavesNothingBehind is #2486 at the size-only
// check it reported: a signature of the right length that verifies against
// nothing is a 400 naming the signature, and it stores no key version, stores
// no grant and tells nobody.
func TestChatGrants_GarbageSignatureLeavesNothingBehind(t *testing.T) {
	h := newHarness(t)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "bob", keysBody('b', false), nil)
	h.expect(t, http.StatusOK, http.MethodPut, "/chat/keys/me", "carol", keysBody('c', false), nil)
	var channels chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", "bob", "", &channels)
	general := channels.Channels[0].ID
	keysPath := "/chat/channels/" + strconv.FormatInt(general, 10) + "/keys"
	garbage := `"sealedKey":"` + b64('x', chatutil.SealedKeyBytes) + `","signature":"` + b64('s', chatutil.SignatureBytes) + `"`
	refused := func(path, body string) {
		t.Helper()
		h.drain()
		code, got := h.do(t, http.MethodPost, path, "bob", body)
		if code != http.StatusBadRequest || !strings.Contains(got, chatutil.ErrGrantSignature.Error()) {
			t.Errorf("POST %s with a garbage signature = %d %s, want 400 %q", path, code, got, chatutil.ErrGrantSignature)
		}
		if events := h.drain(); len(events) != 0 {
			t.Errorf("POST %s with a garbage signature published %+v", path, events)
		}
	}

	refused(keysPath, `{"version":1,`+garbage+`}`)
	var keys chatutil.GetChannelKeysResult
	h.expect(t, http.StatusOK, http.MethodGet, keysPath, "bob", "", &keys)
	if keys.CurrentVersion != 0 {
		t.Fatalf("a garbage signature started key version %d", keys.CurrentVersion)
	}

	h.expect(t, http.StatusOK, http.MethodPost, keysPath, "bob", createKeyBody('b', general, 1, h.users["bob"]), nil)
	refused(keysPath+"/grants", `{"grants":[{"version":1,"userId":`+strconv.FormatInt(h.users["carol"], 10)+`,`+garbage+`}]}`)
	h.expect(t, http.StatusOK, http.MethodGet, keysPath, "carol", "", &keys)
	if len(keys.Grants) != 0 {
		t.Errorf("a garbage signature stored a grant: %+v", keys.Grants)
	}
}

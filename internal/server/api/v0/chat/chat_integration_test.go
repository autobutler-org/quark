package v0_chat_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_chat "github.com/autobutler-org/quark/internal/server/api/v0/chat"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// harness is the chat router over a migrated database. Each request acts as
// the account its ?as= names, as an admin when that account is admin.
type harness struct {
	srv      *httptest.Server
	users    map[string]int64
	everyone int64
	events   <-chan eventbus.Event
}

func newHarness(t *testing.T) harness {
	t.Helper()
	database := dbtest.NewDB(t)
	users := map[string]int64{}
	for _, name := range []string{"admin", "bob", "carol"} {
		user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		users[name] = user.ID
	}
	var everyone int64
	if err := database.Db.QueryRow(`SELECT id FROM groups WHERE name = 'everyone'`).Scan(&everyone); err != nil {
		t.Fatal(err)
	}
	bus := eventbus.New()
	events, unsub := bus.Subscribe("chat-integration-test")
	t.Cleanup(unsub)

	deps := deputil.NewDependencies().WithEventBus(bus).WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		as := c.Query("as")
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: users[as], IsAdmin: as == "admin"})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_chat.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)
	return harness{srv: srv, users: users, everyone: everyone, events: events}
}

func (h harness) do(t *testing.T, method, path, as, body string) (int, string) {
	t.Helper()
	sep := "?"
	if strings.Contains(path, "?") {
		sep = "&"
	}
	req, err := http.NewRequest(method, h.srv.URL+"/api/v0"+path+sep+"as="+as, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out bytes.Buffer
	if _, err := out.ReadFrom(resp.Body); err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, out.String()
}

// expect runs a request and fails unless it answers want, decoding the body
// into into when it is not nil.
func (h harness) expect(t *testing.T, want int, method, path, as, body string, into any) {
	t.Helper()
	code, got := h.do(t, method, path, as, body)
	if code != want {
		t.Fatalf("%s %s as %s = %d %s, want %d", method, path, as, code, got, want)
	}
	if into != nil {
		if err := json.Unmarshal([]byte(got), into); err != nil {
			t.Fatalf("decode %s: %v", got, err)
		}
	}
}

func (h harness) channelNames(t *testing.T, as string) []string {
	t.Helper()
	var result chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", as, "", &result)
	names := make([]string, 0, len(result.Channels))
	for _, channel := range result.Channels {
		names = append(names, channel.Name)
	}
	return names
}

// heard drains the bus and reports how many chat_channel_changed events were
// published for a channel.
func (h harness) heard(channelID int64) int {
	n := 0
	for {
		select {
		case evt := <-h.events:
			if changed, ok := evt.Data.(eventbus.ChatChannelChanged); ok && evt.Kind == eventbus.EventChatChannelChanged && changed.ChannelID == channelID {
				n++
			}
		default:
			return n
		}
	}
}

func userBody(id int64, level string) string {
	return `{"userId":` + strconv.FormatInt(id, 10) + `,"level":"` + level + `"}`
}

// TestChat_ChannelLifecycle has bob create a channel, share it with carol and
// take it back, while carol gets 404 whenever she isn't a member and 403 while
// she is one without owning it.
func TestChat_ChannelLifecycle(t *testing.T) {
	h := newHarness(t)
	if got := h.channelNames(t, "carol"); len(got) != 1 || got[0] != "general" {
		t.Fatalf("carol's channels = %v, want [general]", got)
	}

	var channel chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"plans","topic":"weekend"}`, &channel)
	if channel.Name != "plans" || channel.Topic != "weekend" || channel.Level != "owner" || !channel.IsPrivate || channel.CreatedBy != h.users["bob"] {
		t.Errorf("created %+v", channel)
	}
	if h.heard(channel.ID) != 1 {
		t.Error("create published no chat_channel_changed")
	}
	h.expect(t, http.StatusConflict, http.MethodPost, "/chat/channels", "carol", `{"name":"PLANS"}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodPost, "/chat/channels", "carol", `{"name":" "}`, nil)

	path := "/chat/channels/" + strconv.FormatInt(channel.ID, 10)
	for _, req := range []struct{ method, path, body string }{
		{http.MethodGet, path + "/members", ""},
		{http.MethodPatch, path, `{"name":"mine"}`},
		{http.MethodDelete, path, ""},
		{http.MethodPut, path + "/members", userBody(h.users["carol"], "owner")},
		{http.MethodDelete, path + "/members", userBody(h.users["bob"], "")},
		{http.MethodGet, "/chat/channels/9999/members", ""},
		{http.MethodGet, "/chat/channels/..%2F1/members", ""},
	} {
		code, body := h.do(t, req.method, req.path, "carol", req.body)
		if code != http.StatusNotFound || strings.Contains(body, "plans") {
			t.Errorf("%s %s as a non-member = %d %s, want 404 without the name", req.method, req.path, code, body)
		}
	}

	var members chatutil.ListMembersResult
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "bob", userBody(h.users["carol"], "read"), &members)
	if len(members.Members) != 2 {
		t.Errorf("members after adding carol = %+v", members.Members)
	}
	if h.heard(channel.ID) != 1 {
		t.Error("adding carol published no chat_channel_changed")
	}
	if got := h.channelNames(t, "carol"); len(got) != 2 || got[1] != "plans" {
		t.Errorf("carol's channels after the add = %v", got)
	}
	h.expect(t, http.StatusOK, http.MethodGet, path+"/members", "carol", "", nil)
	h.expect(t, http.StatusForbidden, http.MethodPatch, path, "carol", `{"topic":"x"}`, nil)
	h.expect(t, http.StatusForbidden, http.MethodDelete, path+"/members", "carol", userBody(h.users["bob"], ""), nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, path+"/members", "bob", userBody(h.users["carol"], "admin"), nil)
	h.expect(t, http.StatusNotFound, http.MethodPut, path+"/members", "bob", userBody(9999, "read"), nil)

	var updated chatutil.Channel
	h.expect(t, http.StatusOK, http.MethodPatch, path, "bob", `{"topic":"sunday"}`, &updated)
	if updated.Name != "plans" || updated.Topic != "sunday" {
		t.Errorf("updated %+v", updated)
	}
	h.expect(t, http.StatusOK, http.MethodDelete, path+"/members", "carol", userBody(h.users["carol"], ""), nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, path+"/members", "bob", userBody(h.users["carol"], ""), nil)
	h.expect(t, http.StatusNoContent, http.MethodDelete, path, "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, path+"/members", "bob", "", nil)
}

// TestChat_GeneralIsProtected refuses to delete general or take everyone out
// of it, even for an admin.
func TestChat_GeneralIsProtected(t *testing.T) {
	h := newHarness(t)
	var result chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", "admin", "", &result)
	general := result.Channels[0]
	if !general.IsDefault || general.Level != "write" {
		t.Fatalf("general = %+v", general)
	}
	path := "/chat/channels/" + strconv.FormatInt(general.ID, 10)
	h.expect(t, http.StatusBadRequest, http.MethodDelete, path, "admin", "", nil)
	h.expect(t, http.StatusBadRequest, http.MethodDelete, path+"/members", "admin", `{"groupId":`+strconv.FormatInt(h.everyone, 10)+`}`, nil)
	h.expect(t, http.StatusBadRequest, http.MethodDelete, path+"/members", "admin", `{}`, nil)

	var members chatutil.ListMembersResult
	h.expect(t, http.StatusOK, http.MethodGet, path+"/members", "carol", "", &members)
	if len(members.Members) != 1 || !members.Members[0].Builtin || len(members.Members[0].Users) != 3 {
		t.Errorf("general's members = %+v, want everyone with all three accounts", members.Members)
	}
}

// TestChat_AdminManagesWithoutSeeing lets an admin rename, re-member and delete
// a channel they are not in, which never shows up in their own list.
func TestChat_AdminManagesWithoutSeeing(t *testing.T) {
	h := newHarness(t)
	var channel chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"private"}`, &channel)
	path := "/chat/channels/" + strconv.FormatInt(channel.ID, 10)

	var updated chatutil.Channel
	h.expect(t, http.StatusOK, http.MethodPatch, path, "admin", `{"name":"renamed"}`, &updated)
	if updated.Name != "renamed" || updated.Level != "" {
		t.Errorf("admin rename = %+v", updated)
	}
	h.expect(t, http.StatusOK, http.MethodGet, path+"/members", "admin", "", nil)
	h.expect(t, http.StatusOK, http.MethodPut, path+"/members", "admin", userBody(h.users["carol"], "write"), nil)
	if got := h.channelNames(t, "admin"); len(got) != 1 || got[0] != "general" {
		t.Errorf("admin's channels = %v, want [general]", got)
	}
	h.expect(t, http.StatusNoContent, http.MethodDelete, path, "admin", "", nil)
	if got := h.channelNames(t, "carol"); len(got) != 1 {
		t.Errorf("carol's channels after the delete = %v", got)
	}
}

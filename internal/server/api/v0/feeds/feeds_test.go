package v0_feeds_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_feeds "github.com/autobutler-org/quark/internal/server/api/v0/feeds"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

type harness struct {
	srv    *httptest.Server
	users  map[string]int64
	events <-chan eventbus.Event
}

func newHarness(t *testing.T) harness {
	t.Helper()
	database := dbtest.NewDB(t)
	users := map[string]int64{}
	for _, name := range []string{"admin", "bob", "carol"} {
		hash, err := authutil.HashKey(dbtest.AuthKey(name + "-password"))
		if err != nil {
			t.Fatal(err)
		}
		user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
			Username: name, AuthKeyHash: hash, RecoveryPhraseHash: "r",
		})
		if err != nil {
			t.Fatal(err)
		}
		users[name] = user.ID
	}
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("feeds-integration-test")
	t.Cleanup(unsubscribe)

	deps := deputil.NewDependencies().WithEventBus(bus).WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		as := c.Query("as")
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: users[as], IsAdmin: as == "admin"})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_feeds.NewRouter())
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)
	return harness{srv: srv, users: users, events: events}
}

func (h harness) expect(t *testing.T, want int, method, path, as, body string, out any) string {
	t.Helper()
	req, err := http.NewRequest(method, h.srv.URL+"/api/v0"+path+"?as="+as, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	raw, _ := io.ReadAll(res.Body)
	if res.StatusCode != want {
		t.Fatalf("%s %s as %s = %d %s, want %d", method, path, as, res.StatusCode, raw, want)
	}
	if out != nil {
		if err := json.Unmarshal(raw, out); err != nil {
			t.Fatalf("%s %s: %v in %s", method, path, err, raw)
		}
	}
	return string(raw)
}

func (h harness) heard() []eventbus.FeedChanged {
	var out []eventbus.FeedChanged
	for {
		select {
		case evt := <-h.events:
			if data, ok := evt.Data.(eventbus.FeedChanged); ok && evt.Kind == eventbus.EventFeedChanged {
				out = append(out, data)
			}
		default:
			return out
		}
	}
}

func TestFeeds_SubscribeOrganizeUnsubscribe(t *testing.T) {
	h := newHarness(t)
	bob := h.users["bob"]
	const token = "opaque-token"
	body := `{"url":"https://203.0.113.5/feed?token=` + token + `","name":"Morning","folder":"News"}`

	h.expect(t, http.StatusUnauthorized, http.MethodPost, "/feeds", "stranger", body, nil)
	if heard := h.heard(); len(heard) != 0 {
		t.Fatalf("refused request published %v", heard)
	}

	var created feedutil.Feed
	raw := h.expect(t, http.StatusCreated, http.MethodPost, "/feeds", "bob", body, &created)
	if !strings.Contains(raw, token) || created.Name != "Morning" || created.Folder != "News" || created.URL != "https://203.0.113.5/feed?token="+token {
		t.Fatalf("created = %+v %s", created, raw)
	}
	if heard := h.heard(); len(heard) != 1 || heard[0] != (eventbus.FeedChanged{FeedID: created.ID, UserID: bob}) {
		t.Fatalf("events = %v", heard)
	}
	eventRaw, err := json.Marshal(eventbus.Event{Kind: eventbus.EventFeedChanged, Data: eventbus.FeedChanged{FeedID: created.ID, UserID: bob}})
	if err != nil || strings.Contains(string(eventRaw), token) || strings.Contains(string(eventRaw), "203.0.113.5") {
		t.Fatalf("event json = %s %v", eventRaw, err)
	}

	dup := h.expect(t, http.StatusConflict, http.MethodPost, "/feeds", "bob", body, nil)
	if strings.Contains(dup, token) || strings.Contains(dup, "203.0.113.5") {
		t.Fatalf("duplicate error repeats the address: %s", dup)
	}

	var carol feedutil.Feed
	h.expect(t, http.StatusCreated, http.MethodPost, "/feeds", "carol", `{"url":"https://203.0.113.6/other?token=carol-token","name":"Carol"}`, &carol)
	h.heard()

	var listed []feedutil.Feed
	h.expect(t, http.StatusOK, http.MethodGet, "/feeds", "bob", "", &listed)
	if len(listed) != 1 || listed[0].ID != created.ID || !strings.Contains(listed[0].URL, token) {
		t.Fatalf("bob list = %+v", listed)
	}
	h.expect(t, http.StatusOK, http.MethodGet, "/feeds", "carol", "", &listed)
	if len(listed) != 1 || strings.Contains(listed[0].URL, token) {
		t.Fatalf("carol list = %+v", listed)
	}

	id := strings.Trim(strings.ReplaceAll(jsonNumber(created.ID), " ", ""), " ")
	var got feedutil.Feed
	h.expect(t, http.StatusOK, http.MethodGet, "/feeds/"+id, "bob", "", &got)
	h.expect(t, http.StatusNotFound, http.MethodGet, "/feeds/"+id, "carol", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, "/feeds/"+id, "admin", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodPatch, "/feeds/"+id, "admin", `{"name":"nope"}`, nil)
	if heard := h.heard(); len(heard) != 0 {
		t.Fatalf("not found published %v", heard)
	}

	h.expect(t, http.StatusOK, http.MethodPatch, "/feeds/"+id, "bob", `{"name":"Dawn"}`, &got)
	if got.Name != "Dawn" || got.Folder != "News" {
		t.Fatalf("rename = %+v", got)
	}
	h.expect(t, http.StatusOK, http.MethodPatch, "/feeds/"+id, "bob", `{"folder":""}`, &got)
	if got.Folder != "" || got.Name != "Dawn" {
		t.Fatalf("clear folder = %+v", got)
	}
	h.expect(t, http.StatusBadRequest, http.MethodPatch, "/feeds/"+id, "bob", `{}`, nil)
	long := strings.Repeat("n", 201)
	h.expect(t, http.StatusBadRequest, http.MethodPatch, "/feeds/"+id, "bob", `{"name":"`+long+`"}`, nil)

	h.expect(t, http.StatusNoContent, http.MethodDelete, "/feeds/"+id, "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, "/feeds/"+id, "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodDelete, "/feeds/"+id, "carol", "", nil)
	heard := h.heard()
	if len(heard) < 3 {
		t.Fatalf("events after edits = %v", heard)
	}
	for _, evt := range heard {
		raw, err := json.Marshal(eventbus.Event{Kind: eventbus.EventFeedChanged, Data: evt})
		if err != nil || strings.Contains(string(raw), token) {
			t.Fatalf("event %s repeats the feed address", raw)
		}
	}
}

func TestFeeds_RejectsPrivateAddresses(t *testing.T) {
	h := newHarness(t)
	const token = "opaque-token"
	for _, raw := range []string{
		"http://127.0.0.1/feed?token=" + token,
		"http://[::1]/feed?token=" + token,
		"http://10.1.2.3/feed?token=" + token,
		"http://192.168.1.20/feed?token=" + token,
		"http://169.254.169.254/latest?token=" + token,
		"http://feed.example:80@127.0.0.1/feed?token=" + token,
		"ftp://203.0.113.5/feed?token=" + token,
		"http://0.0.0.0/feed?token=" + token,
	} {
		body := h.expect(t, http.StatusBadRequest, http.MethodPost, "/feeds", "bob", `{"url":"`+raw+`"}`, nil)
		if strings.Contains(body, token) || strings.Contains(body, "://") {
			t.Fatalf("error for %s repeats the address: %s", raw, body)
		}
	}
	broken := h.expect(t, http.StatusBadRequest, http.MethodPost, "/feeds", "bob", `{"url":"http://10.0.0.1/feed?token=`+token+`"`, nil)
	if strings.Contains(broken, token) {
		t.Fatalf("malformed body echoed the address: %s", broken)
	}
	discover := h.expect(t, http.StatusBadRequest, http.MethodPost, "/feeds", "bob", `{"url":"http://192.168.0.9/blog?token=`+token+`","discover":true}`, nil)
	if strings.Contains(discover, token) || strings.Contains(discover, "192.168.0.9") {
		t.Fatalf("discover error repeats the address: %s", discover)
	}
	if heard := h.heard(); len(heard) != 0 {
		t.Fatalf("rejected addresses published %v", heard)
	}
}

func jsonNumber(id int64) string {
	raw, _ := json.Marshal(id)
	return string(raw)
}

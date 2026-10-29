package feedutil

import (
	"context"
	"errors"
	"net"
	"net/url"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

func newAccount(t *testing.T, database *db.DatabaseSqlc, name string) int64 {
	t.Helper()
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
	return user.ID
}

func allowNames(names ...string) IPLookup {
	ok := map[string]bool{}
	for _, name := range names {
		ok[name] = true
	}
	return func(ctx context.Context, host string) ([]net.IP, error) {
		if ok[host] {
			return []net.IP{net.ParseIP("203.0.113.5")}, nil
		}
		return nil, errors.New("no such host " + host)
	}
}

type scriptedFetch struct {
	page pageBody
	err  error
	got  string
}

func (s *scriptedFetch) Fetch(ctx context.Context, page *url.URL) (pageBody, error) {
	s.got = page.String()
	return s.page, s.err
}

func TestAddDirectAndOrganize(t *testing.T) {
	database := dbtest.NewDB(t)
	bob := newAccount(t, database, "bob")
	carol := newAccount(t, database, "carol")
	ctx := context.Background()
	fetch := &scriptedFetch{err: errors.New("fetch should not be called")}
	raw := "HTTP://203.0.113.5:80/a/Feed?token=opaque-token#frag"

	added, err := Add(AddParams{
		Ctx: ctx, Queries: database.Queries, UserID: bob, URL: raw,
		Name: "Morning", Folder: "News", Fetch: fetch,
	})
	if err != nil {
		t.Fatal(err)
	}
	if fetch.got != "" {
		t.Fatal("a direct subscription fetched the feed")
	}
	if added.Feed.URL != "http://203.0.113.5/a/Feed?token=opaque-token" || added.Feed.Name != "Morning" || added.Feed.Folder != "News" || added.Feed.Title != "" || added.Feed.LastFetchedAt != nil || added.Feed.ConsecutiveFailures != 0 {
		t.Fatalf("stored = %+v", added.Feed)
	}
	if _, err := Add(AddParams{Ctx: ctx, Queries: database.Queries, UserID: bob, URL: added.Feed.URL}); !errors.Is(err, ErrAlreadySubscribed) || strings.Contains(err.Error(), "opaque-token") {
		t.Fatalf("duplicate = %v", err)
	}
	again, err := Add(AddParams{Ctx: ctx, Queries: database.Queries, UserID: carol, URL: added.Feed.URL, Name: "Carol"})
	if err != nil || again.Feed.ID == added.Feed.ID {
		t.Fatalf("second account = %+v %v", again.Feed, err)
	}

	renamed, err := Update(UpdateParams{Ctx: ctx, Queries: database.Queries, UserID: bob, ID: added.Feed.ID, Name: strPtr("Dawn")})
	if err != nil || renamed.Feed.Name != "Dawn" || renamed.Feed.Folder != "News" {
		t.Fatalf("rename = %+v %v", renamed.Feed, err)
	}
	moved, err := Update(UpdateParams{Ctx: ctx, Queries: database.Queries, UserID: bob, ID: added.Feed.ID, Folder: strPtr("Archive")})
	if err != nil || moved.Feed.Folder != "Archive" || moved.Feed.Name != "Dawn" {
		t.Fatalf("move = %+v %v", moved.Feed, err)
	}
	cleared, err := Update(UpdateParams{Ctx: ctx, Queries: database.Queries, UserID: bob, ID: added.Feed.ID, Folder: strPtr("  ")})
	if err != nil || cleared.Feed.Folder != "" {
		t.Fatalf("clear folder = %+v %v", cleared.Feed, err)
	}
	if _, err := Update(UpdateParams{Ctx: ctx, Queries: database.Queries, UserID: carol, ID: added.Feed.ID, Name: strPtr("stolen")}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("other account update = %v", err)
	}
	if got, err := Get(GetParams{Ctx: ctx, Queries: database.Queries, UserID: bob, ID: added.Feed.ID}); err != nil || got.Feed.Name != "Dawn" {
		t.Fatalf("get after refused update = %+v %v", got.Feed, err)
	}
	if _, err := Get(GetParams{Ctx: ctx, Queries: database.Queries, UserID: carol, ID: added.Feed.ID}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("other account get = %v", err)
	}

	listed, err := List(ListParams{Ctx: ctx, Queries: database.Queries, UserID: bob})
	if err != nil || len(listed.Feeds) != 1 || listed.Feeds[0].ID != added.Feed.ID {
		t.Fatalf("bob list = %+v %v", listed.Feeds, err)
	}
	carolList, err := List(ListParams{Ctx: ctx, Queries: database.Queries, UserID: carol})
	if err != nil || len(carolList.Feeds) != 1 || carolList.Feeds[0].Name != "Carol" {
		t.Fatalf("carol list = %+v %v", carolList.Feeds, err)
	}

	if _, err := Delete(DeleteParams{Ctx: ctx, Queries: database.Queries, UserID: carol, ID: added.Feed.ID}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("other account delete = %v", err)
	}
	if _, err := Delete(DeleteParams{Ctx: ctx, Queries: database.Queries, UserID: bob, ID: added.Feed.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := Get(GetParams{Ctx: ctx, Queries: database.Queries, UserID: bob, ID: added.Feed.ID}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("deleted get = %v", err)
	}

	bus := eventbus.New()
	PublishChanged(PublishChangedParams{EventBus: bus, UserID: bob, FeedID: added.Feed.ID})
	events, unsubscribe := bus.Subscribe("feed-test")
	defer unsubscribe()
	PublishChanged(PublishChangedParams{EventBus: bus, UserID: bob, FeedID: 9})
	select {
	case evt := <-events:
		data, ok := evt.Data.(eventbus.FeedChanged)
		if evt.Kind != eventbus.EventFeedChanged || !ok || data.FeedID != 9 || data.UserID != bob {
			t.Fatalf("event = %+v", evt)
		}
	default:
		t.Fatal("no event")
	}
}

func TestAddDiscover(t *testing.T) {
	database := dbtest.NewDB(t)
	bob := newAccount(t, database, "bob")
	ctx := context.Background()
	lookup := allowNames("blog.example", "other.example")
	page, err := url.Parse("https://blog.example/posts/?token=site-secret")
	if err != nil {
		t.Fatal(err)
	}
	one := &scriptedFetch{page: pageBody{
		URL:         page,
		ContentType: "text/html",
		Body: []byte(`
			<link rel="alternate" type="application/rss+xml" title="Blog" href="/feed.xml">
			<link rel="alternate" type="application/atom+xml" href="http://10.1.2.3/private.xml">
			<link rel="icon" href="/favicon.ico">
			<link rel="icon" href="http://192.168.0.1/secret.ico">
		`),
	}}
	added, err := Add(AddParams{
		Ctx: ctx, Queries: database.Queries, UserID: bob,
		URL:  "https://user:site-secret@blog.example/posts/?token=site-secret",
		Name: "Mine", Folder: "News", Discover: true, Lookup: lookup, Fetch: one,
	})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(one.got, "site-secret") == false {
		t.Fatalf("fetch url dropped the caller's address: %s", one.got)
	}
	if added.Feed.URL != "https://blog.example/feed.xml" || strings.Contains(added.Feed.URL, "site-secret") {
		t.Fatalf("feed url = %s", added.Feed.URL)
	}
	if added.Feed.Title != "Blog" || added.Feed.Name != "Mine" || added.Feed.Folder != "News" {
		t.Fatalf("labels = %+v", added.Feed)
	}
	if added.Feed.Icon != "https://blog.example/favicon.ico" {
		t.Fatalf("icon = %s", added.Feed.Icon)
	}
	if !strings.Contains(added.Feed.SiteLink, "blog.example") || strings.Contains(added.Feed.SiteLink, "10.1.2.3") {
		t.Fatalf("site = %s", added.Feed.SiteLink)
	}

	several := &scriptedFetch{page: pageBody{
		URL:         page,
		ContentType: "text/html",
		Body: []byte(`
			<link rel="alternate" type="application/rss+xml" title="One" href="/one.xml">
			<link rel="alternate" type="application/atom+xml" title="Two" href="https://other.example/two.xml">
			<link rel="alternate" type="application/rss+xml" href="http://192.168.1.9/nope.xml?token=hidden">
		`),
	}}
	choice, err := Add(AddParams{
		Ctx: ctx, Queries: database.Queries, UserID: bob,
		URL:      "https://blog.example/posts/?token=site-secret",
		Discover: true, Lookup: lookup, Fetch: several,
	})
	if !errors.Is(err, ErrSeveralFeeds) || strings.Contains(err.Error(), "site-secret") || strings.Contains(err.Error(), "hidden") {
		t.Fatalf("several = %v %+v", err, choice.Candidates)
	}
	if len(choice.Candidates) != 2 || choice.Feed.ID != 0 {
		t.Fatalf("candidates = %+v feed=%+v", choice.Candidates, choice.Feed)
	}
	listed, err := List(ListParams{Ctx: ctx, Queries: database.Queries, UserID: bob})
	if err != nil || len(listed.Feeds) != 1 {
		t.Fatalf("list after several = %+v %v", listed.Feeds, err)
	}

	none := &scriptedFetch{page: pageBody{URL: page, ContentType: "text/html", Body: []byte(`<html>no feed</html>`)}}
	if _, err := Add(AddParams{
		Ctx: ctx, Queries: database.Queries, UserID: bob,
		URL: "https://blog.example/", Discover: true, Lookup: lookup, Fetch: none,
	}); !errors.Is(err, ErrNoFeed) {
		t.Fatalf("none = %v", err)
	}

	feedURL, err := url.Parse("https://blog.example/rss.xml?token=feed-token")
	if err != nil {
		t.Fatal(err)
	}
	feedDoc := &scriptedFetch{page: pageBody{
		URL:         feedURL,
		ContentType: "application/rss+xml",
		Body:        []byte(`<rss version="2.0"></rss>`),
	}}
	doc, err := Add(AddParams{
		Ctx: ctx, Queries: database.Queries, UserID: bob,
		URL:      feedURL.String(),
		Discover: true, Lookup: lookup, Fetch: feedDoc,
	})
	if err != nil {
		t.Fatal(err)
	}
	if doc.Feed.URL != feedURL.String() || doc.Feed.SiteLink != "" {
		t.Fatalf("feed document = %s site=%s", doc.Feed.URL, doc.Feed.SiteLink)
	}
}

func TestAddRejectsBeforeSaving(t *testing.T) {
	ctx := context.Background()
	if _, err := Add(AddParams{Ctx: ctx, UserID: 1, URL: "http://127.0.0.1/feed?token=opaque-token"}); !errors.Is(err, ErrForbiddenAddress) || strings.Contains(err.Error(), "opaque-token") {
		t.Fatalf("loopback = %v", err)
	}
	if _, err := Add(AddParams{Ctx: ctx, UserID: 1, URL: "https://missing.example/feed?token=opaque-token", Lookup: allowNames()}); !errors.Is(err, ErrUnresolved) || strings.Contains(err.Error(), "missing.example") || strings.Contains(err.Error(), "opaque-token") {
		t.Fatalf("unresolved = %v", err)
	}
	long := strings.Repeat("a", maxLabelLength+1)
	if _, err := Add(AddParams{Ctx: ctx, UserID: 1, URL: "http://203.0.113.5/feed", Name: long}); !errors.Is(err, ErrLabelTooLong) {
		t.Fatalf("long name = %v", err)
	}
	if _, err := Update(UpdateParams{Ctx: ctx, UserID: 1, ID: 1}); !errors.Is(err, ErrNoChange) {
		t.Fatalf("no change = %v", err)
	}
}

func TestListOrdersByFolderThenLabel(t *testing.T) {
	database := dbtest.NewDB(t)
	bob := newAccount(t, database, "bob")
	ctx := context.Background()
	for _, in := range []AddParams{
		{URL: "http://203.0.113.5/m", Name: "", Folder: ""},
		{URL: "http://203.0.113.6/z", Name: "zeta", Folder: "News"},
		{URL: "http://203.0.113.7/a", Name: "alpha", Folder: "news"},
		{URL: "http://203.0.113.8/arc", Name: "clips", Folder: "Archive"},
	} {
		in.Ctx, in.Queries, in.UserID = ctx, database.Queries, bob
		if _, err := Add(in); err != nil {
			t.Fatal(err)
		}
	}
	// The untitled row's title is empty, so give it one through the row the
	// sort reads. Name is empty and title is empty for every direct add, so
	// the empty folder still sorts first and the rest follow the label.
	listed, err := List(ListParams{Ctx: ctx, Queries: database.Queries, UserID: bob})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, feed := range listed.Feeds {
		got = append(got, feed.Folder+"/"+feed.Name)
	}
	want := []string{"/", "Archive/clips", "news/alpha", "News/zeta"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("order = %v", got)
	}
}

func strPtr(s string) *string { return &s }

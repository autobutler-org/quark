package accessutil_test

import (
	"context"
	"database/sql"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// get asks the cache for the fixture's account as of seq.
func (f fixture) get(t *testing.T, cache *accessutil.Cache, bus *eventbus.Bus, userID int64, seq uint64) accessutil.CacheGetResult {
	t.Helper()
	result, err := cache.Get(accessutil.CacheGetParams{
		Ctx:      context.Background(),
		Database: f.database,
		Storage:  f.storage,
		Bus:      bus,
		UserID:   userID,
		Seq:      seq,
	})
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	return result
}

// Two hundred sockets of one account hearing the same change go to the
// database once between them (#2764). Run under -race.
func TestCacheOneRefillPerChange(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "shared", accessutil.Read)
	bus := eventbus.New()
	cache := accessutil.NewCache(accessutil.CacheParams{})
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	seq := bus.Seq()

	var wg sync.WaitGroup
	for range 200 {
		wg.Go(func() {
			result, err := cache.Get(accessutil.CacheGetParams{
				Ctx: context.Background(), Database: f.database, Storage: f.storage,
				Bus: bus, UserID: f.userID, Seq: seq,
			})
			if err != nil || !result.Active || !result.Access.Check("", "shared", accessutil.Read).Readable {
				t.Errorf("Get = %+v, %v; want bob active and able to read shared", result, err)
			}
		})
	}
	wg.Wait()
	if got := cache.Refills(); got != 1 {
		t.Fatalf("Refills() = %d after one change, want 1", got)
	}

	// An event published before that refill started needs nothing new.
	f.get(t, cache, bus, f.userID, seq-1)
	if got := cache.Refills(); got != 1 {
		t.Fatalf("Refills() = %d for an older event, want still 1", got)
	}
}

// A grant revoked and announced is gone from the next answer for the event
// that announced it: the cache never hands back a snapshot older than the
// event it is asked about.
func TestCacheRevocationTakesEffectAtItsEvent(t *testing.T) {
	f := newFixture(t)
	f.grant(t, f.userID, "", "shared", accessutil.Read)
	bus := eventbus.New()
	cache := accessutil.NewCache(accessutil.CacheParams{})
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	if !f.get(t, cache, bus, f.userID, bus.Seq()).Access.Check("", "shared", accessutil.Read).Readable {
		t.Fatal("bob cannot read shared before the revocation")
	}

	if _, err := f.database.Queries.DeleteUserPathAccess(context.Background(), db.DeleteUserPathAccessParams{
		UserID: sql.NullInt64{Int64: f.userID, Valid: true}, RelPath: "shared",
	}); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "shared"})
	if f.get(t, cache, bus, f.userID, bus.Seq()).Access.Check("", "shared", accessutil.Read).Readable {
		t.Fatal("bob can still read shared after the access_changed that revoked it")
	}
}

// An account turned off, or whose role changed, reads as such from the next
// answer, so its streams can close.
func TestCacheReportsStatusAndRole(t *testing.T) {
	f := newFixture(t)
	bus := eventbus.New()
	cache := accessutil.NewCache(accessutil.CacheParams{})
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	if got := f.get(t, cache, bus, f.userID, bus.Seq()); !got.Active || got.Access.Principal().IsAdmin {
		t.Fatalf("got %+v, want bob active and not an admin", got)
	}

	ctx := context.Background()
	if err := f.database.Queries.SetUserAdmin(ctx, db.SetUserAdminParams{IsAdmin: 1, Username: "bob"}); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	if got := f.get(t, cache, bus, f.userID, bus.Seq()); !got.Active || !got.Access.Principal().IsAdmin {
		t.Fatalf("got %+v, want bob active and an admin", got)
	}

	if _, err := f.database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{
		ToStatus: authutil.StatusDisabled, Username: "bob", FromStatus: authutil.StatusActive,
	}); err != nil {
		t.Fatal(err)
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	if got := f.get(t, cache, bus, f.userID, bus.Seq()); got.Active {
		t.Fatalf("got %+v, want bob inactive once disabled", got)
	}

	if got := f.get(t, cache, bus, 9999, bus.Seq()); got.Active {
		t.Fatalf("got %+v for an account that does not exist, want inactive", got)
	}
}

// A load that fails is an error for everyone waiting on it and is not kept:
// a stream fails closed rather than filter against nothing.
func TestCacheFailsClosed(t *testing.T) {
	f := newFixture(t)
	bus := eventbus.New()
	cache := accessutil.NewCache(accessutil.CacheParams{})
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	_, err := cache.Get(accessutil.CacheGetParams{
		Ctx: context.Background(), Bus: bus, UserID: f.userID, Seq: bus.Seq(),
	})
	if err == nil {
		t.Fatal("Get with no database succeeded")
	}
	if got := f.get(t, cache, bus, f.userID, bus.Seq()); !got.Active {
		t.Fatalf("got %+v after a failed load, want a fresh load", got)
	}
}

// The cache holds at most Capacity accounts; one pushed out loads again.
func TestCacheIsBounded(t *testing.T) {
	f := newFixture(t)
	carol := createUser(t, f.database, "carol")
	bus := eventbus.New()
	cache := accessutil.NewCache(accessutil.CacheParams{Capacity: 1})
	bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	seq := bus.Seq()

	f.get(t, cache, bus, f.userID, seq)
	f.get(t, cache, bus, carol, seq)
	f.get(t, cache, bus, f.userID, seq)
	if got := cache.Refills(); got != 3 {
		t.Fatalf("Refills() = %d, want 3: bob was evicted for carol", got)
	}
}

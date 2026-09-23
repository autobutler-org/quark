package authutil_test

import (
	"context"
	"fmt"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestSetup_ConcurrentOnlyOneFoundingAdmin is the race quark-project #118
// describes: two first-boot requests with different usernames must not both
// succeed and both become admin.
func TestSetup_ConcurrentOnlyOneFoundingAdmin(t *testing.T) {
	database := newTestDB(t)
	queries := database.Queries
	ctx := context.Background()
	filesDir := t.TempDir()

	const n = 8
	type outcome struct {
		res *authutil.SetupResult
		err error
	}
	out := make([]outcome, n)

	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			res, err := authutil.Setup(ctx, authutil.SetupParams{
				Database: database,
				FilesDir: filesDir,
				Username: fmt.Sprintf("admin%d", i),
				Password: "supersecret",
			})
			out[i] = outcome{res: res, err: err}
		}(i)
	}
	close(start)
	wg.Wait()

	var winners int
	for i, o := range out {
		if o.err == nil {
			winners++
			if o.res == nil || o.res.SessionToken == "" {
				t.Errorf("setup %d succeeded without a session token", i)
			}
			continue
		}
		if o.err.Error() != "setup already complete" {
			t.Errorf("setup %d: unexpected error %v", i, o.err)
		}
	}
	if winners != 1 {
		t.Fatalf("expected exactly one successful setup, got %d", winners)
	}

	count, err := queries.CountUsers(ctx)
	if err != nil {
		t.Fatalf("CountUsers: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected 1 user after concurrent setup, got %d", count)
	}

	users, err := queries.ListActiveUsers(ctx)
	if err != nil {
		t.Fatalf("ListActiveUsers: %v", err)
	}
	if len(users) != 1 {
		t.Fatalf("expected 1 active user, got %d", len(users))
	}
	isAdmin, err := authutil.IsAdmin(ctx, queries, users[0].Username)
	if err != nil {
		t.Fatalf("IsAdmin: %v", err)
	}
	if !isAdmin {
		t.Fatalf("founding user %q is not admin", users[0].Username)
	}
}

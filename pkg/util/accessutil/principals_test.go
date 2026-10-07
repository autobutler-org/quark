package accessutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// TestListPrincipals lists who something can be shared with: active accounts
// only, and every group with everyone marked builtin.
func TestListPrincipals(t *testing.T) {
	f := newFixture(t)
	carol := createUser(t, f.database, "carol")
	pending := createUser(t, f.database, "pending")
	if _, err := f.database.Db.Exec(`UPDATE users SET status = 'pending' WHERE id = ?`, pending); err != nil {
		t.Fatal(err)
	}

	result, err := accessutil.ListPrincipals(accessutil.ListPrincipalsParams{Ctx: context.Background(), Database: f.database})
	if err != nil {
		t.Fatal(err)
	}
	users := map[int64]string{}
	for _, user := range result.Users {
		users[user.ID] = user.Username
	}
	if users[f.userID] != "bob" || users[carol] != "carol" {
		t.Errorf("users = %+v, want bob and carol", result.Users)
	}
	if _, listed := users[pending]; listed {
		t.Error("a pending account is offered to share with")
	}
	if len(result.Groups) == 0 || result.Groups[0].Name != "everyone" || !result.Groups[0].Builtin {
		t.Errorf("groups = %+v, want everyone first and builtin", result.Groups)
	}
}

func TestListPrincipalsNeedsADatabase(t *testing.T) {
	result, err := accessutil.ListPrincipals(accessutil.ListPrincipalsParams{Ctx: context.Background()})
	if !errors.Is(err, accessutil.ErrNoDatabase) {
		t.Errorf("ListPrincipals without a database = %+v, %v; want ErrNoDatabase", result, err)
	}
}

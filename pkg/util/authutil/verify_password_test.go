package authutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestVerifyPassword checks the gate in front of account deletion and reset
// (#2346): only the account's own auth key passes, a raw password is an app
// too old to send the key (#2430), and an account that no longer exists is
// told apart from a wrong key.
func TestVerifyPassword(t *testing.T) {
	database := newTestDB(t)
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, Files: vfs.NewMemVFS("files"), Username: "ada", AuthKey: dbtest.AuthKey("long-enough"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatalf("Setup: %v", err)
	}

	for _, tc := range []struct {
		username, password string
		want               error
	}{
		{"ada", dbtest.AuthKey("long-enough"), nil},
		{"ada", dbtest.AuthKey("wrong-password"), authutil.ErrIncorrectPassword},
		{"ada", "", authutil.ErrIncorrectPassword},
		{"ada", "long-enough", authutil.ErrAppTooOld},
		{"nobody", dbtest.AuthKey("long-enough"), authutil.ErrUserNotFound},
	} {
		_, err := authutil.VerifyPassword(ctx, authutil.VerifyPasswordParams{
			Queries:  database.Queries,
			Username: tc.username,
			Password: tc.password,
		})
		if !errors.Is(err, tc.want) {
			t.Errorf("%s/%q: err = %v, want %v", tc.username, tc.password, err, tc.want)
		}
	}
}

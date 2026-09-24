package authutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestVerifyPassword checks the gate in front of account deletion and reset
// (#2346): only the account's own password passes, and an account that no
// longer exists is told apart from a wrong password.
func TestVerifyPassword(t *testing.T) {
	database := newTestDB(t)
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "ada", Password: "long-enough"}); err != nil {
		t.Fatalf("Setup: %v", err)
	}

	for _, tc := range []struct {
		username, password string
		want               error
	}{
		{"ada", "long-enough", nil},
		{"ada", "wrong-password", authutil.ErrIncorrectPassword},
		{"ada", "", authutil.ErrIncorrectPassword},
		{"nobody", "long-enough", authutil.ErrUserNotFound},
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

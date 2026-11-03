package authutil_test

import (
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestRecoveryPhraseWords covers the word count a client reports beside a
// recovery key (#3183): every write path stores it with the key, a count out
// of range is refused, and GetAuthStatus calls an account short below
// RecoveryPhraseWords or with no count, and never one with no key.
func TestRecoveryPhraseWords(t *testing.T) {
	ctx := context.Background()
	database := newTestDB(t)
	queries := database.Queries
	if _, err := authutil.Setup(ctx, authutil.SetupParams{
		Database: database, Files: vfs.NewMemVFS("files"), Username: "ada",
		AuthKey: authKeyOf(1), RecoveryKey: authKeyOf(9), RecoveryPhraseWords: authutil.RecoveryPhraseWords, SaltSecret: saltSecret,
	}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	if _, err := authutil.RequestAccount(ctx, queries, authutil.RequestAccountParams{
		Username: "bea", AuthKey: authKeyOf(2), RecoveryKey: authKeyOf(8), RecoveryPhraseWords: 6, SaltSecret: saltSecret, RequestsEnabled: true,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.CreateUser(ctx, authutil.CreateUserParams{Database: database, Username: "cy", AuthKey: authKeyOf(3), SaltSecret: saltSecret, Files: vfs.NewMemVFS("files")}); err != nil {
		t.Fatal(err)
	}
	addLegacy(t, queries)

	for name, want := range map[string]int64{"ada": 16, "bea": 6, "cy": 0} {
		if got := userRow(t, queries, name).RecoveryPhraseWords; got != want {
			t.Errorf("%s stored %d words, want %d", name, got, want)
		}
	}

	shortFor := func(name string, authKey string) bool {
		t.Helper()
		session, err := authutil.Login(ctx, queries, authutil.LoginParams{Username: name, AuthKey: authKey})
		if err != nil {
			t.Fatalf("login %s: %v", name, err)
		}
		status, err := authutil.GetAuthStatus(ctx, queries, authutil.GetAuthStatusParams{SessionToken: session.SessionToken})
		if err != nil || !status.Authenticated {
			t.Fatalf("status %s = %+v %v", name, status, err)
		}
		return status.ShortRecoveryPhrase
	}
	if shortFor("ada", authKeyOf(1)) {
		t.Error("a 16-word phrase reads short")
	}
	if shortFor("cy", authKeyOf(3)) {
		t.Error("an account with no recovery key reads short; legacyRecovery covers it")
	}

	set := func(words int) error {
		_, err := authutil.SetRecoveryKey(ctx, database, authutil.SetRecoveryKeyParams{
			UserID: userRow(t, queries, "cy").ID, RecoveryKey: authKeyOf(7), RecoveryPhraseWords: words,
		})
		return err
	}
	for _, words := range []int{-1, 65} {
		if err := set(words); !errors.Is(err, authutil.ErrInvalidRecoveryPhraseWords) {
			t.Errorf("%d words = %v, want ErrInvalidRecoveryPhraseWords", words, err)
		}
	}
	for _, tc := range []struct {
		words int
		short bool
	}{{0, true}, {6, true}, {16, false}} {
		if err := set(tc.words); err != nil {
			t.Fatal(err)
		}
		if got := userRow(t, queries, "cy").RecoveryPhraseWords; got != int64(tc.words) {
			t.Errorf("SetRecoveryKey stored %d words, want %d", got, tc.words)
		}
		if got := shortFor("cy", authKeyOf(3)); got != tc.short {
			t.Errorf("%d words: short = %v, want %v", tc.words, got, tc.short)
		}
	}

	// A legacy phrase recovery stores the new phrase's count with its key.
	if _, err := authutil.Recover(ctx, database, authutil.RecoverParams{
		Username: "old", RecoveryPhrase: "old-phrase", NewAuthKey: authKeyOf(5), NewRecoveryKey: authKeyOf(6),
		NewRecoveryPhraseWords: authutil.RecoveryPhraseWords, SaltSecret: saltSecret,
	}); err != nil {
		t.Fatal(err)
	}
	if got := userRow(t, queries, "old").RecoveryPhraseWords; got != authutil.RecoveryPhraseWords {
		t.Errorf("Recover stored %d words, want %d", got, authutil.RecoveryPhraseWords)
	}
}

// TestIsShortRecoveryPhrase pins the rule GetAuthStatus and GET /admin/users
// share (#3183).
func TestIsShortRecoveryPhrase(t *testing.T) {
	for _, tc := range []struct {
		hasKey bool
		words  int64
		want   bool
	}{
		{false, 0, false},
		{false, 6, false},
		{true, 0, true},
		{true, 6, true},
		{true, authutil.RecoveryPhraseWords - 1, true},
		{true, authutil.RecoveryPhraseWords, false},
		{true, 24, false},
	} {
		if got := authutil.IsShortRecoveryPhrase(tc.hasKey, tc.words); got != tc.want {
			t.Errorf("IsShortRecoveryPhrase(%v, %d) = %v, want %v", tc.hasKey, tc.words, got, tc.want)
		}
	}
}

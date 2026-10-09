package authutil_test

import (
	"encoding/base64"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestDeriveKey_MatchesTheApp pins DeriveKey to the vectors
// test/services/chat_crypto_test.dart pins ChatCrypto to: the salt is the
// bytes 0 through 15. A key that differs from the app's signs nobody in.
func TestDeriveKey_MatchesTheApp(t *testing.T) {
	salt := base64.StdEncoding.EncodeToString([]byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15})
	for _, tc := range []struct {
		name, secret, want string
		recovery           bool
	}{
		{"the auth key", "correct horse battery staple", "zNR6rA8kTcAq8wwj0fjQh9lSZ0A3+VNjah0pZEMf7XU=", false},
		{"the recovery key", "abandon-ability-able-about-above-absent", "mvSfNFyawdUYP8Sp/ldQ6Zg+ka7XSRpmfJyOYFcprBQ=", true},
		{"a phrase is lowercased and trimmed", "  Abandon-Ability-able-about-above-ABSENT\n", "mvSfNFyawdUYP8Sp/ldQ6Zg+ka7XSRpmfJyOYFcprBQ=", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := authutil.DeriveKey(authutil.DeriveKeyParams{Secret: tc.secret, Salt: salt, Recovery: tc.recovery})
			if err != nil {
				t.Fatal(err)
			}
			if got.Key != tc.want {
				t.Errorf("DeriveKey = %q, want %q", got.Key, tc.want)
			}
		})
	}
}

// TestDeriveKey_RefusesABadSalt keeps a salt that is not a Quark's from
// giving a key that looks right and signs nobody in.
func TestDeriveKey_RefusesABadSalt(t *testing.T) {
	for _, salt := range []string{"", "not base64!", base64.StdEncoding.EncodeToString([]byte("short"))} {
		if _, err := authutil.DeriveKey(authutil.DeriveKeyParams{Secret: "a-password", Salt: salt}); err == nil {
			t.Errorf("DeriveKey with salt %q gave no error", salt)
		}
	}
}

package v0_auth_test

import (
	"net/http"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestRawSecrets_UpdateTheApp sends every body an app from before auth keys
// sends to every public endpoint that read a raw password or phrase, along
// with the half-keyed shapes an app between the two layers sent. Each is the
// same 426 and the same update-the-app sentence, which released apps show as
// it is, and none of them touches an account (#2430). Setup is already done,
// so a 426 that came after the lookup would have been "setup already
// complete" instead. The legacy account "old" is refused too, so a 426 does
// not hang on whether the account could still take the shape's secret.
func TestRawSecrets_UpdateTheApp(t *testing.T) {
	engine, database := newAuthKeyEngine(t)
	createRecoverableUser(t, database.Queries, "bob", "bob-phrase")
	before, oldBefore := userByName(t, database.Queries, "bob"), userByName(t, database.Queries, "old")
	key, recoveryKey := dbtest.AuthKey("original-password"), dbtest.AuthKey("bob-phrase")

	for _, tc := range []struct {
		path string
		body map[string]string
	}{
		{"/api/v0/auth/login", map[string]string{"username": "bob", "password": "original-password"}},
		{"/api/v0/auth/login", map[string]string{"username": "old", "password": "old-password"}},
		{"/api/v0/auth/login", map[string]string{"username": "nobody", "password": "anything"}},
		{"/api/v0/auth/setup", map[string]string{"username": "owner", "password": "long-enough"}},
		{"/api/v0/auth/setup", map[string]string{"username": "owner", "password": "long-enough", "authKey": key}},
		{"/api/v0/auth/request-account", map[string]string{"username": "asker", "password": "long-enough"}},
		{"/api/v0/auth/request-account", map[string]string{"username": "asker", "password": "long-enough", "authKey": key, "recoveryKey": recoveryKey}},
		{"/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryPhrase": "bob-phrase", "newPassword": "brand-new-password"}},
		{"/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryPhrase": "bob-phrase", "newAuthKey": key}},
		{"/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryKey": recoveryKey, "newPassword": "brand-new-password"}},
		{"/api/v0/auth/recover", map[string]string{"username": "bob", "recoveryPhrase": "bob-phrase", "recoveryKey": recoveryKey, "newAuthKey": key}},
		{"/api/v0/auth/recover", map[string]string{"username": "old", "recoveryPhrase": "old-phrase", "newPassword": "brand-new-password"}},
		{"/api/v0/auth/recover", map[string]string{"username": "old", "recoveryPhrase": "old-phrase", "newAuthKey": key}},
		{"/api/v0/auth/recover", map[string]string{"username": "old", "recoveryPhrase": "old-phrase", "newRecoveryKey": recoveryKey}},
	} {
		w := postJSON(engine, tc.path, tc.body)
		if w.Code != http.StatusUpgradeRequired || decodeBody(t, w)["error"] != authutil.ErrAppTooOld.Error() {
			t.Errorf("%s %v = %d %s, want 426 with the update-the-app copy", tc.path, tc.body, w.Code, w.Body)
		}
	}

	if after := userByName(t, database.Queries, "bob"); after != before {
		t.Errorf("a refused body changed bob: %+v, was %+v", after, before)
	}
	if after := userByName(t, database.Queries, "old"); after != oldBefore {
		t.Errorf("a refused body changed old: %+v, was %+v", after, oldBefore)
	}
	for _, name := range []string{"owner", "asker"} {
		if _, err := database.Queries.GetUserByUsername(t.Context(), name); err == nil {
			t.Errorf("a refused body made %s", name)
		}
	}
	// The key flows next to them are untouched.
	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "bob", "authKey": key}); w.Code != http.StatusOK {
		t.Errorf("auth key login = %d %s, want 200", w.Code, w.Body)
	}
}

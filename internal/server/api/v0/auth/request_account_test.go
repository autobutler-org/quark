package v0_auth_test

import (
	"context"
	"net/http"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// TestRequestAccount_Endpoint drives POST /auth/request-account through each
// outcome: refused before setup, created with an event and no phrase, refused
// for a taken or invalid name, and refused once an admin turns requests off.
// GET /auth/status reports the toggle as it changes.
func TestRequestAccount_Endpoint(t *testing.T) {
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	database := dbtest.NewDB(t)
	ctx := context.Background()
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	t.Cleanup(unsubscribe)
	deps := deputil.NewDependencies().WithDatabase(database).WithEventBus(bus)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())
	post := func(username, authKey string) int {
		t.Helper()
		return postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": username, "authKey": authKey, "recoveryKey": dbtest.AuthKey(username + "-phrase")}).Code
	}
	statusBody := func() map[string]any {
		t.Helper()
		w := getPath(engine, "/api/v0/auth/status")
		return decodeBody(t, w)
	}

	if got := post("bob", dbtest.AuthKey("bob-password")); got != http.StatusNotFound {
		t.Errorf("request before setup = %d, want 404", got)
	}
	if body := statusBody(); len(body) != 1 || body["setup"] != false {
		t.Errorf("status before setup = %v, want only setup=false", body)
	}

	if _, err := authutil.Setup(ctx, authutil.SetupParams{Database: database, Files: vfs.NewMemVFS("files"), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	if body := statusBody(); body["accessRequestsEnabled"] != true {
		t.Errorf("status after setup = %v, want accessRequestsEnabled=true", body)
	}

	w := postJSON(engine, "/api/v0/auth/request-account", map[string]string{"username": "bob", "authKey": dbtest.AuthKey("bob-password"), "recoveryKey": dbtest.AuthKey("bob-phrase")})
	if w.Code != http.StatusCreated {
		t.Fatalf("request = %d, want 201: %s", w.Code, w.Body.String())
	}
	if body := decodeBody(t, w); len(body) != 0 {
		t.Errorf("request body %s, want an empty object: the app made the phrase", w.Body.String())
	}
	select {
	case evt := <-events:
		if evt.Kind != eventbus.EventAccountChanged {
			t.Errorf("event = %q, want account_changed", evt.Kind)
		}
	default:
		t.Error("a new request published no account_changed")
	}
	if user, err := database.Queries.GetUserByUsername(ctx, "bob"); err != nil || user.Status != authutil.StatusPending {
		t.Errorf("bob = %+v (err %v), want a pending row", user, err)
	}

	for _, tc := range []struct {
		name, username, authKey string
		want                    int
	}{
		{"pending name", "bob", dbtest.AuthKey("other-password"), http.StatusConflict},
		{"account name", "admin", dbtest.AuthKey("other-password"), http.StatusConflict},
		{"invalid name", "../x", dbtest.AuthKey("long-enough"), http.StatusBadRequest},
		{"malformed key", "carol", "short", http.StatusBadRequest},
		{"missing key", "carol", "", http.StatusBadRequest},
	} {
		if got := post(tc.username, tc.authKey); got != tc.want {
			t.Errorf("%s = %d, want %d", tc.name, got, tc.want)
		}
	}

	if err := settingsutil.SetAccessRequestsEnabled(false); err != nil {
		t.Fatal(err)
	}
	if got := post("carol", dbtest.AuthKey("carol-password")); got != http.StatusNotFound {
		t.Errorf("request with requests off = %d, want 404", got)
	}
	if body := statusBody(); body["accessRequestsEnabled"] != false {
		t.Errorf("status with requests off = %v, want accessRequestsEnabled=false", body)
	}
}

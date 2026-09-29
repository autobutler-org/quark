package v0_settings_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_settings "github.com/autobutler-org/quark/internal/server/api/v0/settings"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/featureflagutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// featuresHarness mounts the settings routers the way routes.go does, the
// admin one behind RequireAdmin, on a database holding an admin and a member.
// X-Test-User picks which of them makes a request.
type featuresHarness struct {
	engine *gin.Engine
	events <-chan eventbus.Event
	path   string
}

func newFeaturesHarness(t *testing.T) featuresHarness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	path := filepath.Join(t.TempDir(), "settings.json")
	settingsutil.ResetForTesting(path)

	database := dbtest.NewDB(t)
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, authutil.SetupParams{
		Database: database, Username: "admin", Password: "admin-password", FilesDir: t.TempDir(),
	}); err != nil {
		t.Fatal(err)
	}
	hash, err := authutil.HashPassword("member-password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "member", PasswordHash: hash, RecoveryPhraseHash: hash}); err != nil {
		t.Fatal(err)
	}

	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	t.Cleanup(unsubscribe)
	deps := deputil.NewDependencies().WithDatabase(database).WithEventBus(bus)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "username", c.GetHeader("X-Test-User"))
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_settings.NewRouter())
	serverutil.RegisterRouterWithGroup(group.Group("", middleware.RequireAdmin(deps)), v0_settings.NewAdminRouter())
	return featuresHarness{engine: engine, events: events, path: path}
}

func (h featuresHarness) do(user, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Test-User", user)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

// published counts the feature_flag_changed events so far.
func (h featuresHarness) published() int {
	n := 0
	for {
		select {
		case evt := <-h.events:
			if evt.Kind == eventbus.EventFeatureFlagChanged {
				n++
			}
		default:
			return n
		}
	}
}

// chatState returns chat's entry from GET /settings/features as user.
func (h featuresHarness) chatState(t *testing.T, user string) featureflagutil.FlagState {
	t.Helper()
	w := h.do(user, http.MethodGet, "/api/v0/settings/features", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /settings/features as %s = %d: %s", user, w.Code, w.Body.String())
	}
	var got featureflagutil.ListFlagsResult
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	for _, f := range got.Features {
		if f.Key == featureflagutil.Chat {
			return f
		}
	}
	t.Fatalf("chat missing from %s", w.Body.String())
	return featureflagutil.FlagState{}
}

// TestListFeatures_DefaultForAnyUser checks a member can read the flags and
// that chat reports its registry default while nobody has set it.
func TestListFeatures_DefaultForAnyUser(t *testing.T) {
	h := newFeaturesHarness(t)
	chat := h.chatState(t, "member")
	if !chat.Enabled || !chat.Default || chat.SunsetIssue != 2577 || chat.Label == "" || chat.Description == "" {
		t.Errorf("chat = %+v; want on by default, with its copy and sunset issue", chat)
	}
}

// TestUpdateFeature_AdminPersists checks an admin's PUT is stored, survives a
// reload, is what every user then reads, and tells open apps.
func TestUpdateFeature_AdminPersists(t *testing.T) {
	h := newFeaturesHarness(t)
	w := h.do("admin", http.MethodPut, "/api/v0/settings/features/chat", `{"enabled":false}`)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT = %d: %s", w.Code, w.Body.String())
	}
	var got featureflagutil.FlagState
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Key != featureflagutil.Chat || got.Enabled {
		t.Errorf("response = %+v; want chat off", got)
	}
	if n := h.published(); n != 1 {
		t.Errorf("published %d feature_flag_changed events; want 1", n)
	}
	settingsutil.ResetForTesting(h.path)
	if h.chatState(t, "member").Enabled {
		t.Error("chat is on for a member after an admin turned it off")
	}
}

// TestUpdateFeature_Refusals checks a member is forbidden, a body that does
// not say on or off is refused, and an unknown or retired key is 404; none of
// them changes anything or publishes.
func TestUpdateFeature_Refusals(t *testing.T) {
	h := newFeaturesHarness(t)
	for _, tc := range []struct {
		name, user, path, body string
		want                   int
	}{
		{"member", "member", "/api/v0/settings/features/chat", `{"enabled":false}`, http.StatusForbidden},
		{"empty body", "admin", "/api/v0/settings/features/chat", `{}`, http.StatusBadRequest},
		{"unknown key", "admin", "/api/v0/settings/features/nope", `{"enabled":true}`, http.StatusNotFound},
		{"retired key", "admin", "/api/v0/settings/features/chatEnabled", `{"enabled":false}`, http.StatusNotFound},
	} {
		if w := h.do(tc.user, http.MethodPut, tc.path, tc.body); w.Code != tc.want {
			t.Errorf("%s: PUT = %d, want %d: %s", tc.name, w.Code, tc.want, w.Body.String())
		}
	}
	if !h.chatState(t, "admin").Enabled {
		t.Error("a refused PUT turned chat off")
	}
	if n := h.published(); n != 0 {
		t.Errorf("refused PUTs published %d events", n)
	}
	for _, key := range []string{"nope", "chatEnabled"} {
		if _, set, _ := settingsutil.GetFeatureFlag(key); set {
			t.Errorf("refused key %q was stored", key)
		}
	}
}

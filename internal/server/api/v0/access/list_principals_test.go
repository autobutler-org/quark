package v0_access_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_access "github.com/autobutler-org/quark/internal/server/api/v0/access"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// TestListPrincipals checks a non-admin gets every active account and every
// group, and that accounts carry only an id and a username: no pending or
// disabled account, and no status or admin field.
func TestListPrincipals(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)
	ids := map[string]int64{}
	for _, name := range []string{"carol", "bob", "off"} {
		user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		ids[name] = user.ID
	}
	if _, err := database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{Username: "off", FromStatus: "active", ToStatus: "disabled"}); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.CreatePendingUser(ctx, db.CreatePendingUserParams{Username: "waiting", PasswordHash: "h", RecoveryPhraseHash: "r"}); err != nil {
		t.Fatal(err)
	}
	family, err := database.Queries.CreateGroup(ctx, "Family")
	if err != nil {
		t.Fatal(err)
	}
	everyone, err := database.Queries.ListGroups(ctx)
	if err != nil {
		t.Fatal(err)
	}

	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: ids["bob"]})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_access.NewRouter())
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/access/principals", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("GET /access/principals = %d %s", w.Code, w.Body.String())
	}

	var raw struct {
		Users  []map[string]any `json:"users"`
		Groups []map[string]any `json:"groups"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	wantUsers := []map[string]any{
		{"id": float64(ids["bob"]), "username": "bob"},
		{"id": float64(ids["carol"]), "username": "carol"},
	}
	if !reflect.DeepEqual(raw.Users, wantUsers) {
		t.Errorf("users = %v, want only the active accounts' ids and usernames %v", raw.Users, wantUsers)
	}
	wantGroups := []map[string]any{
		{"id": float64(everyone[0].ID), "name": "everyone", "builtin": true},
		{"id": float64(family.ID), "name": "Family", "builtin": false},
	}
	if !reflect.DeepEqual(raw.Groups, wantGroups) {
		t.Errorf("groups = %v, want %v", raw.Groups, wantGroups)
	}
}

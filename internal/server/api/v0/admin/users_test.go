package v0_admin_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_admin "github.com/autobutler-org/quark/internal/server/api/v0/admin"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// adminHarness is the admin router on a migrated database, called as the
// founding admin the way routes.go mounts it behind RequireAdmin.
type adminHarness struct {
	database *db.DatabaseSqlc
	engine   *gin.Engine
	events   <-chan eventbus.Event
	adminID  int64
}

func newAdminHarness(t *testing.T) adminHarness {
	t.Helper()
	database := dbtest.NewDB(t)
	ctx := context.Background()
	if _, err := authutil.Setup(ctx, database.Queries, authutil.SetupParams{Username: "admin", Password: "admin-password"}); err != nil {
		t.Fatal(err)
	}
	admin, err := database.Queries.GetUserByUsername(ctx, "admin")
	if err != nil {
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
		c = ctxutil.With(c, "username", "admin")
		c = ctxutil.With(c, "userID", admin.ID)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_admin.NewRouter())
	return adminHarness{database: database, engine: engine, events: events, adminID: admin.ID}
}

func (h adminHarness) do(method, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

// addUser creates an account with password "user-password" in status.
func (h adminHarness) addUser(t *testing.T, username, status string, admin bool) {
	t.Helper()
	ctx := context.Background()
	hash, err := authutil.HashPassword("user-password")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.database.Queries.CreateUser(ctx, db.CreateUserParams{Username: username, PasswordHash: hash, RecoveryPhraseHash: hash}); err != nil {
		t.Fatal(err)
	}
	if admin {
		if err := authutil.PromoteToAdmin(ctx, h.database.Queries, username); err != nil {
			t.Fatal(err)
		}
	}
	if status != authutil.StatusActive {
		if _, err := h.database.Queries.SetUserStatus(ctx, db.SetUserStatusParams{Username: username, FromStatus: authutil.StatusActive, ToStatus: status}); err != nil {
			t.Fatal(err)
		}
	}
}

// drainEvents counts the account_changed events published so far.
func (h adminHarness) drainEvents() int {
	count := 0
	for {
		select {
		case evt := <-h.events:
			if evt.Kind == eventbus.EventAccountChanged {
				count++
			}
		default:
			return count
		}
	}
}

func errorText(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var body struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %q: %v", w.Body.String(), err)
	}
	return body.Error
}

// TestListUsers_IncludesStatus checks every account is listed with its status.
func TestListUsers_IncludesStatus(t *testing.T) {
	h := newAdminHarness(t)
	h.addUser(t, "waiting", authutil.StatusPending, false)
	h.addUser(t, "off", authutil.StatusDisabled, false)

	w := h.do(http.MethodGet, "/api/v0/admin/users")
	if w.Code != http.StatusOK {
		t.Fatalf("list = %d: %s", w.Code, w.Body.String())
	}
	var users []struct {
		Username string `json:"username"`
		IsAdmin  bool   `json:"isAdmin"`
		Status   string `json:"status"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &users); err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, u := range users {
		got[u.Username] = u.Status
	}
	want := map[string]string{"admin": "active", "waiting": "pending", "off": "disabled"}
	if len(got) != len(want) {
		t.Fatalf("listed %v, want %v", got, want)
	}
	for name, status := range want {
		if got[name] != status {
			t.Errorf("%s status = %q, want %q", name, got[name], status)
		}
	}
}

// TestDemoteUser_LastActiveAdminIsConflict checks the last active admin cannot
// be demoted, with the sentinel's own text and no event, and that a disabled
// admin does not count as a second one. A second active admin makes it work.
func TestDemoteUser_LastActiveAdminIsConflict(t *testing.T) {
	h := newAdminHarness(t)
	h.addUser(t, "sleeping", authutil.StatusDisabled, true)

	w := h.do(http.MethodPut, "/api/v0/admin/demote/admin")
	if w.Code != http.StatusConflict {
		t.Fatalf("demote last active admin = %d, want 409: %s", w.Code, w.Body.String())
	}
	if got := errorText(t, w); got != authutil.ErrLastAdmin.Error() {
		t.Errorf("error = %q, want %q", got, authutil.ErrLastAdmin.Error())
	}
	if n := h.drainEvents(); n != 0 {
		t.Errorf("refused demote published %d account_changed events", n)
	}

	h.addUser(t, "deputy", authutil.StatusActive, true)
	if w := h.do(http.MethodPut, "/api/v0/admin/demote/deputy"); w.Code != http.StatusOK {
		t.Errorf("demote with two active admins = %d: %s", w.Code, w.Body.String())
	}
	if w := h.do(http.MethodPut, "/api/v0/admin/demote/admin"); w.Code != http.StatusConflict {
		t.Errorf("demote the only active admin once the second is gone = %d, want 409", w.Code)
	}
}

// TestPromoteUser_OnlyActive checks promoting a pending, disabled or unknown
// account is 404, and an active one works and publishes account_changed.
func TestPromoteUser_OnlyActive(t *testing.T) {
	h := newAdminHarness(t)
	h.addUser(t, "waiting", authutil.StatusPending, false)
	h.addUser(t, "off", authutil.StatusDisabled, false)
	h.addUser(t, "member", authutil.StatusActive, false)

	for _, name := range []string{"waiting", "off", "nobody"} {
		if w := h.do(http.MethodPut, "/api/v0/admin/promote/"+name); w.Code != http.StatusNotFound {
			t.Errorf("promote %s = %d, want 404: %s", name, w.Code, w.Body.String())
		}
	}
	if n := h.drainEvents(); n != 0 {
		t.Errorf("refused promotes published %d events", n)
	}
	if w := h.do(http.MethodPut, "/api/v0/admin/promote/member"); w.Code != http.StatusOK {
		t.Errorf("promote member = %d: %s", w.Code, w.Body.String())
	}
	if n := h.drainEvents(); n != 1 {
		t.Errorf("promote published %d account_changed events, want 1", n)
	}
}

package v0_notifications_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_notifications "github.com/autobutler-org/quark/internal/server/api/v0/notifications"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
	"github.com/gin-gonic/gin"
)

// harness is the router on a real database holding an admin and a member.
type harness struct {
	engine            *gin.Engine
	queries           *db.Queries
	adminID, memberID int64
}

// newHarness serves the router to a caller named by the X-Test-User header:
// "admin", "member", or nobody.
func newHarness(t *testing.T) harness {
	t.Helper()
	database := dbtest.NewDB(t)
	addUser := func(username string) int64 {
		user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{Username: username, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		return user.ID
	}
	adminID, memberID := addUser("admin"), addUser("member")
	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		switch c.GetHeader("X-Test-User") {
		case "admin":
			c = ctxutil.With(c, "principal", accessutil.Principal{UserID: adminID, IsAdmin: true})
		case "member":
			c = ctxutil.With(c, "principal", accessutil.Principal{UserID: memberID})
		}
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_notifications.NewRouter())
	return harness{engine: engine, queries: database.Queries, adminID: adminID, memberID: memberID}
}

// disable turns backup_due off in one account's own settings.
func (h harness) disable(t *testing.T, userID int64) {
	t.Helper()
	if _, err := usersettingsutil.Save(context.Background(), usersettingsutil.SaveParams{
		Queries: h.queries, UserID: userID,
		Settings: usersettingsutil.Settings{DisabledNotifications: []notificationutil.Type{notificationutil.TypeBackupDue}},
	}); err != nil {
		t.Fatal(err)
	}
}

func (h harness) list(t *testing.T, user string) []notificationutil.Notification {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/v0/notifications", nil)
	req.Header.Set("X-Test-User", user)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("GET as %s = %d: %s", user, w.Code, w.Body.String())
	}
	var result notificationutil.ListResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	if result.Notifications == nil {
		t.Fatalf("notifications is not an array: %s", w.Body.String())
	}
	return result.Notifications
}

func TestListNotifications_AdminWithNoBackupIsDue(t *testing.T) {
	h := newHarness(t)
	got := h.list(t, "admin")
	if len(got) != 1 || got[0].Type != notificationutil.TypeBackupDue || got[0].Link != notificationutil.BackupLink {
		t.Fatalf("notifications = %+v, want one backup_due linking to %s", got, notificationutil.BackupLink)
	}
}

func TestListNotifications_ClearsAfterSnapshot(t *testing.T) {
	h := newHarness(t)
	if err := backup.RecordSnapshot(context.Background(), h.queries, time.Now()); err != nil {
		t.Fatal(err)
	}
	if got := h.list(t, "admin"); len(got) != 0 {
		t.Fatalf("notifications after a snapshot = %+v, want none", got)
	}
}

func TestListNotifications_AdminWithOldBackupIsStale(t *testing.T) {
	h := newHarness(t)
	last := time.Now().Add(-notificationutil.BackupStaleAfter - time.Hour)
	if err := backup.RecordSnapshot(context.Background(), h.queries, last); err != nil {
		t.Fatal(err)
	}
	got := h.list(t, "admin")
	if len(got) != 1 || got[0].Type != notificationutil.TypeBackupStale || got[0].LastBackupAt == nil {
		t.Fatalf("notifications = %+v, want one backup_stale with lastBackupAt", got)
	}
}

func TestListNotifications_NonAdminGetsNone(t *testing.T) {
	h := newHarness(t)
	if got := h.list(t, "member"); len(got) != 0 {
		t.Fatalf("a member's notifications = %+v, want none", got)
	}
}

// TestListNotifications_DisabledTypeIsOmitted checks the caller's own setting
// is the one read: another account turning backup_due off changes nothing for
// the admin, and the admin turning it off leaves them with none.
func TestListNotifications_DisabledTypeIsOmitted(t *testing.T) {
	h := newHarness(t)
	h.disable(t, h.memberID)
	if got := h.list(t, "admin"); len(got) != 1 {
		t.Fatalf("notifications after another account turned backup_due off = %+v, want one", got)
	}
	h.disable(t, h.adminID)
	if got := h.list(t, "admin"); len(got) != 0 {
		t.Fatalf("notifications with backup_due turned off = %+v, want none", got)
	}
}

func TestListNotifications_RequiresSignIn(t *testing.T) {
	h := newHarness(t)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/notifications", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("GET with no caller = %d, want 401: %s", w.Code, w.Body.String())
	}
}

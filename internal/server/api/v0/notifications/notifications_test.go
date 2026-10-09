package v0_notifications_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	v0_notifications "github.com/autobutler-org/quark/internal/server/api/v0/notifications"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
	"github.com/gin-gonic/gin"
)

const (
	adminID  int64 = 1
	memberID int64 = 2
)

// newEngine serves the router to a caller named by the X-Test-User header:
// "admin", "member", or nobody. The data directory is a temp dir.
func newEngine(t *testing.T) *gin.Engine {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		switch c.GetHeader("X-Test-User") {
		case "admin":
			c = ctxutil.With(c, "principal", accessutil.Principal{UserID: adminID, IsAdmin: true})
		case "member":
			c = ctxutil.With(c, "principal", accessutil.Principal{UserID: memberID})
		}
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_notifications.NewRouter())
	return engine
}

func list(t *testing.T, engine *gin.Engine, user string) []notificationutil.Notification {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/v0/notifications", nil)
	req.Header.Set("X-Test-User", user)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
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
	engine := newEngine(t)
	got := list(t, engine, "admin")
	if len(got) != 1 || got[0].Type != notificationutil.TypeBackupDue || got[0].Link != notificationutil.BackupLink {
		t.Fatalf("notifications = %+v, want one backup_due linking to %s", got, notificationutil.BackupLink)
	}
}

func TestListNotifications_ClearsAfterSnapshot(t *testing.T) {
	engine := newEngine(t)
	if err := backup.RecordSnapshot(storageutil.GetDataDir(), time.Now()); err != nil {
		t.Fatal(err)
	}
	if got := list(t, engine, "admin"); len(got) != 0 {
		t.Fatalf("notifications after a snapshot = %+v, want none", got)
	}
}

func TestListNotifications_AdminWithOldBackupIsStale(t *testing.T) {
	engine := newEngine(t)
	last := time.Now().Add(-notificationutil.BackupStaleAfter - time.Hour)
	if err := backup.RecordSnapshot(storageutil.GetDataDir(), last); err != nil {
		t.Fatal(err)
	}
	got := list(t, engine, "admin")
	if len(got) != 1 || got[0].Type != notificationutil.TypeBackupStale || got[0].LastBackupAt == nil {
		t.Fatalf("notifications = %+v, want one backup_stale with lastBackupAt", got)
	}
}

func TestListNotifications_NonAdminGetsNone(t *testing.T) {
	engine := newEngine(t)
	if got := list(t, engine, "member"); len(got) != 0 {
		t.Fatalf("a member's notifications = %+v, want none", got)
	}
}

// TestListNotifications_DisabledTypeIsOmitted checks the caller's own setting
// is the one read: another account turning backup_due off changes nothing for
// the admin, and the admin turning it off leaves them with none.
func TestListNotifications_DisabledTypeIsOmitted(t *testing.T) {
	engine := newEngine(t)
	if _, err := usersettingsutil.Save(usersettingsutil.SaveParams{
		DataDir: storageutil.GetDataDir(), UserID: memberID,
		Settings: usersettingsutil.Settings{DisabledNotifications: []notificationutil.Type{notificationutil.TypeBackupDue}},
	}); err != nil {
		t.Fatal(err)
	}
	if got := list(t, engine, "admin"); len(got) != 1 {
		t.Fatalf("notifications after another account turned backup_due off = %+v, want one", got)
	}
	if _, err := usersettingsutil.Save(usersettingsutil.SaveParams{
		DataDir: storageutil.GetDataDir(), UserID: adminID,
		Settings: usersettingsutil.Settings{DisabledNotifications: []notificationutil.Type{notificationutil.TypeBackupDue}},
	}); err != nil {
		t.Fatal(err)
	}
	if got := list(t, engine, "admin"); len(got) != 0 {
		t.Fatalf("notifications with backup_due turned off = %+v, want none", got)
	}
}

func TestListNotifications_RequiresSignIn(t *testing.T) {
	engine := newEngine(t)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/notifications", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("GET with no caller = %d, want 401: %s", w.Code, w.Body.String())
	}
}

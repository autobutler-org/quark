package v0_admin_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	v0_admin "github.com/autobutler-org/quark/internal/server/api/v0/admin"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/repairutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/updateutil"

	"github.com/gin-gonic/gin"
)

const repairableUnit = "[Service]\nExecStartPre=-+/opt/quark/bin/quark install --system-only\nExecStart=/opt/quark/bin/quark serve\n"

// countExits makes a scheduled restart count on the returned counter instead
// of exiting the test, and clears the in-progress guard when the test ends.
func countExits(t *testing.T) *atomic.Int32 {
	t.Helper()
	exits := &atomic.Int32{}
	t.Cleanup(updateutil.SetRestartExitForTest(func(int) { exits.Add(1) }))
	return exits
}

// waitForExits fails the test unless the counter reaches want in time.
func waitForExits(t *testing.T, exits *atomic.Int32, want int32) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for exits.Load() != want {
		if time.Now().After(deadline) {
			t.Fatalf("exits = %d, want %d", exits.Load(), want)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// holdUpdateGuard claims the in-progress guard the way an update does, as if
// one were installed and waiting to restart.
func holdUpdateGuard(t *testing.T) {
	t.Helper()
	t.Cleanup(updateutil.SetApplyUpdateForTest(func(*updateutil.UpdateSource, string) error { return nil }))
	if err := updateutil.ApplyUpdate(nil, "v0.0.1"); err != nil {
		t.Fatal(err)
	}
}

// assertConflict fails the test unless w is a 409 carrying an error.
func assertConflict(t *testing.T, w *httptest.ResponseRecorder) {
	t.Helper()
	if w.Code != http.StatusConflict {
		t.Fatalf("status %d, want 409: %s", w.Code, w.Body)
	}
	var body map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body["error"] == "" {
		t.Errorf("409 body = %s, want an error", w.Body)
	}
}

// newAdminEngine is the admin router over deps.
func newAdminEngine(deps deputil.Dependencies) *gin.Engine {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_admin.NewRouter())
	return engine
}

// newRepairEngine is the admin router over a fake host: service says whether
// this is the installed service and unit is the installed unit's content. A
// repair goes through the real updateutil.ScheduleRestart, and every exit it
// performs lands on the returned counter instead of ending the test.
func newRepairEngine(t *testing.T, service repairutil.Reason, unit string) (*gin.Engine, *atomic.Int32) {
	t.Helper()
	unitPath := filepath.Join(t.TempDir(), "quark.service")
	if err := os.WriteFile(unitPath, []byte(unit), 0o644); err != nil {
		t.Fatal(err)
	}
	exits := countExits(t)
	deps := deputil.NewDependencies().WithRepairSystem(repairutil.System{
		Service:  func() repairutil.Reason { return service },
		UnitPath: unitPath,
		Restart:  updateutil.ScheduleRestart,
	})
	return newAdminEngine(deps), exits
}

func serveRepair(engine *gin.Engine, method string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(method, "/api/v0/admin/repair", nil))
	return w
}

func TestGetRepairStatus(t *testing.T) {
	cases := []struct {
		name    string
		service repairutil.Reason
		unit    string
		want    string
	}{
		{"available", repairutil.ReasonNone, repairableUnit, ""},
		{"not Linux", repairutil.ReasonUnsupportedOS, repairableUnit, "unsupported_os"},
		{"not the service", repairutil.ReasonNotService, repairableUnit, "not_service"},
		{"unit before #2120", repairutil.ReasonNone, "[Service]\nExecStart=/opt/quark/bin/quark serve\n", "unit_outdated"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			engine, _ := newRepairEngine(t, tc.service, tc.unit)
			w := serveRepair(engine, http.MethodGet)
			if w.Code != http.StatusOK {
				t.Fatalf("status %d: %s", w.Code, w.Body)
			}
			var body map[string]any
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body["reason"] != tc.want || body["available"] != (tc.want == "") {
				t.Errorf("body = %v, want reason %q", body, tc.want)
			}
		})
	}
}

func TestRepairInstallationRestarts(t *testing.T) {
	engine, exits := newRepairEngine(t, repairutil.ReasonNone, repairableUnit)
	if w := serveRepair(engine, http.MethodPost); w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	waitForExits(t, exits, 1)
}

func TestRepairInstallationConflictsWhenUnavailable(t *testing.T) {
	engine, exits := newRepairEngine(t, repairutil.ReasonNotService, repairableUnit)
	assertConflict(t, serveRepair(engine, http.MethodPost))
	if exits.Load() != 0 {
		t.Error("restarted although unavailable")
	}
}

// A repair is a restart, so it is refused while an update holds the guard
// rather than exiting in the middle of the install (#4019).
func TestRepairInstallationConflictsDuringUpdate(t *testing.T) {
	engine, exits := newRepairEngine(t, repairutil.ReasonNone, repairableUnit)
	holdUpdateGuard(t)
	assertConflict(t, serveRepair(engine, http.MethodPost))
	if exits.Load() != 0 {
		t.Error("a repair restarted while an update was in progress")
	}
}

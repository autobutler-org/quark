package v0_admin_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	v0_admin "github.com/autobutler-org/quark/internal/server/api/v0/admin"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/repairutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

const repairableUnit = "[Service]\nExecStartPre=-+/opt/quark/bin/quark install --system-only\nExecStart=/opt/quark/bin/quark serve\n"

// newRepairEngine is the admin router over a fake host: service says whether
// this is the installed service, unit is the installed unit's content, and
// every restart lands on the returned channel instead of exiting the test.
func newRepairEngine(t *testing.T, service repairutil.Reason, unit string) (*gin.Engine, <-chan struct{}) {
	t.Helper()
	unitPath := filepath.Join(t.TempDir(), "quark.service")
	if err := os.WriteFile(unitPath, []byte(unit), 0o644); err != nil {
		t.Fatal(err)
	}
	restarts := make(chan struct{}, 1)
	deps := deputil.NewDependencies().WithRepairSystem(repairutil.System{
		Service:  func() repairutil.Reason { return service },
		UnitPath: unitPath,
		Restart:  func() { restarts <- struct{}{} },
	})
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_admin.NewRouter())
	return engine, restarts
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
	engine, restarts := newRepairEngine(t, repairutil.ReasonNone, repairableUnit)
	if w := serveRepair(engine, http.MethodPost); w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	select {
	case <-restarts:
	case <-time.After(5 * time.Second):
		t.Fatal("repair did not restart")
	}
}

func TestRepairInstallationConflictsWhenUnavailable(t *testing.T) {
	engine, restarts := newRepairEngine(t, repairutil.ReasonNotService, repairableUnit)
	w := serveRepair(engine, http.MethodPost)
	if w.Code != http.StatusConflict {
		t.Fatalf("status %d, want 409: %s", w.Code, w.Body)
	}
	var body map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body["error"] == "" {
		t.Errorf("409 body = %s, want an error", w.Body)
	}
	select {
	case <-restarts:
		t.Error("restarted although unavailable")
	default:
	}
}

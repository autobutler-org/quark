package v0_admin_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/restartutil"

	"github.com/gin-gonic/gin"
)

func serveRestart(engine *gin.Engine, method string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(method, "/api/v0/admin/restart", nil))
	return w
}

func TestGetRestartStatus(t *testing.T) {
	cases := []struct {
		name  string
		value string
		want  string
	}{
		{"supervised", "1", ""},
		{"not supervised", "", "not_supervised"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv(restartutil.SupervisedEnv, tc.value)
			w := serveRestart(newAdminEngine(deputil.NewDependencies()), http.MethodGet)
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

func TestRestartQuarkRestartsOnce(t *testing.T) {
	t.Setenv(restartutil.SupervisedEnv, "1")
	exits := countExits(t)
	engine := newAdminEngine(deputil.NewDependencies())
	if w := serveRestart(engine, http.MethodPost); w.Code != http.StatusOK {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	waitForExits(t, exits, 1)
	// The process is still serving until it exits into the restart.
	assertConflict(t, serveRestart(engine, http.MethodPost))
	if exits.Load() != 1 {
		t.Errorf("exits = %d after a second request, want 1", exits.Load())
	}
}

func TestRestartQuarkConflictsWhenUnsupervised(t *testing.T) {
	t.Setenv(restartutil.SupervisedEnv, "")
	exits := countExits(t)
	assertConflict(t, serveRestart(newAdminEngine(deputil.NewDependencies()), http.MethodPost))
	if exits.Load() != 0 {
		t.Error("restarted although unsupervised")
	}
}

func TestRestartQuarkConflictsDuringUpdate(t *testing.T) {
	t.Setenv(restartutil.SupervisedEnv, "1")
	exits := countExits(t)
	holdUpdateGuard(t)
	assertConflict(t, serveRestart(newAdminEngine(deputil.NewDependencies()), http.MethodPost))
	if exits.Load() != 0 {
		t.Error("restarted while an update was in progress")
	}
}

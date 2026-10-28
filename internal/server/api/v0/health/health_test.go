package v0_health_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_health "github.com/autobutler-org/quark/internal/server/api/v0/health"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/healthutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// newHealthEngine creates a gin engine with the health routes registered.
// Uses healthutil.Register() which attaches to the default no-op OTel provider —
// safe for unit tests and avoids real process monitoring.
func newHealthEngine(t *testing.T, middleware ...gin.HandlerFunc) *gin.Engine {
	t.Helper()
	collector, err := healthutil.Register()
	if err != nil {
		t.Fatalf("healthutil.Register() failed: %v", err)
	}
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(middleware...)
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_health.NewRouter(collector))
	return engine
}

func doGet(engine *gin.Engine, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestGetHealth_Returns200 verifies that GET /health returns 200 with a valid JSON body.
func TestGetHealth_Returns200(t *testing.T) {
	engine := newHealthEngine(t)
	w := doGet(engine, "/api/v0/health")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

// TestGetHealth_BodyShape verifies the response contains the expected top-level fields.
func TestGetHealth_BodyShape(t *testing.T) {
	engine := newHealthEngine(t)
	w := doGet(engine, "/api/v0/health")

	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to parse JSON body: %v", err)
	}

	requiredFields := []string{
		"healthy", "alerts", "cpuPercent", "cpuCorePercents",
		"cpuCoreCount", "memPercent", "memUsedBytes", "memTotalBytes",
		"diskPercent", "diskUsedBytes", "diskTotalBytes",
		"temperatureCelsius", "hostname",
	}
	for _, field := range requiredFields {
		if _, ok := body[field]; !ok {
			t.Errorf("missing field %q in health response", field)
		}
	}
}

// TestGetHealth_AlertsIsArray verifies that the alerts field is always a JSON array,
// never null — important for Flutter client parsing.
func TestGetHealth_AlertsIsArray(t *testing.T) {
	engine := newHealthEngine(t)
	w := doGet(engine, "/api/v0/health")

	var body struct {
		Alerts []any `json:"alerts"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to parse JSON body: %v", err)
	}
	if body.Alerts == nil {
		t.Error("alerts must be a JSON array (not null) — Flutter client expects []")
	}
}

// TestGetHealth_CPUCorePercentsIsArray verifies cpuCorePercents is always a JSON array.
func TestGetHealth_CPUCorePercentsIsArray(t *testing.T) {
	engine := newHealthEngine(t)
	w := doGet(engine, "/api/v0/health")

	var body struct {
		CPUCorePercents []float64 `json:"cpuCorePercents"`
		CPUCoreCount    int       `json:"cpuCoreCount"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to parse JSON body: %v", err)
	}
	if body.CPUCorePercents == nil {
		t.Error("cpuCorePercents must be a JSON array (not null)")
	}
	if len(body.CPUCorePercents) != body.CPUCoreCount {
		t.Errorf("cpuCoreCount=%d does not match len(cpuCorePercents)=%d",
			body.CPUCoreCount, len(body.CPUCorePercents))
	}
}

// TestGetHealth_HostnamePresent verifies that hostname is a non-empty string.
func TestGetHealth_HostnamePresent(t *testing.T) {
	engine := newHealthEngine(t)
	w := doGet(engine, "/api/v0/health")

	var body struct {
		Hostname string `json:"hostname"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to parse JSON body: %v", err)
	}
	if body.Hostname == "" {
		t.Error("expected non-empty hostname")
	}
}

// /health says when the database stops answering, and says nothing about it
// while it answers.
func TestGetHealth_ReportsTheDatabase(t *testing.T) {
	const alert = "The SQLite database is not answering"
	for _, tc := range []struct {
		name   string
		closed bool
	}{
		{name: "open"},
		{name: "closed", closed: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			database := dbtest.NewDB(t)
			if tc.closed {
				database.Db.Close()
			}
			deps := deputil.NewDependencies().WithDatabase(database)
			engine := newHealthEngine(t, func(c *gin.Context) {
				c = ctxutil.With(c, "deps", deps)
				c.Next()
			})

			var body struct {
				Healthy bool     `json:"healthy"`
				Alerts  []string `json:"alerts"`
			}
			if err := json.Unmarshal(doGet(engine, "/api/v0/health").Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if got := slices.Contains(body.Alerts, alert); got != tc.closed {
				t.Errorf("alerts %q, want the database alert: %v", body.Alerts, tc.closed)
			}
			// The host may raise alerts of its own, so only a closed database
			// decides healthy here.
			if tc.closed && body.Healthy {
				t.Error("healthy with the database closed")
			}
		})
	}
}

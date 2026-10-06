package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/featureflagutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// TestRequireFeatureEnabled checks a beta's route is reached while its flag
// is on and answers 404 once an admin turns the beta off.
func TestRequireFeatureEnabled(t *testing.T) {
	for key, path := range map[string]string{
		featureflagutil.Chat:     "/api/v0/chat/channels",
		featureflagutil.Calendar: "/api/v0/calendar/events",
		featureflagutil.Slides:   "/api/v0/files/export/pptx",
	} {
		t.Run(key, func(t *testing.T) {
			settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
			gin.SetMode(gin.TestMode)
			engine := gin.New()
			engine.Group("", middleware.RequireFeatureEnabled(key)).GET(path, func(c *gin.Context) {
				c.Status(http.StatusOK)
			})
			get := func() int {
				w := httptest.NewRecorder()
				engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
				return w.Code
			}

			if code := get(); code != http.StatusOK {
				t.Errorf("%s on: GET = %d, want 200", key, code)
			}
			if _, err := featureflagutil.SetFlag(featureflagutil.SetFlagParams{Key: key, Enabled: false}); err != nil {
				t.Fatal(err)
			}
			if code := get(); code != http.StatusNotFound {
				t.Errorf("%s off: GET = %d, want 404", key, code)
			}
		})
	}
}

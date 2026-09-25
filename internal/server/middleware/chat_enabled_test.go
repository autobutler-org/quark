package middleware_test

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// TestRequireChatEnabled checks a chat route is reached while chat is on and
// answers 404 once an admin turns the beta off.
func TestRequireChatEnabled(t *testing.T) {
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Group("", middleware.RequireChatEnabled()).GET("/api/v0/chat/channels", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	get := func() int {
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/chat/channels", nil))
		return w.Code
	}

	if code := get(); code != http.StatusOK {
		t.Errorf("chat on: GET = %d, want 200", code)
	}
	if err := settingsutil.SetChatEnabled(false); err != nil {
		t.Fatal(err)
	}
	if code := get(); code != http.StatusNotFound {
		t.Errorf("chat off: GET = %d, want 404", code)
	}
}

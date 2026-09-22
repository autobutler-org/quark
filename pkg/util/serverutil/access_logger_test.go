package serverutil

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRedactQuery(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"no query", "/api/v0/files", "/api/v0/files"},
		{"token alone", "/api/v0/videos/stream?token=hunter2", "/api/v0/videos/stream?token=REDACTED"},
		{
			"token among others keeps their order and encoding",
			"/api/v0/files/download?filePath=a%20b.mp4&token=hunter2&serial=X1",
			"/api/v0/files/download?filePath=a%20b.mp4&token=REDACTED&serial=X1",
		},
		{"every copy of the token", "/x?token=a&token=b", "/x?token=REDACTED&token=REDACTED"},
		{"an empty token", "/x?token=", "/x?token=REDACTED"},
		{"a bare token key", "/x?token", "/x?token=REDACTED"},
		{"a percent-encoded key", "/x?%74%6F%6B%65%6E=hunter2", "/x?%74%6F%6B%65%6E=REDACTED"},
		{"a parameter that only starts with token", "/x?tokens=1", "/x?tokens=1"},
		{"a token value on another key", "/x?q=token", "/x?q=token"},
		{
			"a download token",
			"/api/v0/files/download?filePath=big&downloadToken=I2cAyRit_x",
			"/api/v0/files/download?filePath=big&downloadToken=REDACTED",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := redactQuery(tc.in); got != tc.want {
				t.Errorf("redactQuery(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

// TestRecoveryRedactsTheRequestLine verifies a recovered panic's log, which
// gin writes with a dump of the request, carries no credential from the URL.
func TestRecoveryRedactsTheRequestLine(t *testing.T) {
	gin.SetMode(gin.DebugMode)
	t.Cleanup(func() { gin.SetMode(gin.TestMode) })
	var out bytes.Buffer
	engine := gin.New()
	engine.Use(Recovery(&out))
	engine.GET("/api/v0/files/download", func(*gin.Context) { panic("boom") })

	engine.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet,
		"/api/v0/files/download?filePath=big&downloadToken=secret1&token=secret2", nil))

	logged := out.String()
	if !strings.Contains(logged, "boom") {
		t.Fatalf("panic not logged: %q", logged)
	}
	if strings.Contains(logged, "secret") {
		t.Errorf("credential in the recovery log: %q", logged)
	}
	if !strings.Contains(logged, "/api/v0/files/download?filePath=big&downloadToken=REDACTED&token=REDACTED HTTP/1.1") {
		t.Errorf("request line not redacted in place: %q", logged)
	}
}

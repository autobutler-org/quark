package v0_auth

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

// TestIsTLS_ForwardedProtoNeedsTrustedPeer verifies that X-Forwarded-Proto is
// honored only from a trusted proxy (loopback by default), so any other
// client cannot claim the connection was HTTPS.
func TestIsTLS_ForwardedProtoNeedsTrustedPeer(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "")
	gin.SetMode(gin.TestMode)
	cases := []struct {
		remoteAddr string
		want       bool
	}{
		{"127.0.0.1:40000", true},
		{"[::1]:40000", true},
		{"203.0.113.7:40000", false},
	}
	for _, tc := range cases {
		c, _ := gin.CreateTestContext(httptest.NewRecorder())
		c.Request = httptest.NewRequest(http.MethodPost, "/api/v0/auth/login", nil)
		c.Request.RemoteAddr = tc.remoteAddr
		c.Request.Header.Set("X-Forwarded-Proto", "https")
		if got := isTLS(c); got != tc.want {
			t.Errorf("isTLS from %s with X-Forwarded-Proto: https = %v; want %v", tc.remoteAddr, got, tc.want)
		}
	}
}

package remoteutil

import (
	"crypto/tls"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// newProxy builds the reverse proxy that carries tailnet traffic to the quark
// serving on target.
func newProxy(target *url.URL, localTLS bool) *httputil.ReverseProxy {
	rp := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(target)
			r.Out.Host = target.Host
			// Rewrite strips inbound forwarding headers; without this every
			// tailnet peer reaches the quark as 127.0.0.1 and they all share
			// one login rate-limit bucket.
			r.SetXForwarded()
		},
	}
	if localTLS {
		// The quark presents its own self-signed cert, and this hop is a
		// loopback connection to that same process — there is no third party to
		// authenticate, and no CA that could vouch for the cert.
		rp.Transport = &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
	}
	return rp
}

func controlURL() string {
	u := os.Getenv("QUARK_HEADSCALE_URL")
	if u == "" {
		u = defaultControlURL
	}
	if strings.HasPrefix(u, "http://") {
		log.Printf("[remote] WARNING: Headscale control URL is using HTTP (%s). Auth keys will be sent in plaintext. Use HTTPS in production.", u)
	}
	return u
}

// stateDir returns the path where tsnet should persist its state. On Linux it
// prefers the system service directory if the parent exists; otherwise it falls
// back to the user's home config directory. Directory creation is left to the
// caller (Start).
func stateDir() string {
	if runtime.GOOS == "linux" {
		svcDir := "/var/lib/quark/tsnet"
		if _, err := os.Stat(filepath.Dir(svcDir)); err == nil {
			return svcDir
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		home = os.TempDir()
	}
	return filepath.Join(home, ".config", "quark", "tsnet")
}

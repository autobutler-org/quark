package remoteutil

import (
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
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

// connectionFromStatus maps a tsnet status to whether the node is on the
// tailnet and, if it is, the URL peers reach it at. tsnet.Server.Start returns
// before the node authenticates, so only BackendState "Running" counts —
// "Starting", "NeedsLogin" and the rest are not connected, whatever IP the
// node may already hold.
//
// "NeedsLogin" is also a failure: tailscale's LocalBackend enters it only when
// login cannot continue without a human (#1876). For a node given a pre-auth
// key, that means control rejected the key or it expired.
func connectionFromStatus(st *ipnstate.Status) StatusResult {
	if st == nil {
		return StatusResult{}
	}
	switch st.BackendState {
	case ipn.Running.String():
		if len(st.TailscaleIPs) == 0 {
			return StatusResult{Connected: true}
		}
		return StatusResult{Connected: true, RemoteURL: fmt.Sprintf("http://%s:80", st.TailscaleIPs[0])}
	case ipn.NeedsLogin.String():
		return StatusResult{Error: errKeyRejected}
	default:
		return StatusResult{}
	}
}

// nodeHostname is the tsnet hostname for the Quark with deviceID:
// "quark-" and the first eight hex digits of the ID. It is stable across
// restarts and distinct per device, so Headscale and MagicDNS can tell one
// Quark from another (#2358, #1880) instead of suffixing a shared "quark".
func nodeHostname(deviceID string) string {
	return "quark-" + deviceID[:min(8, len(deviceID))]
}

// newPairDeviceID is a random ID for one paired device, which the
// provisioning service logs and rate-limits the key against.
func newPairDeviceID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate device id: %w", err)
	}
	return "pair-" + hex.EncodeToString(b), nil
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

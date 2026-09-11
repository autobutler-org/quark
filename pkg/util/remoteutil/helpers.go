package remoteutil

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
)

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

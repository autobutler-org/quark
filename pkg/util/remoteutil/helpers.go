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
func connectionFromStatus(st *ipnstate.Status) (bool, string) {
	if st == nil || st.BackendState != ipn.Running.String() {
		return false, ""
	}
	if len(st.TailscaleIPs) == 0 {
		return true, ""
	}
	return true, fmt.Sprintf("http://%s:80", st.TailscaleIPs[0])
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

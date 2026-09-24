package provisionutil

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"strings"
)

// provisioningURL is QUARK_PROVISIONING_URL, or the production endpoint.
func provisioningURL() string {
	if u := os.Getenv("QUARK_PROVISIONING_URL"); u != "" {
		return u
	}
	return defaultProvisioningURL
}

// defaultDeviceID is the sha256 of the hostname and machine-id. It is stable
// across restarts, so the service's per-device rate limit sees one device.
// Hosts without a machine-id (macOS, some containers) hash the hostname alone.
func defaultDeviceID() string {
	hostname, _ := os.Hostname()
	sum := sha256.Sum256([]byte(hostname + ":" + machineID()))
	return hex.EncodeToString(sum[:])
}

func machineID() string {
	for _, path := range []string{"/etc/machine-id", "/var/lib/dbus/machine-id"} {
		// A 33-byte system file, not user content.
		if data, err := os.ReadFile(path); err == nil {
			return strings.TrimSpace(string(data))
		}
	}
	return ""
}

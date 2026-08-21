// Package pluginutil implements the AutoButler plugin subprocess host.
//
// Plugins are independent binaries that implement the AutoButler plugin
// protocol:
//
//  1. The host spawns the binary with --addr 127.0.0.1:0 (or the env var
//     AUTOBUTLER_PLUGIN_ADDR) and injects a scoped VFS JWT via
//     AUTOBUTLER_VFS_TOKEN + AUTOBUTLER_VFS_BASE_URL.
//
//  2. The plugin writes "READY addr=<host:port>\n" to stdout once it is
//     listening. The host has 10 seconds to receive this line before it
//     kills the process and logs an error.
//
//  3. The host calls GET /manifest on the plugin and merges the result into
//     the global plugin listing exposed at GET /api/v1/plugins.
//
//  4. The host proxies /api/v1/plugins/<id>/* requests to the plugin's HTTP
//     server.
//
//  5. The host polls GET /health on each plugin every 30 seconds. Failed
//     health checks trigger an exponential-backoff restart.
package pluginutil

import (
	"encoding/json"
	"os"
)

// PluginEntry is one entry in plugins.json — the on-disk plugin registry.
type PluginEntry struct {
	// ID is the unique plugin identifier (URL-safe, lower-kebab-case).
	ID string `json:"id"`
	// BinaryPath is the absolute path to the plugin executable.
	BinaryPath string `json:"binaryPath"`
	// SHA256 is the expected hex SHA-256 of the binary for integrity verification.
	SHA256 string `json:"sha256"`
	// Enabled controls whether the plugin is started on boot.
	Enabled bool `json:"enabled"`
	// NamespacesRead lists VFS namespaces the plugin may read.
	NamespacesRead []string `json:"namespacesRead,omitempty"`
	// NamespacesWrite lists VFS namespaces the plugin may write.
	NamespacesWrite []string `json:"namespacesWrite,omitempty"`
}

// PluginManifest is the response from GET /manifest on a running plugin.
type PluginManifest struct {
	// ID must match the PluginEntry.ID — the plugin asserts its own identity.
	ID string `json:"id"`
	// Name is a human-readable display name.
	Name string `json:"name"`
	// Version is the plugin's semver string.
	Version string `json:"version"`
	// Description is a short one-sentence summary.
	Description string `json:"description"`
}

// LoadPluginRegistry reads and parses the plugins.json registry file.
// Returns an empty slice (not an error) when the file does not exist.
func LoadPluginRegistry(path string) ([]PluginEntry, error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var entries []PluginEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		return nil, err
	}
	return entries, nil
}

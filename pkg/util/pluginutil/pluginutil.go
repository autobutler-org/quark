package pluginutil

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/autobutler-org/autobutler/pkg/util/storageutil"
)

const manifestFileName = "manifest.json"

// NavItem describes a plugin's contribution to the sidebar navigation.
type NavItem struct {
	Label string `json:"label"`
	Icon  string `json:"icon"`
	Route string `json:"route"`
}

// Contributes describes what UI slots the plugin fills.
type Contributes struct {
	NavItem       *NavItem `json:"navItem,omitempty"`
	SettingsPanel bool     `json:"settingsPanel,omitempty"`
}

// Manifest is the on-disk description of a plugin.
type Manifest struct {
	ID             string      `json:"id"`
	Name           string      `json:"name"`
	Version        string      `json:"version"`
	Description    string      `json:"description"`
	Author         string      `json:"author"`
	Enabled        bool        `json:"enabled"`
	Contributes    Contributes `json:"contributes"`
	MinAppVersion  string      `json:"minAppVersion,omitempty"`
}

// GetPluginsDir returns (and creates) <dataDir>/plugins.
func GetPluginsDir() (string, error) {
	dir := filepath.Join(storageutil.GetDataDir(), "plugins")
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create plugins directory: %w", err)
	}
	return dir, nil
}

// MarketplaceEntry describes a plugin available for installation.  For now
// this is a superset of Manifest with an extra Available flag so the frontend
// can distinguish installed vs not-installed in a single list.
type MarketplaceEntry struct {
	Manifest
	Installed bool `json:"installed"`
}

// builtinCatalog is the hardcoded marketplace catalog.  Replace / extend this
// with a remote fetch once a real marketplace backend exists.
var builtinCatalog = []Manifest{
	{
		ID:          "hello",
		Name:        "Hello World",
		Version:     "1.0.0",
		Description: "A simple hello world plugin to demonstrate the plugin system.",
		Author:      "autobutler-org",
		Enabled:     true,
		Contributes: Contributes{
			NavItem: &NavItem{
				Label: "Hello",
				Icon:  "waving_hand",
				Route: "/plugins/hello",
			},
		},
	},
}

// ListMarketplace returns all available plugins, annotated with whether they
// are already installed on this device.
func ListMarketplace() ([]MarketplaceEntry, error) {
	installed, err := ListPlugins()
	if err != nil {
		return nil, err
	}
	installedIDs := make(map[string]bool, len(installed))
	for _, p := range installed {
		installedIDs[p.ID] = true
	}
	entries := make([]MarketplaceEntry, 0, len(builtinCatalog))
	for _, m := range builtinCatalog {
		entries = append(entries, MarketplaceEntry{
			Manifest:  m,
			Installed: installedIDs[m.ID],
		})
	}
	return entries, nil
}

// InstallPlugin writes the manifest for the given plugin ID to disk.
// Returns an error if the plugin is not in the catalog.
func InstallPlugin(id string) error {
	var target *Manifest
	for i := range builtinCatalog {
		if builtinCatalog[i].ID == id {
			target = &builtinCatalog[i]
			break
		}
	}
	if target == nil {
		return fmt.Errorf("plugin %q not found in marketplace", id)
	}
	pluginsDir, err := GetPluginsDir()
	if err != nil {
		return err
	}
	pluginDir := filepath.Join(pluginsDir, id)
	if err := os.MkdirAll(pluginDir, 0755); err != nil {
		return fmt.Errorf("failed to create plugin directory: %w", err)
	}
	data, err := json.MarshalIndent(target, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal plugin manifest: %w", err)
	}
	return os.WriteFile(filepath.Join(pluginDir, manifestFileName), data, 0644)
}

// UninstallPlugin removes the plugin directory for the given ID.
func UninstallPlugin(id string) error {
	pluginsDir, err := GetPluginsDir()
	if err != nil {
		return err
	}
	pluginDir := filepath.Join(pluginsDir, id)
	if _, err := os.Stat(pluginDir); os.IsNotExist(err) {
		return fmt.Errorf("plugin %q is not installed", id)
	}
	return os.RemoveAll(pluginDir)
}

// ListPlugins scans <dataDir>/plugins/ and returns all valid, enabled manifests.
func ListPlugins() ([]Manifest, error) {
	pluginsDir, err := GetPluginsDir()
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(pluginsDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read plugins directory: %w", err)
	}
	var plugins []Manifest
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		manifestPath := filepath.Join(pluginsDir, entry.Name(), manifestFileName)
		data, err := os.ReadFile(manifestPath)
		if err != nil {
			// Skip directories without a manifest.
			continue
		}
		var m Manifest
		if err := json.Unmarshal(data, &m); err != nil {
			// Skip malformed manifests.
			continue
		}
		plugins = append(plugins, m)
	}
	return plugins, nil
}

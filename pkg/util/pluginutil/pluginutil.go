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

// EnsureHelloPlugin writes the bundled hello plugin manifest if it doesn't
// already exist on disk.
func EnsureHelloPlugin() error {
	pluginsDir, err := GetPluginsDir()
	if err != nil {
		return err
	}
	helloDir := filepath.Join(pluginsDir, "hello")
	if err := os.MkdirAll(helloDir, 0755); err != nil {
		return fmt.Errorf("failed to create hello plugin directory: %w", err)
	}
	manifestPath := filepath.Join(helloDir, manifestFileName)
	if _, err := os.Stat(manifestPath); err == nil {
		// Already exists — don't overwrite user edits.
		return nil
	}
	m := Manifest{
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
	}
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal hello plugin manifest: %w", err)
	}
	return os.WriteFile(manifestPath, data, 0644)
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

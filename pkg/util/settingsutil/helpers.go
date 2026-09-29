package settingsutil

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func settingsPath() string {
	if pathOverride != "" {
		return pathOverride
	}
	dataDir := storageutil.GetDataDir()
	return filepath.Join(dataDir, settingsFileName)
}

// migrations is the ordered history of settings.json. A file's
// settingsVersion counts how many it has been through; append only, never
// reorder or delete, or a file already past an entry would skip the next one.
var migrations []migration

// migrate runs the migrations data has not been through and, when it ran
// any, writes the result back to path. A file from a newer build, with a
// higher version than this one knows, is left alone.
func migrate(path string, data []byte) ([]byte, error) {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("failed to parse settings file: %w", err)
	}
	if raw == nil {
		raw = map[string]json.RawMessage{}
	}
	version := 0
	if v, ok := raw["settingsVersion"]; ok {
		if err := json.Unmarshal(v, &version); err != nil {
			return nil, fmt.Errorf("failed to parse settingsVersion: %w", err)
		}
	}
	if version >= len(migrations) {
		return data, nil
	}
	for i := version; i < len(migrations); i++ {
		if err := migrations[i](raw); err != nil {
			return nil, fmt.Errorf("settings migration %d: %w", i+1, err)
		}
	}
	raw["settingsVersion"] = json.RawMessage(strconv.Itoa(len(migrations)))
	out, err := json.MarshalIndent(raw, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to marshal migrated settings: %w", err)
	}
	if err := os.WriteFile(path, out, 0600); err != nil {
		return nil, fmt.Errorf("failed to write migrated settings: %w", err)
	}
	return out, nil
}

package settingsutil

import (
	"bytes"
	"encoding/json"
	"fmt"
	"maps"
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
var migrations = []migration{
	moveChatEnabledToFeatureFlags, // 1: #2542
}

// snapshotOf copies s, map included, so neither the cache nor a caller can
// change the other's settings. The copy's FeatureFlags is never nil.
func snapshotOf(s *Settings) *Settings {
	snapshot := *s
	snapshot.FeatureFlags = maps.Clone(s.FeatureFlags)
	if snapshot.FeatureFlags == nil {
		snapshot.FeatureFlags = map[string]bool{}
	}
	return &snapshot
}

// moveChatEnabledToFeatureFlags moves the chat switch #2421 stored as
// chatEnabled into featureFlags.chat, where the flag registry reads it, and
// drops chatEnabled. A file with no chatEnabled keeps chat's default.
func moveChatEnabledToFeatureFlags(raw map[string]json.RawMessage) error {
	value, ok := raw["chatEnabled"]
	if !ok {
		return nil
	}
	delete(raw, "chatEnabled")
	var enabled *bool
	if err := json.Unmarshal(value, &enabled); err != nil {
		return fmt.Errorf("chatEnabled: %w", err)
	}
	if enabled == nil {
		return nil
	}
	return editFeatureFlags(raw, func(flags map[string]bool) {
		if _, set := flags["chat"]; !set {
			flags["chat"] = *enabled
		}
	})
}

// dropFeatureFlag is the migration that retires a flag: it removes key's
// persisted value, so a flag deleted from the registry leaves nothing behind.
func dropFeatureFlag(key string) migration {
	return func(raw map[string]json.RawMessage) error {
		return editFeatureFlags(raw, func(flags map[string]bool) { delete(flags, key) })
	}
}

// editFeatureFlags applies edit to the featureFlags object in raw, removing
// the object when it ends up empty.
func editFeatureFlags(raw map[string]json.RawMessage, edit func(map[string]bool)) error {
	flags := map[string]bool{}
	if value, ok := raw["featureFlags"]; ok {
		if err := json.Unmarshal(value, &flags); err != nil {
			return fmt.Errorf("featureFlags: %w", err)
		}
		if flags == nil {
			flags = map[string]bool{}
		}
	}
	edit(flags)
	if len(flags) == 0 {
		delete(raw, "featureFlags")
		return nil
	}
	value, err := json.Marshal(flags)
	if err != nil {
		return err
	}
	raw["featureFlags"] = value
	return nil
}

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
	if err := storageutil.WriteFileAtomicPerm(path, bytes.NewReader(out), 0600); err != nil {
		return nil, fmt.Errorf("failed to write migrated settings: %w", err)
	}
	return out, nil
}

package settingsutil

import (
	"context"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// authSaltSecretKey is the settings key of the salt secret.
const authSaltSecretKey = "authSaltSecret"

var (
	// store is the database Bind gave the package. It is a handle, not state:
	// every instance's points at the same rows.
	store        atomic.Pointer[db.Queries]
	testDB       *sql.DB // opened by ResetForTesting only
	pathOverride string  // set by ResetForTesting only
)

// bound returns the database the settings live in, or ErrNotBound.
func bound() (*db.Queries, error) {
	queries := store.Load()
	if queries == nil {
		return nil, ErrNotBound
	}
	return queries, nil
}

// set stores one setting as its JSON, leaving every other row alone.
func set(key string, value any) error {
	queries, err := bound()
	if err != nil {
		return err
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("failed to marshal setting %s: %w", key, err)
	}
	if err := queries.SetSetting(context.Background(), db.SetSettingParams{Key: key, Value: string(encoded)}); err != nil {
		return fmt.Errorf("failed to write setting %s: %w", key, err)
	}
	return nil
}

// decodeRaw fills s from the settings rows: raw by key, and flags by flag
// name, which Settings holds as one featureFlags object.
func decodeRaw(raw, flags map[string]json.RawMessage, s *Settings) error {
	if len(flags) > 0 {
		value, err := json.Marshal(flags)
		if err != nil {
			return err
		}
		raw["featureFlags"] = value
	}
	data, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, s)
}

// storedSaltSecret returns the salt secret in the database, or nil when there
// is none or what is stored is not one.
func storedSaltSecret(ctx context.Context, queries *db.Queries) ([]byte, error) {
	value, err := queries.GetSetting(ctx, authSaltSecretKey)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read the salt secret: %w", err)
	}
	var encoded string
	if json.Unmarshal([]byte(value), &encoded) != nil {
		return nil, nil
	}
	secret, err := hex.DecodeString(encoded)
	if err != nil || len(secret) != authSaltSecretSize {
		return nil, nil
	}
	return secret, nil
}

// importFile moves the settings.json an older build kept at path into the
// database, then renames it to path.imported so it is read once and nothing
// is deleted. It first runs the file migrations the file has not been
// through. Only the settings Settings knows are brought in, each as its own
// row, and a setting the database already has is kept: a second instance
// importing its own copy does not overwrite what the first one stored. No
// file means nothing to do.
func importFile(path string) error {
	queries, err := bound()
	if err != nil {
		return err
	}
	// Whole in memory is fine: a settings file is a few short values we wrote.
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed to read settings file: %w", err)
	}
	data, err = migrate(data)
	if err != nil {
		return err
	}
	s := &Settings{}
	if err := json.Unmarshal(data, s); err != nil {
		return fmt.Errorf("failed to parse settings file: %w", err)
	}
	// Through Settings and back, so its omitempty tags decide what has a
	// value and a key it does not know is dropped.
	known, err := json.Marshal(s)
	if err != nil {
		return fmt.Errorf("failed to marshal settings: %w", err)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(known, &raw); err != nil {
		return fmt.Errorf("failed to marshal settings: %w", err)
	}
	delete(raw, "settingsVersion")
	delete(raw, "featureFlags")
	for flag, enabled := range s.FeatureFlags {
		raw[featureFlagKeyPrefix+flag] = json.RawMessage(fmt.Sprint(enabled))
	}
	ctx := context.Background()
	for key, value := range raw {
		if err := queries.AddSetting(ctx, db.AddSettingParams{Key: key, Value: string(value)}); err != nil {
			return fmt.Errorf("failed to import setting %s: %w", key, err)
		}
	}
	if err := os.Rename(path, path+".imported"); err != nil {
		return fmt.Errorf("failed to set the imported settings file aside: %w", err)
	}
	return nil
}

func settingsPath() string {
	if pathOverride != "" {
		return pathOverride
	}
	dataDir := storageutil.GetDataDir()
	return filepath.Join(dataDir, settingsFileName)
}

// migrations is the ordered history of settings.json. A file's
// settingsVersion counts how many it has been through, and importFile runs
// the rest. The list is closed: the settings are rows now, so a change to
// them is a migration in internal/db/migrations.
var migrations = []migration{
	moveChatEnabledToFeatureFlags, // 1: #2542
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

// migrate runs the file migrations data has not been through and returns
// the result. A file from a newer build, with a higher version than this one
// knows, is returned as it is.
func migrate(data []byte) ([]byte, error) {
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
	out, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal migrated settings: %w", err)
	}
	return out, nil
}

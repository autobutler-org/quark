package settingsutil

import (
	"encoding/json"
	"testing"
)

// DropFeatureFlagForTesting is dropFeatureFlag, for a test that retires a flag
// the real registry still has.
func DropFeatureFlagForTesting(key string) func(raw map[string]json.RawMessage) error {
	return dropFeatureFlag(key)
}

// SetMigrationsForTesting replaces the migration list for one test, so the
// mechanism can be exercised with steps that are not part of the real history.
func SetMigrationsForTesting(t *testing.T, steps ...func(raw map[string]json.RawMessage) error) {
	t.Helper()
	saved := migrations
	t.Cleanup(func() { migrations = saved })
	migrations = nil
	for _, step := range steps {
		migrations = append(migrations, step)
	}
}

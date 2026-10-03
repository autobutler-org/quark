// Package settingsutil reads and writes the Quark's settings, which live in settings.json in the data directory
// rather than in the database.
package settingsutil

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

const settingsFileName = "settings.json"

// authSaltSecretSize is the salt secret's length in bytes.
const authSaltSecretSize = 32

// Settings holds application-level user-configurable settings.
type Settings struct {
	// SettingsVersion is how many of the package's migrations the file has
	// been through. Load runs the rest; Save stamps the current count.
	SettingsVersion int  `json:"settingsVersion"`
	AutoUpdate      bool `json:"autoUpdate"`
	// RemoteAccessEnabled is the user's choice. The node's credential is its
	// tsnet state dir, not a key kept here (#1876): files written before then
	// still carry a remoteAccessAuthKey, which parsing ignores and the next
	// Save drops.
	RemoteAccessEnabled bool `json:"remoteAccessEnabled"`
	// RemoteAccessHousehold and RemoteAccessHouseholdToken are the Quark's
	// Headscale household and the token that authenticates pair requests for
	// it (#2358). They outlive Disable, so the next Enable rejoins the same
	// household. The file is written 0600.
	RemoteAccessHousehold      string `json:"remoteAccessHousehold,omitempty"`
	RemoteAccessHouseholdToken string `json:"remoteAccessHouseholdToken,omitempty"`
	DevMode                    bool   `json:"devMode"`
	ActiveBranch               string `json:"activeBranch,omitempty"`
	DeviceID                   string `json:"deviceId,omitempty"`
	// AccessRequestsEnabled is whether people may request an account from the
	// sign-in page (#1908). Nil means on: requests start on, and a file written
	// before the setting existed carries no value.
	AccessRequestsEnabled *bool `json:"accessRequestsEnabled,omitempty"`
	// FeatureFlags holds the beta switches an admin has set, by the key
	// featureflagutil registers them under (#2542). A missing key means the
	// registry's default. A retired flag's key is removed by a migration.
	FeatureFlags map[string]bool `json:"featureFlags,omitempty"`
	// AuthSaltSecret is the hex of the 32 random bytes that key the salt
	// /auth/salt answers with for an account that has none stored (#2430).
	// AuthSaltSecret makes it on first use and Save never drops it. The file
	// is written 0600.
	AuthSaltSecret string `json:"authSaltSecret,omitempty"`
}

var (
	// secretMu keeps two first calls of AuthSaltSecret from each making one.
	secretMu     sync.Mutex
	mu           sync.Mutex
	cached       *Settings
	pathOverride string // set by ResetForTesting only
)

// Load reads settings from disk (or returns defaults if not present),
// first bringing an older file up to date by running the migrations it has
// not been through and writing it back. The result is cached for the lifetime of the process.
// Returns a copy of the cached settings to prevent callers from mutating
// the shared state without holding the lock.
func Load() (*Settings, error) {
	mu.Lock()
	defer mu.Unlock()

	if cached != nil {
		return snapshotOf(cached), nil
	}

	path := settingsPath()

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		cached = &Settings{SettingsVersion: len(migrations)}
		return snapshotOf(cached), nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read settings file: %w", err)
	}

	data, err = migrate(path, data)
	if err != nil {
		return nil, err
	}

	s := &Settings{}
	if err := json.Unmarshal(data, s); err != nil {
		return nil, fmt.Errorf("failed to parse settings file: %w", err)
	}

	cached = s
	return snapshotOf(cached), nil
}

// Save writes settings to disk and updates the in-process cache.
// Stores a copy so the caller's pointer cannot mutate the cache.
func Save(s *Settings) error {
	mu.Lock()
	defer mu.Unlock()

	path := settingsPath()

	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return fmt.Errorf("failed to create settings directory: %w", err)
	}

	snapshot := snapshotOf(s)
	snapshot.SettingsVersion = len(migrations)
	// The salt secret is written once and never cleared. A caller holding
	// settings read before it existed would otherwise save it away, and the
	// next one made would not match the salts already handed out (#2430).
	if snapshot.AuthSaltSecret == "" && cached != nil {
		snapshot.AuthSaltSecret = cached.AuthSaltSecret
	}
	data, err := json.MarshalIndent(snapshot, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal settings: %w", err)
	}

	if err := os.WriteFile(path, data, 0600); err != nil {
		return fmt.Errorf("failed to write settings file: %w", err)
	}

	cached = snapshot
	return nil
}

// GetAutoUpdate returns whether automatic updates are enabled.
func GetAutoUpdate() bool {
	s, err := Load()
	if err != nil {
		return false
	}
	return s.AutoUpdate
}

// SetAutoUpdate sets the auto-update preference and persists it.
func SetAutoUpdate(enabled bool) error {
	mu.Lock()
	s := cached
	mu.Unlock()

	if s == nil {
		loaded, err := Load()
		if err != nil {
			loaded = &Settings{}
		}
		s = loaded
	}
	s.AutoUpdate = enabled
	return Save(s)
}

// GetRemoteAccess returns whether remote access is enabled.
func GetRemoteAccess() bool {
	s, err := Load()
	if err != nil {
		return false
	}
	return s.RemoteAccessEnabled
}

// SetRemoteAccess sets the remote access enabled flag and persists it.
func SetRemoteAccess(enabled bool) error {
	mu.Lock()
	s := cached
	mu.Unlock()

	if s == nil {
		loaded, err := Load()
		if err != nil {
			loaded = &Settings{}
		}
		s = loaded
	}
	s.RemoteAccessEnabled = enabled
	return Save(s)
}

// GetHousehold returns the stored household credential, or two empty strings
// when the Quark has not enrolled.
func GetHousehold() (household, token string) {
	s, err := Load()
	if err != nil {
		return "", ""
	}
	return s.RemoteAccessHousehold, s.RemoteAccessHouseholdToken
}

// SetHousehold persists the household credential.
func SetHousehold(household, token string) error {
	mu.Lock()
	s := cached
	mu.Unlock()

	if s == nil {
		loaded, err := Load()
		if err != nil {
			loaded = &Settings{}
		}
		s = loaded
	}
	s.RemoteAccessHousehold = household
	s.RemoteAccessHouseholdToken = token
	return Save(s)
}

// GetAccessRequestsEnabled returns whether account requests are on. An unset
// value is on; settings that cannot be read are off, so a broken file does not
// open the sign-in page to requests.
func GetAccessRequestsEnabled() bool {
	s, err := Load()
	if err != nil {
		return false
	}
	return s.AccessRequestsEnabled == nil || *s.AccessRequestsEnabled
}

// SetAccessRequestsEnabled turns account requests on or off and persists it.
func SetAccessRequestsEnabled(enabled bool) error {
	mu.Lock()
	s := cached
	mu.Unlock()

	if s == nil {
		loaded, err := Load()
		if err != nil {
			loaded = &Settings{}
		}
		s = loaded
	}
	s.AccessRequestsEnabled = &enabled
	return Save(s)
}

// GetFeatureFlag returns the stored value of the feature flag key, and
// whether one is stored at all; the caller supplies the default. An error
// means settings could not be read.
func GetFeatureFlag(key string) (enabled, set bool, err error) {
	s, err := Load()
	if err != nil {
		return false, false, err
	}
	enabled, set = s.FeatureFlags[key]
	return enabled, set, nil
}

// SetFeatureFlag stores the feature flag key as on or off and persists it.
// It does not check key against the registry; featureflagutil does.
func SetFeatureFlag(key string, enabled bool) error {
	s, err := Load()
	if err != nil {
		return err
	}
	s.FeatureFlags[key] = enabled
	return Save(s)
}

// GetDeviceID returns the persisted device ID, or empty string if not set.
func GetDeviceID() string {
	s, err := Load()
	if err != nil {
		return ""
	}
	return s.DeviceID
}

// SetDeviceID persists the device ID.
func SetDeviceID(id string) error {
	mu.Lock()
	s := cached
	mu.Unlock()

	if s == nil {
		loaded, err := Load()
		if err != nil {
			loaded = &Settings{}
		}
		s = loaded
	}
	s.DeviceID = id
	return Save(s)
}

// GetActiveBranch returns the active dev branch, or empty string if not set.
func GetActiveBranch() string {
	s, err := Load()
	if err != nil {
		return ""
	}
	return s.ActiveBranch
}

// SetActiveBranch persists the active dev branch.
func SetActiveBranch(branch string) error {
	mu.Lock()
	s := cached
	mu.Unlock()

	if s == nil {
		loaded, err := Load()
		if err != nil {
			loaded = &Settings{}
		}
		s = loaded
	}
	s.ActiveBranch = branch
	return Save(s)
}

// AuthSaltSecret returns this install's salt secret, making and persisting it
// on first use. Losing it locks nobody out: an account's real salt is stored
// with the account, and the secret only decides the salt offered for a
// username that has none.
func AuthSaltSecret() ([]byte, error) {
	secretMu.Lock()
	defer secretMu.Unlock()

	s, err := Load()
	if err != nil {
		return nil, err
	}
	if secret, err := hex.DecodeString(s.AuthSaltSecret); err == nil && len(secret) == authSaltSecretSize {
		return secret, nil
	}
	secret := make([]byte, authSaltSecretSize)
	if _, err := rand.Read(secret); err != nil {
		return nil, fmt.Errorf("failed to generate the salt secret: %w", err)
	}
	s.AuthSaltSecret = hex.EncodeToString(secret)
	if err := Save(s); err != nil {
		return nil, err
	}
	return secret, nil
}

// ResetForTesting resets in-memory state and redirects the settings file to
// path. Call this at the start of each test that touches settingsutil.
func ResetForTesting(path string) {
	mu.Lock()
	defer mu.Unlock()
	cached = nil
	pathOverride = path
}

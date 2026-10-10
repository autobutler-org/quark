// Package settingsutil reads and writes the Quark's settings. They live in the database's settings table, one
// row per setting, so every instance serving an install reads the same values and a change to one setting never
// reverts another (#3083). Nothing is cached: each read is a query. Bind gives the package its database, and
// imports the settings.json an older build kept in the data directory.
package settingsutil

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
)

const settingsFileName = "settings.json"

// featureFlagKeyPrefix starts the settings key of a feature flag, which has a
// row of its own: featureFlags.<flag>.
const featureFlagKeyPrefix = "featureFlags."

// ErrNotBound reports a use of the settings before Bind gave them a database.
var ErrNotBound = errors.New("settings have no database: call settingsutil.Bind first")

// authSaltSecretSize is the salt secret's length in bytes.
const authSaltSecretSize = 32

// Settings holds application-level user-configurable settings.
type Settings struct {
	// SettingsVersion is how many of the package's migrations settings.json
	// had been through. The import runs the rest, so Load always reports the
	// current count; a change to stored settings is now a database migration.
	SettingsVersion int  `json:"settingsVersion"`
	AutoUpdate      bool `json:"autoUpdate"`
	// RemoteAccessEnabled is the user's choice. The node's credential is its
	// tsnet state dir, not a key kept here (#1876): files written before then
	// still carry a remoteAccessAuthKey, which the import leaves behind.
	RemoteAccessEnabled bool `json:"remoteAccessEnabled"`
	// RemoteAccessHousehold and RemoteAccessHouseholdToken are the Quark's
	// Headscale household and the token that authenticates pair requests for
	// it (#2358). They outlive Disable, so the next Enable rejoins the same
	// household.
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
	// ThemeColor is the theme color an admin chose for the whole Quark (#2740),
	// in the form ValidateThemeColor accepts. Empty means the client's default.
	ThemeColor string `json:"themeColor,omitempty"`
	// AuthSaltSecret is the hex of the 32 random bytes that key the salt
	// /auth/salt answers with for an account that has none stored (#2430).
	// AuthSaltSecret makes it on first use and nothing clears it.
	AuthSaltSecret string `json:"authSaltSecret,omitempty"`
}

// ErrInvalidThemeColor reports a theme color that is neither empty, a preset name,
// nor a lowercase #rrggbb color.
var ErrInvalidThemeColor = errors.New("theme color must be empty, a preset name, or a lowercase #rrggbb color")

// themeColorPattern is a preset name or a custom color.
var themeColorPattern = regexp.MustCompile(`^(?:[a-z][a-z0-9-]{0,31}|#[0-9a-f]{6})$`)

// ValidateThemeColor checks the shape of a theme color, the Quark's or an account's
// own: empty (no choice), a preset name, or a custom color as lowercase
// #rrggbb. Anything else is ErrInvalidThemeColor.
//
// Shape is all the server checks, on purpose. The list of preset names lives
// in the Flutter package, and a client falls back to classic for a name
// it does not know, so a preset can be added or retired without a server
// release.
func ValidateThemeColor(themeColor string) error {
	if themeColor != "" && !themeColorPattern.MatchString(themeColor) {
		return ErrInvalidThemeColor
	}
	return nil
}

// Bind gives the package the database its settings live in, and brings in the
// settings.json an older build left in the data directory: see importFile.
// The server calls it once, before anything reads a setting.
//
// A file that cannot be imported leaves the package unbound, so every read
// fails and the getters answer off, as they did when the file could not be
// parsed. Binding anyway would start the Quark on defaults: account requests
// open, and a new salt secret.
func Bind(database *db.DatabaseSqlc) error {
	store.Store(database.Queries)
	if err := importFile(settingsPath()); err != nil {
		store.Store(nil)
		return err
	}
	return nil
}

// Load reads every setting from the database. A setting with no row has its
// zero value. The result is the caller's own: changing it changes nothing
// stored, which is what the Set functions are for.
func Load() (*Settings, error) {
	queries, err := bound()
	if err != nil {
		return nil, err
	}
	rows, err := queries.ListSettings(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to read settings: %w", err)
	}
	raw := map[string]json.RawMessage{}
	flags := map[string]json.RawMessage{}
	for _, row := range rows {
		if flag, ok := strings.CutPrefix(row.Key, featureFlagKeyPrefix); ok {
			flags[flag] = json.RawMessage(row.Value)
		} else {
			raw[row.Key] = json.RawMessage(row.Value)
		}
	}
	s := &Settings{FeatureFlags: map[string]bool{}}
	if err := decodeRaw(raw, flags, s); err != nil {
		return nil, fmt.Errorf("failed to parse settings: %w", err)
	}
	s.SettingsVersion = len(migrations)
	return s, nil
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
	return set("autoUpdate", enabled)
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
	return set("remoteAccessEnabled", enabled)
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
	if err := set("remoteAccessHousehold", household); err != nil {
		return err
	}
	return set("remoteAccessHouseholdToken", token)
}

// GetAccessRequestsEnabled returns whether account requests are on. An unset
// value is on; settings that cannot be read are off, so a broken database does
// not open the sign-in page to requests.
func GetAccessRequestsEnabled() bool {
	s, err := Load()
	if err != nil {
		return false
	}
	return s.AccessRequestsEnabled == nil || *s.AccessRequestsEnabled
}

// SetAccessRequestsEnabled turns account requests on or off and persists it.
func SetAccessRequestsEnabled(enabled bool) error {
	return set("accessRequestsEnabled", enabled)
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
	return set(featureFlagKeyPrefix+key, enabled)
}

// GetThemeColor returns the Quark's theme color, or the empty string when an admin has
// not chosen one or settings cannot be read.
func GetThemeColor() string {
	s, err := Load()
	if err != nil {
		return ""
	}
	return s.ThemeColor
}

// SetThemeColor validates and persists the Quark's theme color. The empty string
// clears it.
func SetThemeColor(themeColor string) error {
	if err := ValidateThemeColor(themeColor); err != nil {
		return err
	}
	return set("themeColor", themeColor)
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
	return set("deviceId", id)
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
	return set("activeBranch", branch)
}

// AuthSaltSecret returns this install's salt secret, making and persisting it
// on first use. Losing it locks nobody out: an account's real salt is stored
// with the account, and the secret only decides the salt offered for a
// username that has none.
//
// Two instances on a fresh install may both make one. Each offers its own to
// the database, which keeps the first, and then both read back what is
// stored, so they answer /auth/salt alike (#3083).
func AuthSaltSecret() ([]byte, error) {
	queries, err := bound()
	if err != nil {
		return nil, err
	}
	ctx := context.Background()
	if secret, err := storedSaltSecret(ctx, queries); secret != nil || err != nil {
		return secret, err
	}
	secret := make([]byte, authSaltSecretSize)
	if _, err := rand.Read(secret); err != nil {
		return nil, fmt.Errorf("failed to generate the salt secret: %w", err)
	}
	value, err := json.Marshal(hex.EncodeToString(secret))
	if err != nil {
		return nil, err
	}
	offer := db.AddSettingParams{Key: authSaltSecretKey, Value: string(value)}
	if err := queries.AddSetting(ctx, offer); err != nil {
		return nil, fmt.Errorf("failed to store the salt secret: %w", err)
	}
	if stored, err := storedSaltSecret(ctx, queries); stored != nil || err != nil {
		return stored, err
	}
	// What is stored is not a secret, so the offer was turned away: replace it.
	if err := queries.SetSetting(ctx, db.SetSettingParams(offer)); err != nil {
		return nil, fmt.Errorf("failed to store the salt secret: %w", err)
	}
	return secret, nil
}

// ResetForTesting gives the package the database beside path, making it if
// need be, and imports the settings file at path, if there is one, the way
// Bind does on startup. A second call with the same path is a restart: it
// reads what the first stored. The empty path leaves the package unbound.
// Call this at the start of each test that touches settingsutil.
func ResetForTesting(path string) {
	if testDB != nil {
		testDB.Close()
		testDB = nil
	}
	store.Store(nil)
	pathOverride = ""
	if path == "" {
		return
	}
	sqlDB, err := sql.Open("sqlite", db.DSN(path+".db"))
	if err != nil {
		panic(fmt.Sprintf("settingsutil: open test database: %v", err))
	}
	testDB = sqlDB
	database := &db.DatabaseSqlc{Db: sqlDB, Queries: db.New(sqlDB)}
	// On a new file this only runs the migrations, and on one an earlier call
	// made it keeps the settings, as every reset does.
	if err := db.ResetDatabase(database); err != nil {
		panic(fmt.Sprintf("settingsutil: migrate test database: %v", err))
	}
	pathOverride = path
	// A file that cannot be imported leaves the package unbound, as in Bind.
	_ = Bind(database)
}

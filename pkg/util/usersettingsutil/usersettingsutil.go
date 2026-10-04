// Package usersettingsutil stores the settings one account chooses for
// itself, as opposed to settingsutil's, which apply to the whole Quark. Each
// account has one JSON file in the Quark's data directory,
// user-settings/<user id>.json, outside every user's home and written 0600.
// An account with no file has chosen nothing.
package usersettingsutil

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// MaxRequestBytes caps a settings request body. The settings are a handful of
// short strings.
const MaxRequestBytes int64 = 4 << 10

// ErrInvalid reports settings that are not well-formed: a body that is not
// one JSON object, a field Settings does not have, or a value its field
// rejects.
var ErrInvalid = errors.New("invalid settings")

// Settings is what an account has chosen for itself.
type Settings struct {
	// ThemeColor overrides the Quark's theme color for this account. Empty means
	// follow the Quark. See settingsutil.ValidateThemeColor for what it may hold.
	ThemeColor string `json:"themeColor"`
}

// LoadParams names the account whose settings to read.
type LoadParams struct {
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
	UserID  int64
}

// LoadResult is an account's stored settings, zero when it has none.
type LoadResult struct {
	Settings Settings
}

// SaveParams is an account's new settings, replacing the stored ones whole.
type SaveParams struct {
	DataDir  string
	UserID   int64
	Settings Settings
}

// SaveResult is the settings as stored.
type SaveResult struct {
	Settings Settings
}

// RemoveParams names the account whose settings to remove.
type RemoveParams struct {
	DataDir string
	UserID  int64
}

// RemoveResult reports whether there were settings to remove.
type RemoveResult struct {
	Removed bool
}

// RemoveAllParams locates every account's settings.
type RemoveAllParams struct {
	DataDir string
}

// Dir returns the directory the settings files are stored in.
func Dir(dataDir string) string {
	return filepath.Join(dataDir, "user-settings")
}

// Path returns the settings file of one account.
func Path(dataDir string, userID int64) string {
	return filepath.Join(Dir(dataDir), strconv.FormatInt(userID, 10)+".json")
}

// Decode reads settings from a request body. Anything but a single JSON
// object holding only Settings' fields, each with a value it accepts, is
// ErrInvalid. The caller bounds the reader (MaxRequestBytes).
func Decode(r io.Reader) (Settings, error) {
	dec := json.NewDecoder(r)
	dec.DisallowUnknownFields()
	var s Settings
	if err := dec.Decode(&s); err != nil {
		return Settings{}, fmt.Errorf("%w: %w", ErrInvalid, err)
	}
	if _, err := dec.Token(); err != io.EOF {
		return Settings{}, fmt.Errorf("%w: more than one JSON value", ErrInvalid)
	}
	if err := settingsutil.ValidateThemeColor(s.ThemeColor); err != nil {
		return Settings{}, fmt.Errorf("%w: %w", ErrInvalid, err)
	}
	return s, nil
}

// Load returns an account's settings. An account with no file gets the zero
// Settings, which follows the Quark in everything.
func Load(params LoadParams) (LoadResult, error) {
	f, err := os.Open(Path(params.DataDir, params.UserID))
	if os.IsNotExist(err) {
		return LoadResult{}, nil
	}
	if err != nil {
		return LoadResult{}, fmt.Errorf("open user settings: %w", err)
	}
	defer f.Close()
	// Lenient where Decode is strict: a file written by a newer build may
	// carry fields this one does not know.
	var s Settings
	if err := json.NewDecoder(io.LimitReader(f, MaxRequestBytes)).Decode(&s); err != nil {
		return LoadResult{}, fmt.Errorf("parse user settings: %w", err)
	}
	return LoadResult{Settings: s}, nil
}

// Save replaces an account's settings. Settings with a value its field
// rejects are ErrInvalid and nothing is written.
func Save(params SaveParams) (SaveResult, error) {
	if err := settingsutil.ValidateThemeColor(params.Settings.ThemeColor); err != nil {
		return SaveResult{}, fmt.Errorf("%w: %w", ErrInvalid, err)
	}
	if err := os.MkdirAll(Dir(params.DataDir), 0o700); err != nil {
		return SaveResult{}, fmt.Errorf("create user settings directory: %w", err)
	}
	data, err := json.MarshalIndent(params.Settings, "", "  ")
	if err != nil {
		return SaveResult{}, fmt.Errorf("marshal user settings: %w", err)
	}
	if err := os.WriteFile(Path(params.DataDir, params.UserID), data, 0o600); err != nil {
		return SaveResult{}, fmt.Errorf("write user settings: %w", err)
	}
	return SaveResult{Settings: params.Settings}, nil
}

// Remove deletes an account's settings. An account with none is not an error.
func Remove(params RemoveParams) (RemoveResult, error) {
	err := os.Remove(Path(params.DataDir, params.UserID))
	if os.IsNotExist(err) {
		return RemoveResult{}, nil
	}
	if err != nil {
		return RemoveResult{}, fmt.Errorf("remove user settings: %w", err)
	}
	return RemoveResult{Removed: true}, nil
}

// RemoveAll deletes every account's settings, for a Quark whose accounts are
// reset and whose ids will be handed out again.
func RemoveAll(params RemoveAllParams) error {
	if err := os.RemoveAll(Dir(params.DataDir)); err != nil {
		return fmt.Errorf("remove user settings: %w", err)
	}
	return nil
}

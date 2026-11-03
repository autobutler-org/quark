// Package usersettingsutil stores the settings one account chooses for
// itself, as opposed to settingsutil's, which apply to the whole Quark. Each
// account has one row in the user_settings table holding the JSON of its
// Settings, so every instance on one database reads the same choice (#3083).
// An account with no row has chosen nothing, and the row goes with its
// account: the foreign key deletes it. A new account starts from a one-time
// Copy of the admin's who made or approved it (#1914). Import moves in the files they used to
// be, user-settings/<user id>.json in the Quark's data directory.
package usersettingsutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"slices"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// MaxRequestBytes caps a settings request body. The settings are a handful of
// short strings and a list of notification types that cannot repeat.
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
	// DisabledNotifications is the notification types this account turned
	// off. Empty means every type is on.
	DisabledNotifications []notificationutil.Type `json:"disabledNotifications,omitempty"`
	// ThemeMode is the brightness the app uses: "system", "light" or "dark".
	// Nil means this account never chose, and the app keeps its own.
	ThemeMode *string `json:"themeMode,omitempty"`
	// RefreshIntervalSeconds is how often the app refreshes the page on
	// screen, 0 (auto-refresh off) through MaxRefreshIntervalSeconds. Nil
	// means this account never chose.
	RefreshIntervalSeconds *int `json:"refreshIntervalSeconds,omitempty"`
	// DocumentAutoSave is whether the document editor saves as the account
	// types. Nil means this account never chose.
	DocumentAutoSave *bool `json:"documentAutoSave,omitempty"`
	// DocumentDarkPage is whether the document editor draws its page dark in
	// a dark theme. Nil means this account never chose.
	DocumentDarkPage *bool `json:"documentDarkPage,omitempty"`
}

// MaxRefreshIntervalSeconds is the longest RefreshIntervalSeconds accepts:
// an hour.
const MaxRefreshIntervalSeconds = 3600

// ThemeModes is every value ThemeMode accepts.
var ThemeModes = []string{"system", "light", "dark"}

// Validate reports settings with a value its field rejects as ErrInvalid: a
// malformed theme color, a notification type that is unknown or listed
// twice, a theme mode not in ThemeModes, or a refresh interval outside 0
// through MaxRefreshIntervalSeconds.
func (s Settings) Validate() error {
	if err := settingsutil.ValidateThemeColor(s.ThemeColor); err != nil {
		return fmt.Errorf("%w: %w", ErrInvalid, err)
	}
	if s.ThemeMode != nil && !slices.Contains(ThemeModes, *s.ThemeMode) {
		return fmt.Errorf("%w: unknown theme mode %q", ErrInvalid, *s.ThemeMode)
	}
	if n := s.RefreshIntervalSeconds; n != nil && (*n < 0 || *n > MaxRefreshIntervalSeconds) {
		return fmt.Errorf("%w: refresh interval %d is outside 0 through %d seconds", ErrInvalid, *n, MaxRefreshIntervalSeconds)
	}
	for i, t := range s.DisabledNotifications {
		if !t.Valid() {
			return fmt.Errorf("%w: unknown notification type %q", ErrInvalid, t)
		}
		// A repeat changes nothing, and refusing it keeps what is stored
		// within MaxRequestBytes.
		if slices.Contains(s.DisabledNotifications[:i], t) {
			return fmt.Errorf("%w: notification type %q is listed twice", ErrInvalid, t)
		}
	}
	return nil
}

// LoadParams names the account whose settings to read.
type LoadParams struct {
	Queries db.Querier
	UserID  int64
}

// LoadResult is an account's stored settings, zero when it has none.
type LoadResult struct {
	Settings Settings
}

// SaveParams is an account's new settings, replacing the stored ones whole.
type SaveParams struct {
	Queries  db.Querier
	UserID   int64
	Settings Settings
}

// SaveResult is the settings as stored.
type SaveResult struct {
	Settings Settings
}

// CopyParams names the account whose settings a new account starts from.
type CopyParams struct {
	Queries    db.Querier
	FromUserID int64
	ToUserID   int64
}

// CopyResult reports whether Copy wrote anything.
type CopyResult struct {
	// Copied is false when the source has no settings, or when the target
	// already had its own. A target account that does not exist gets nothing
	// either way.
	Copied bool
}

// ImportParams locates the settings files of a Quark from before the
// settings moved into the database.
type ImportParams struct {
	Queries db.Querier
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
}

// ImportResult reports what Import found.
type ImportResult struct {
	// Files is how many settings files were read and offered to the database.
	// Zero when there was no directory.
	Files int
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
	if err := s.Validate(); err != nil {
		return Settings{}, err
	}
	return s, nil
}

// Load returns an account's settings. An account with no row gets the zero
// Settings, which follows the Quark in everything.
func Load(ctx context.Context, params LoadParams) (LoadResult, error) {
	stored, err := params.Queries.GetUserSettings(ctx, params.UserID)
	if errors.Is(err, sql.ErrNoRows) {
		return LoadResult{}, nil
	}
	if err != nil {
		return LoadResult{}, fmt.Errorf("read user settings: %w", err)
	}
	// Lenient where Decode is strict: a row written by a newer build may
	// carry fields this one does not know.
	var s Settings
	if err := json.Unmarshal([]byte(stored), &s); err != nil {
		return LoadResult{}, fmt.Errorf("parse user settings: %w", err)
	}
	return LoadResult{Settings: s}, nil
}

// Save replaces an account's settings. Settings with a value its field
// rejects are ErrInvalid and nothing is written.
func Save(ctx context.Context, params SaveParams) (SaveResult, error) {
	if err := params.Settings.Validate(); err != nil {
		return SaveResult{}, err
	}
	data, err := json.Marshal(params.Settings)
	if err != nil {
		return SaveResult{}, fmt.Errorf("marshal user settings: %w", err)
	}
	if err := params.Queries.SetUserSettings(ctx, db.SetUserSettingsParams{UserID: params.UserID, Settings: string(data)}); err != nil {
		return SaveResult{}, fmt.Errorf("write user settings: %w", err)
	}
	return SaveResult{Settings: params.Settings}, nil
}

// Copy starts one account from another's settings, once (#1914): later
// changes to the source do not reach the copy. A source with no row copies
// nothing, so the target keeps following the Quark, and a target that already
// has settings keeps them. The row goes over as stored, fields a newer build
// wrote included.
func Copy(ctx context.Context, params CopyParams) (CopyResult, error) {
	stored, err := params.Queries.GetUserSettings(ctx, params.FromUserID)
	if errors.Is(err, sql.ErrNoRows) {
		return CopyResult{}, nil
	}
	if err != nil {
		return CopyResult{}, fmt.Errorf("read user settings: %w", err)
	}
	if _, err := params.Queries.GetUserSettings(ctx, params.ToUserID); err == nil {
		return CopyResult{}, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return CopyResult{}, fmt.Errorf("read user settings: %w", err)
	}
	if err := params.Queries.AddUserSettings(ctx, db.AddUserSettingsParams{UserID: params.ToUserID, Settings: stored}); err != nil {
		return CopyResult{}, fmt.Errorf("copy user settings: %w", err)
	}
	return CopyResult{Copied: true}, nil
}

// Import moves the settings files of an older Quark into the database and
// renames their directory user-settings.imported so the next start finds
// nothing to do. Settings already in the database are kept, and a file whose
// account no longer exists is dropped. A file that cannot be read or parsed
// is logged and skipped, so one damaged file does not keep the rest out. No
// directory is nothing to do.
func Import(ctx context.Context, params ImportParams) (ImportResult, error) {
	dir := legacyDir(params.DataDir)
	files, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return ImportResult{}, nil
	}
	if err != nil {
		return ImportResult{}, fmt.Errorf("read user settings directory: %w", err)
	}
	result := ImportResult{}
	for _, file := range files {
		name, isSettings := strings.CutSuffix(file.Name(), ".json")
		userID, err := strconv.ParseInt(name, 10, 64)
		if !isSettings || err != nil {
			continue
		}
		settings, err := readLegacyFile(dir, file.Name())
		if err != nil {
			slog.Warn("user settings: skipping a file that cannot be imported", "file", file.Name(), "err", err)
			continue
		}
		if err := params.Queries.AddUserSettings(ctx, db.AddUserSettingsParams{UserID: userID, Settings: settings}); err != nil {
			return ImportResult{}, fmt.Errorf("import user settings: %w", err)
		}
		result.Files++
	}
	// Another instance may have renamed it first; its rows are the same ones.
	if err := os.Rename(dir, dir+".imported"); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return ImportResult{}, fmt.Errorf("retire user settings directory: %w", err)
	}
	return result, nil
}

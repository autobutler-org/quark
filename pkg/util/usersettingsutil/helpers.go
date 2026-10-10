package usersettingsutil

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
)

// legacyDir is where the settings files of a Quark from before the settings
// moved into the database are.
func legacyDir(dataDir string) string {
	return filepath.Join(dataDir, "user-settings")
}

// readLegacyFile returns the settings one legacy file holds, as the JSON the
// user_settings table stores. Like Load it is lenient about fields this build
// does not know, and it reads no more than MaxRequestBytes.
func readLegacyFile(dir, name string) (string, error) {
	f, err := os.Open(filepath.Join(dir, name))
	if err != nil {
		return "", err
	}
	defer f.Close()
	var s Settings
	if err := json.NewDecoder(io.LimitReader(f, MaxRequestBytes)).Decode(&s); err != nil {
		return "", err
	}
	data, err := json.Marshal(s)
	return string(data), err
}

package authutil

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

// usernamePattern is what a new account's username must match. A username
// also names a folder and a URL path segment, so it cannot hold a slash, start
// with a dot, or be ".." (#1908). Accounts created before the rule keep theirs.
var usernamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,31}$`)

// validateUsername returns ErrInvalidUsername for a username a new account
// cannot have.
func validateUsername(username string) error {
	if !usernamePattern.MatchString(username) {
		return ErrInvalidUsername
	}
	return nil
}

// statusError is the error a sign-in gets for an account's status, nil for an
// active account. A status the table's CHECK should keep out is refused like a
// disabled one.
func statusError(status string) error {
	switch status {
	case StatusActive:
		return nil
	case StatusPending:
		return ErrAccountPending
	default:
		return ErrAccountDisabled
	}
}

// mountsDirName is the directory under the data directory where external
// devices are mounted.
const mountsDirName = "mounts"

// pruneMountPoints removes the empty per-device directories under
// <dataDir>/mounts and nothing else.
//
// These are real mount targets: enabling a USB device creates
// <dataDir>/mounts/<serial> and mounts a partition onto it. Recursing into that
// tree with RemoveAll would delete straight through the mount into the user's
// external drive — the exact data that stays untouched unless devices=true is
// passed, and more of it than even devices=true authorizes, since that only
// reaches the quark data directory on a drive. os.Remove refuses a directory
// that is not empty, so a still-mounted or still-populated target survives and
// only the stale scaffolding goes.
func pruneMountPoints(dataDir string) error {
	mountsDir := filepath.Join(dataDir, mountsDirName)

	entries, err := os.ReadDir(mountsDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed to read mount points: %w", err)
	}

	for _, entry := range entries {
		// Deliberately unchecked: a non-empty directory is a live mount or a
		// populated target, and leaving it is the correct outcome.
		_ = os.Remove(filepath.Join(mountsDir, entry.Name()))
	}
	return nil
}

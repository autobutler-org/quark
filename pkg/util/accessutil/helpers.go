package accessutil

import (
	"context"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// inTx runs fn against queries bound to one transaction, committing only if fn
// succeeds.
func inTx(ctx context.Context, database *db.DatabaseSqlc, fn func(*db.Queries) error) error {
	tx, err := database.Db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(database.Queries.WithTx(tx)); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// levelsFromRows folds the rows into the highest level per device and path. A
// user granted read directly and write through a group gets write.
func levelsFromRows(rows []db.ListPathAccessForUserRow) map[string]map[string]Level {
	levels := make(map[string]map[string]Level)
	for _, row := range rows {
		paths, ok := levels[row.DeviceSerial]
		if !ok {
			paths = make(map[string]Level)
			levels[row.DeviceSerial] = paths
		}
		rel := Canonical(row.RelPath)
		paths[rel] = max(paths[rel], parseLevel(row.Level))
	}
	return levels
}

// parseLevel reads the level column. The table's CHECK constraint keeps
// anything else out; None is the safe answer if it ever does not.
func parseLevel(s string) Level {
	switch s {
	case "read":
		return Read
	case "write":
		return Write
	case "owner":
		return Owner
	default:
		return None
	}
}

// filesDirsBySerial maps each attached device's serial to its files
// directory. The internal device answers to the empty serial; the first one
// wins, matching StorageService.FindManagedDeviceBySerial.
func filesDirsBySerial(devices []storageutil.ManagedDevice) map[string]string {
	dirs := make(map[string]string, len(devices))
	for _, device := range devices {
		serial := ""
		if device.UsbInfo != nil {
			serial = device.UsbInfo.GetSerial()
		} else if !device.IsInternal {
			continue
		}
		if _, seen := dirs[serial]; !seen {
			dirs[serial] = device.FilesDir
		}
	}
	return dirs
}

// isBeneath reports whether granted lies strictly inside dir. Both are
// canonical, so "foobar" is not inside "foo".
func isBeneath(dir, granted string) bool {
	if dir == "" {
		return granted != ""
	}
	return strings.HasPrefix(granted, dir+"/")
}

// resolveRel follows the symlinks on a canonical path and reports where it
// really lands, canonical and relative to filesDir. The path need not exist
// yet — an upload destination does not — so the longest prefix that does is
// resolved and the rest is appended. It reports false when the path leads out
// of filesDir, or runs through a link that resolves to nothing, since a write
// through a dangling link lands wherever the link points.
func resolveRel(filesDir, rel string) (string, bool) {
	base, err := filepath.EvalSymlinks(filesDir)
	if err != nil {
		return "", false
	}
	root := filepath.Clean(filesDir)
	current := filepath.Join(root, filepath.FromSlash(rel))
	suffix := ""
	for {
		landed, err := filepath.EvalSymlinks(current)
		if err == nil {
			resolved := filepath.Join(landed, suffix)
			if resolved != base && !strings.HasPrefix(resolved, base+string(filepath.Separator)) {
				return "", false
			}
			inside, err := filepath.Rel(base, resolved)
			if err != nil {
				return "", false // coverage: ignore - both paths are absolute and resolved
			}
			return Canonical(inside), true
		}
		if _, statErr := os.Lstat(current); statErr == nil || current == root {
			return "", false
		}
		suffix = filepath.Join(filepath.Base(current), suffix)
		current = filepath.Dir(current)
	}
}

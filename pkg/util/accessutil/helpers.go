package accessutil

import (
	"cmp"
	"context"
	"database/sql"
	"errors"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
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
		// The table's CHECK constraint keeps any other spelling out; None is
		// the safe answer if it ever does not.
		paths[rel] = max(paths[rel], ParseLevel(row.Level))
	}
	return levels
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

// shareablePath canonicalizes a path whose sharing the caller wants to see or
// change, and refuses it unless the caller owns it or is an admin. The trash
// is refused first: what sits there is on its way out, whoever owned it.
func shareablePath(access Access, serial, p string) (string, error) {
	rel := Canonical(p)
	if storageutil.IsTrashPath(rel) {
		return "", ErrTrashShare
	}
	check := access.Check(serial, rel, Owner)
	if !check.Readable {
		return "", ErrShareNotFound
	}
	if !check.Allowed {
		return "", ErrShareForbidden
	}
	return rel, nil
}

// ensurePrincipal returns ErrPrincipalNotFound unless the user is active or
// the group exists.
func ensurePrincipal(ctx context.Context, queries *db.Queries, userID, groupID int64) error {
	if userID != 0 {
		user, err := queries.GetUserByID(ctx, userID)
		if errors.Is(err, sql.ErrNoRows) || (err == nil && user.Status != authutil.StatusActive) {
			return ErrPrincipalNotFound
		}
		return err
	}
	_, err := queries.GetGroup(ctx, groupID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrPrincipalNotFound
	}
	return err
}

// ensureNotSelfOwner returns ErrSelfOwner when a non-admin's change would
// touch their own owner row on exactly this path. Ownership they inherit from
// a parent folder is not touched by it, so it doesn't count.
func ensureNotSelfOwner(ctx context.Context, queries *db.Queries, principal Principal, serial, rel string, userID int64) error {
	if principal.IsAdmin || userID == 0 || userID != principal.UserID {
		return nil
	}
	rows, err := queries.ListPathAccessOnAncestors(ctx, db.ListPathAccessOnAncestorsParams{DeviceSerial: serial, RelPath: rel})
	if err != nil {
		return err
	}
	for _, row := range rows {
		if row.RelPath == rel && row.UserID.Int64 == userID && ParseLevel(row.Level) == Owner {
			return ErrSelfOwner
		}
	}
	return nil
}

// grantsFromRows turns the rows on a path and its parent folders into grants:
// every row on the path, then one grant per principal for what the parent
// folders give, at the highest level and from the nearest folder giving it.
// Each part is sorted everyone first, then by name.
func grantsFromRows(rows []db.ListPathAccessOnAncestorsRow, rel string) []Grant {
	type principalKey struct{ userID, groupID int64 }
	direct := make([]Grant, 0, len(rows))
	inherited := make(map[principalKey]Grant)
	for _, row := range rows {
		grant := Grant{
			UserID:  row.UserID.Int64,
			GroupID: row.GroupID.Int64,
			Name:    row.Name,
			Builtin: row.Builtin != 0,
			Level:   row.Level,
			From:    row.RelPath,
		}
		if row.RelPath == rel {
			direct = append(direct, grant)
			continue
		}
		key := principalKey{grant.UserID, grant.GroupID}
		held, ok := inherited[key]
		level, heldLevel := ParseLevel(grant.Level), ParseLevel(held.Level)
		if !ok || level > heldLevel || (level == heldLevel && len(grant.From) > len(held.From)) {
			inherited[key] = grant
		}
	}
	byName := func(a, b Grant) int {
		if a.Builtin != b.Builtin {
			if a.Builtin {
				return -1
			}
			return 1
		}
		return cmp.Or(
			cmp.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name)),
			cmp.Compare(a.UserID, b.UserID),
			cmp.Compare(a.GroupID, b.GroupID),
		)
	}
	slices.SortFunc(direct, byName)
	fromParents := make([]Grant, 0, len(inherited))
	for _, grant := range inherited {
		fromParents = append(fromParents, grant)
	}
	slices.SortFunc(fromParents, byName)
	return append(direct, fromParents...)
}

// publishAccessChanged tells open streams the access on a path changed. A nil
// bus is a caller that does not care.
func publishAccessChanged(bus *eventbus.Bus, serial, rel string) {
	if bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged, Path: rel, DeviceSerial: serial})
	}
}

// isStructuralRoot reports whether a path is the users or groups folder on the
// internal device, the parents of every home and every group folder.
func isStructuralRoot(serial, p string) bool {
	if serial != "" {
		return false
	}
	rel := Canonical(p)
	return rel == authutil.UsersDirName || rel == authutil.GroupsDirName
}

// sharedRoots keeps the granted paths the Shared with me shortcut lists, in
// order of device then path. Level travels with each; the owner is read from
// the database afterward.
func sharedRoots(levels map[string]map[string]Level, username string) []SharedItem {
	home := ""
	if username != "" {
		home = path.Join(authutil.UsersDirName, username)
	}
	items := make([]SharedItem, 0)
	for serial, paths := range levels {
		for rel, level := range paths {
			if isSharedRoot(serial, rel, home, paths) {
				items = append(items, SharedItem{DeviceSerial: serial, RelPath: rel, Level: level.String()})
			}
		}
	}
	slices.SortFunc(items, func(a, b SharedItem) int {
		return cmp.Or(cmp.Compare(a.DeviceSerial, b.DeviceSerial), cmp.Compare(a.RelPath, b.RelPath))
	})
	return items
}

// isSharedRoot reports whether one granted path is a root of an ad-hoc share,
// rather than somewhere the file browser reaches another way. home is the
// caller's own, empty when their name is not known.
func isSharedRoot(serial, rel, home string, paths map[string]Level) bool {
	if rel == "" || isStructuralRoot(serial, rel) || storageutil.IsTrashPath(rel) {
		return false
	}
	if serial == "" {
		if isBeneath(authutil.GroupsDirName, rel) {
			return false
		}
		if home != "" && (rel == home || isBeneath(home, rel)) {
			return false
		}
	}
	for ancestor := path.Dir(rel); ancestor != "."; ancestor = path.Dir(ancestor) {
		if _, granted := paths[ancestor]; granted && isSharedRoot(serial, ancestor, home, paths) {
			return false
		}
	}
	return true
}

// ownerName is who owns the path the rows were read for: the account or group
// on the owner row nearest it, which is the row on the path itself or the one
// on the closest folder holding it. It is empty when no owner row covers the
// path, which leaves the share unlabeled rather than labeled wrongly.
func ownerName(rows []db.ListPathAccessOnAncestorsRow) string {
	name, from := "", -1
	for _, row := range rows {
		if ParseLevel(row.Level) == Owner && len(row.RelPath) > from {
			name, from = row.Name, len(row.RelPath)
		}
	}
	return name
}

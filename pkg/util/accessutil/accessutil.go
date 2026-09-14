// Package accessutil answers who may reach a path (#1902).
//
// Access is recorded in the path_access table, keyed by (device serial,
// canonical path), and is additive down the tree: a path's level is the
// highest level granted on it or on any ancestor. Admins bypass the table, so a
// path nobody was granted is admin-only.
//
// Callers load a principal's rows once per request with [Load] and ask the
// returned [Access] as many questions as they need; nothing after the load
// touches the database.
package accessutil

import (
	"context"
	"database/sql"
	"errors"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// Level is how much a principal may do with a path. Levels are ordered, so a
// higher one includes everything a lower one allows.
type Level int

const (
	// None allows nothing.
	None Level = iota
	// Read allows listing, stat and download.
	Read
	// Write allows creating, changing, moving and deleting.
	Write
	// Owner is write plus, in later phases, sharing.
	Owner
)

// String is the spelling the path_access table stores. None has no row, so it
// has no spelling.
func (l Level) String() string {
	switch l {
	case Read:
		return "read"
	case Write:
		return "write"
	case Owner:
		return "owner"
	default:
		return ""
	}
}

// Principal is who a request acts as. The zero value is nobody and is denied
// everything, so a request that never set one fails closed.
type Principal struct {
	UserID  int64
	IsAdmin bool
}

// System is the principal background work and admin-only code paths act as.
// It is allowed everything without a database.
var System = Principal{IsAdmin: true}

// ErrNoDatabase reports a write to the access table with no database to write
// it to.
var ErrNoDatabase = errors.New("accessutil: no database")

// ErrMoveIntoItself reports a move of rows onto a path inside the one moved,
// or out of a path onto one of its ancestors. No filesystem move can do either.
var ErrMoveIntoItself = errors.New("accessutil: cannot move a path into itself")

// Canonical spells a path the one way the access table keys it:
// slash-separated, cleaned, no leading slash, and "" for the device root. So
// "Photos", "/Photos" and "Photos/" are the same row, and ".." cannot climb
// out of the root.
func Canonical(p string) string {
	return strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(p)), "/")
}

// Access is one principal's rows, resolved in memory.
type Access struct {
	principal Principal
	// levels maps a device serial to the level granted exactly at each
	// canonical path on it.
	levels map[string]map[string]Level
	// filesDirs maps the serial of every attached device to its files
	// directory. A serial missing here is a device that is not attached.
	filesDirs map[string]string
}

// LoadParams loads what a principal has been granted.
type LoadParams struct {
	Ctx context.Context
	// Database holds the rows. Nil denies every non-admin everything.
	Database *db.DatabaseSqlc
	// Storage lists the attached devices a path may be on. Nil denies every
	// non-admin everything.
	Storage   *storageutil.StorageService
	Principal Principal
}

// LoadResult is the loaded access.
type LoadResult struct {
	Access Access
}

// Load reads the principal's rows. An admin needs none and gets no query.
func Load(params LoadParams) (LoadResult, error) {
	access := Access{principal: params.Principal}
	if params.Principal.IsAdmin || params.Principal.UserID == 0 ||
		params.Database == nil || params.Storage == nil {
		return LoadResult{Access: access}, nil
	}

	// ponytail: loads every row that applies to the user and resolves
	// ancestors in memory. Upgrade to a query on the ancestors of the requested
	// path if a household grows enough rows for this to show up.
	rows, err := params.Database.Queries.ListPathAccessForUser(params.Ctx,
		sql.NullInt64{Int64: params.Principal.UserID, Valid: true})
	if err != nil {
		return LoadResult{}, err
	}
	devices, err := params.Storage.GetManagedDevices()
	if err != nil {
		return LoadResult{}, err
	}

	access.levels = levelsFromRows(rows)
	access.filesDirs = filesDirsBySerial(devices)
	return LoadResult{Access: access}, nil
}

// Principal is who the access was loaded for.
func (a Access) Principal() Principal {
	return a.principal
}

// Level is the highest level granted on the path or any ancestor, read from
// the rows alone. It does not resolve symlinks or check that the device is
// attached; [Access.Check] does.
func (a Access) Level(serial, p string) Level {
	if a.principal.IsAdmin {
		return Owner
	}
	paths := a.levels[serial]
	if len(paths) == 0 {
		return None
	}
	rel := Canonical(p)
	level := paths[""]
	for i := range len(rel) {
		if rel[i] == '/' {
			level = max(level, paths[rel[:i]])
		}
	}
	if rel != "" {
		level = max(level, paths[rel])
	}
	return level
}

// HasBeneath reports whether anything strictly inside the path was granted.
// It is what lets /Family show up on the way to a folder shared at
// /Family/Bob.
func (a Access) HasBeneath(serial, p string) bool {
	if a.principal.IsAdmin {
		return true
	}
	rel := Canonical(p)
	// ponytail: linear in the user's rows on the device; index by prefix if
	// row counts grow large.
	for granted := range a.levels[serial] {
		if isBeneath(rel, granted) {
			return true
		}
	}
	return false
}

// CheckResult is what a principal may do with one path.
type CheckResult struct {
	// Level is the effective level after symlink resolution.
	Level Level
	// Readable reports whether the caller may know the path exists. A handler
	// answers 404 when it is false.
	Readable bool
	// Allowed reports whether the level reaches the one asked for. A handler
	// answers 403 when the path is readable but this is false.
	Allowed bool
}

// Check reports what the principal may do with a path, for the level a
// handler requires.
//
// For a non-admin, a serial that names no attached device is unreadable, and
// so is a path whose symlinks lead out of the device's files directory. A path
// that resolves somewhere else inside it takes the lower of the two levels, so
// a link inside a shared folder cannot reach what the link points at unless
// that was shared too.
func (a Access) Check(serial, p string, required Level) CheckResult {
	if a.principal.IsAdmin {
		return CheckResult{Level: Owner, Readable: true, Allowed: true}
	}
	filesDir, attached := a.filesDirs[serial]
	if !attached {
		return CheckResult{}
	}
	rel := Canonical(p)
	level := a.Level(serial, rel)
	if level == None {
		return CheckResult{}
	}
	resolved, ok := resolveRel(filesDir, rel)
	if !ok {
		return CheckResult{}
	}
	if resolved != rel {
		level = min(level, a.Level(serial, resolved))
	}
	return CheckResult{Level: level, Readable: level >= Read, Allowed: level >= required}
}

// VisibleOnAny reports whether a folder listing merged across devices may be
// shown at all: the folder is visible on one of the serials, or on any
// attached device when serials is empty.
func (a Access) VisibleOnAny(serials []string, p string) bool {
	if a.principal.IsAdmin {
		return true
	}
	candidates := make([]string, 0, len(a.filesDirs))
	if len(serials) > 0 {
		candidates = append(candidates, serials...)
	} else {
		for serial := range a.filesDirs {
			candidates = append(candidates, serial)
		}
	}
	for _, serial := range candidates {
		if a.Visible(serial, p) {
			return true
		}
	}
	return false
}

// Visible reports whether a listing may show the path: the principal can read
// it, or something beneath it was shared with them.
func (a Access) Visible(serial, p string) bool {
	if a.principal.IsAdmin {
		return true
	}
	if _, attached := a.filesDirs[serial]; !attached {
		return false
	}
	return a.Check(serial, p, Read).Readable || a.HasBeneath(serial, p)
}

// VisibleChildrenParams filters a directory listing.
type VisibleChildrenParams[T any] struct {
	Access   Access
	Children []T
	// Locate names the device and path of a child.
	Locate func(child T) (serial, path string)
}

// VisibleChildrenResult is the listing the principal may see.
type VisibleChildrenResult[T any] struct {
	Children []T
}

// VisibleChildren keeps the children a listing may show. An admin's listing
// comes back as it went in.
func VisibleChildren[T any](params VisibleChildrenParams[T]) VisibleChildrenResult[T] {
	if params.Access.principal.IsAdmin {
		return VisibleChildrenResult[T]{Children: params.Children}
	}
	kept := make([]T, 0, len(params.Children))
	for _, child := range params.Children {
		if params.Access.Visible(params.Locate(child)) {
			kept = append(kept, child)
		}
	}
	return VisibleChildrenResult[T]{Children: kept}
}

// GrantOwnerIfNeededParams gives the caller ownership of something they just
// created.
type GrantOwnerIfNeededParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// Access is the caller's access as loaded for the request.
	Access       Access
	DeviceSerial string
	Path         string
}

// GrantOwnerIfNeededResult reports whether a row was written.
type GrantOwnerIfNeededResult struct {
	Granted bool
}

// GrantOwnerIfNeeded records the caller as owner of a path they created. An
// admin needs no row, and neither does a caller who already owns the path
// through an ancestor, so uploading into your own folder adds nothing.
func GrantOwnerIfNeeded(params GrantOwnerIfNeededParams) (GrantOwnerIfNeededResult, error) {
	principal := params.Access.principal
	if principal.IsAdmin || params.Access.Level(params.DeviceSerial, params.Path) >= Owner {
		return GrantOwnerIfNeededResult{}, nil
	}
	if params.Database == nil || principal.UserID == 0 {
		return GrantOwnerIfNeededResult{}, ErrNoDatabase
	}
	if err := params.Database.Queries.SetUserPathAccess(params.Ctx, db.SetUserPathAccessParams{
		DeviceSerial: params.DeviceSerial,
		RelPath:      Canonical(params.Path),
		UserID:       sql.NullInt64{Int64: principal.UserID, Valid: true},
		Level:        Owner.String(),
	}); err != nil {
		return GrantOwnerIfNeededResult{}, err
	}
	return GrantOwnerIfNeededResult{Granted: true}, nil
}

// MoveRowsParams carries access rows along with something that moved.
type MoveRowsParams struct {
	Ctx context.Context
	// Database holds the rows. Nil does nothing.
	Database *db.DatabaseSqlc
	// EventBus hears access_changed when any row moved. Nil skips it.
	EventBus  *eventbus.Bus
	OldSerial string
	OldPath   string
	NewSerial string
	NewPath   string
}

// MoveRowsResult counts the rows that moved.
type MoveRowsResult struct {
	Moved int64
}

// MoveRows points the rows on a path and everything beneath it at where it
// went, including onto another device (#1905). Rows on the destination and
// beneath it are dropped first: whatever they described has been replaced.
// Both happen in one transaction.
func MoveRows(params MoveRowsParams) (MoveRowsResult, error) {
	oldPath, newPath := Canonical(params.OldPath), Canonical(params.NewPath)
	sameDevice := params.OldSerial == params.NewSerial
	if params.Database == nil || oldPath == "" || newPath == "" || (sameDevice && oldPath == newPath) {
		return MoveRowsResult{}, nil
	}
	if sameDevice && (isBeneath(oldPath, newPath) || isBeneath(newPath, oldPath)) {
		return MoveRowsResult{}, ErrMoveIntoItself
	}

	var moved int64
	err := inTx(params.Ctx, params.Database, func(q *db.Queries) error {
		if _, err := q.DeletePathAccessTree(params.Ctx, db.DeletePathAccessTreeParams{
			DeviceSerial: params.NewSerial,
			RelPath:      newPath,
		}); err != nil {
			return err
		}
		n, err := q.MovePathAccessTree(params.Ctx, db.MovePathAccessTreeParams{
			NewDeviceSerial: params.NewSerial,
			NewRelPath:      newPath,
			OldDeviceSerial: params.OldSerial,
			OldRelPath:      oldPath,
		})
		moved = n
		return err
	})
	if err != nil {
		return MoveRowsResult{}, err
	}
	if moved > 0 && params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind:         eventbus.EventAccessChanged,
			Path:         newPath,
			DeviceSerial: params.NewSerial,
		})
	}
	return MoveRowsResult{Moved: moved}, nil
}

// DeleteRowsParams drops the access rows of paths that are gone for good.
type DeleteRowsParams struct {
	Ctx context.Context
	// Database holds the rows. Nil does nothing.
	Database *db.DatabaseSqlc
	// EventBus hears access_changed for each path that lost rows. Nil skips it.
	EventBus     *eventbus.Bus
	DeviceSerial string
	// Paths are the deleted paths; each takes everything beneath it.
	Paths []string
}

// DeleteRowsResult counts the rows deleted.
type DeleteRowsResult struct {
	Deleted int64
}

// DeleteRows drops the rows on each path and everything beneath it, in one
// transaction, so something created at that path later starts with none
// (#1905). A device root is never deleted, so its rows are never dropped.
func DeleteRows(params DeleteRowsParams) (DeleteRowsResult, error) {
	if params.Database == nil || len(params.Paths) == 0 {
		return DeleteRowsResult{}, nil
	}

	var deleted int64
	changed := make([]string, 0, len(params.Paths))
	err := inTx(params.Ctx, params.Database, func(q *db.Queries) error {
		for _, p := range params.Paths {
			rel := Canonical(p)
			if rel == "" {
				continue
			}
			n, err := q.DeletePathAccessTree(params.Ctx, db.DeletePathAccessTreeParams{
				DeviceSerial: params.DeviceSerial,
				RelPath:      rel,
			})
			if err != nil {
				return err
			}
			if n > 0 {
				deleted += n
				changed = append(changed, rel)
			}
		}
		return nil
	})
	if err != nil {
		return DeleteRowsResult{}, err
	}
	if params.EventBus != nil {
		for _, rel := range changed {
			params.EventBus.Publish(eventbus.Event{
				Kind:         eventbus.EventAccessChanged,
				Path:         rel,
				DeviceSerial: params.DeviceSerial,
			})
		}
	}
	return DeleteRowsResult{Deleted: deleted}, nil
}

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
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
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

// LoadRequest loads the access of whoever a request acts as, once per request.
// requireAuth puts the principal on the context; a request that arrives without
// one gets the zero principal, which is denied everything.
func LoadRequest(c *gin.Context, database *db.DatabaseSqlc, storage *storageutil.StorageService) (Access, error) {
	principal, _ := ctxutil.Get[Principal](c, "principal")
	result, err := Load(LoadParams{
		Ctx:       c.Request.Context(),
		Database:  database,
		Storage:   storage,
		Principal: principal,
	})
	return result.Access, err
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

// FilterEventParams decides what one event stream subscriber hears (#1906).
type FilterEventParams struct {
	// Access is the subscriber's access as it stands for this event.
	Access Access
	// Previous is their access from before the access_changed event being
	// filtered reloaded it. It is only read for access_changed.
	Previous Access
	Event    eventbus.Event
}

// FilterEventResult is what to send the subscriber, if anything.
type FilterEventResult struct {
	Event   eventbus.Event
	Deliver bool
}

// FilterEvent decides whether a subscriber hears an event, and in what form.
// It reads only the snapshots it is given, never the database.
//
//   - An admin hears every event unchanged.
//   - trash_changed and account_changed carry no path and pass: each tells an
//     open app to refetch something that answers for the caller already. The
//     backup and vault events are appliance-wide and are dropped.
//   - A move between two readable paths passes. A move into a readable path
//     from an unreadable one reads as an upload into the new path's folder, and
//     one out of a readable path into an unreadable one as a delete of the old
//     path. A move between two unreadable paths is dropped.
//   - access_changed passes when its path is visible to the subscriber before
//     or after the change, so a listing that just gained or lost entries
//     reloads. One with no path, from a group membership change or a deleted
//     group (#1910), may have changed anything and always passes.
//   - A job_* event carries no path and passes when CanSeeJob shows its job,
//     with the job's error left out (#1979).
//   - Anything else passes when its path is readable.
func FilterEvent(params FilterEventParams) FilterEventResult {
	evt := params.Event
	access := params.Access
	if access.principal.IsAdmin {
		return FilterEventResult{Event: evt, Deliver: true}
	}
	readable := func(p string) bool {
		return access.Check(evt.DeviceSerial, p, Read).Readable
	}

	switch evt.Kind {
	case eventbus.EventTrashChanged, eventbus.EventAccountChanged:
		return FilterEventResult{Event: evt, Deliver: true}
	case eventbus.EventBackupStarted, eventbus.EventBackupProgress, eventbus.EventBackupCompleted,
		eventbus.EventBackupFailed, eventbus.EventVaultDeviceDisconnected, eventbus.EventVaultDeviceReconnected,
		eventbus.EventVaultStorageChanged:
		return FilterEventResult{}
	case eventbus.EventMove:
		oldReadable, newReadable := readable(evt.Path), readable(evt.NewPath)
		switch {
		case oldReadable && newReadable:
			return FilterEventResult{Event: evt, Deliver: true}
		case newReadable:
			return FilterEventResult{Deliver: true, Event: eventbus.Event{
				Kind:         eventbus.EventUpload,
				Path:         Canonical(path.Dir(Canonical(evt.NewPath))),
				DeviceSerial: evt.DeviceSerial,
			}}
		case oldReadable:
			return FilterEventResult{Deliver: true, Event: eventbus.Event{
				Kind:         eventbus.EventDelete,
				Path:         evt.Path,
				DeviceSerial: evt.DeviceSerial,
			}}
		default:
			return FilterEventResult{}
		}
	case eventbus.EventAccessChanged:
		visible := Canonical(evt.Path) == "" ||
			params.Previous.Visible(evt.DeviceSerial, evt.Path) || access.Visible(evt.DeviceSerial, evt.Path)
		return FilterEventResult{Event: evt, Deliver: visible}
	case eventbus.EventJobQueued, eventbus.EventJobStarted, eventbus.EventJobProgress,
		eventbus.EventJobCompleted, eventbus.EventJobFailed, eventbus.EventJobCanceled:
		job, ok := evt.Data.(jobutil.Job)
		if !ok || !access.CanSeeJob(job) {
			return FilterEventResult{}
		}
		evt.Data = access.RedactJob(job)
		return FilterEventResult{Event: evt, Deliver: true}
	default:
		return FilterEventResult{Event: evt, Deliver: readable(evt.Path)}
	}
}

// CanSeeTrash reports whether a trashed item is shown to the principal: they
// trashed it, they can read where it came from, or they can read where its
// access rows sit while it is in the trash. An item that does not record who
// trashed it predates the per-user trash and is admin-only (#1905).
func (a Access) CanSeeTrash(serial, trashName, originalPath string, trashedBy int64) bool {
	if a.principal.IsAdmin {
		return true
	}
	if trashedBy == 0 {
		return false
	}
	if trashedBy == a.principal.UserID {
		return true
	}
	if originalPath != "" && a.Level(serial, originalPath) >= Read {
		return true
	}
	return a.Level(serial, storageutil.TrashPath(trashName, "")) >= Read
}

// CanDeleteTrash reports whether the principal may delete a trashed item for
// good: they trashed it, they can write the folder it came from, or they are
// an admin (#1905).
func (a Access) CanDeleteTrash(serial, originalPath string, trashedBy int64) bool {
	if a.principal.IsAdmin {
		return true
	}
	if trashedBy != 0 && trashedBy == a.principal.UserID {
		return true
	}
	return originalPath != "" && a.Level(serial, path.Dir(Canonical(originalPath))) >= Write
}

// VisibleTrashParams filters a trash listing.
type VisibleTrashParams struct {
	Access       Access
	DeviceSerial string
	Items        []storageutil.TrashItem
}

// VisibleTrashResult is the trash the principal may see.
type VisibleTrashResult struct {
	Items []storageutil.TrashItem
}

// VisibleTrash keeps the trash items CanSeeTrash shows. It never returns a nil
// slice, so an empty listing serializes as [].
func VisibleTrash(params VisibleTrashParams) VisibleTrashResult {
	kept := make([]storageutil.TrashItem, 0, len(params.Items))
	for _, item := range params.Items {
		if params.Access.CanSeeTrash(params.DeviceSerial, item.TrashName, item.OriginalPath, item.TrashedBy) {
			kept = append(kept, item)
		}
	}
	return VisibleTrashResult{Items: kept}
}

// CanSeeJob reports whether a job is shown to the principal (#1979). An admin
// sees every job. Anyone else sees only a job they queued, and only while they
// can still read the file it works on. A job with no creator is admin-only.
func (a Access) CanSeeJob(job jobutil.Job) bool {
	if a.principal.IsAdmin {
		return true
	}
	if job.UserID == 0 || job.UserID != a.principal.UserID {
		return false
	}
	serial, relPath := job.Source()
	return relPath == "" || a.Check(serial, relPath, Read).Readable
}

// RedactJob is a job as the principal is shown it. Only an admin sees its
// Error, which can hold host paths and ffmpeg output.
func (a Access) RedactJob(job jobutil.Job) jobutil.Job {
	if !a.principal.IsAdmin {
		job.Error = ""
	}
	return job
}

// VisibleJobsParams filters a job listing.
type VisibleJobsParams struct {
	Access Access
	Jobs   []jobutil.Job
}

// VisibleJobsResult is the jobs the principal may see.
type VisibleJobsResult struct {
	Jobs []jobutil.Job
}

// VisibleJobs keeps the jobs CanSeeJob shows, each through RedactJob. It never
// returns a nil slice, so an empty listing serializes as [].
func VisibleJobs(params VisibleJobsParams) VisibleJobsResult {
	kept := make([]jobutil.Job, 0, len(params.Jobs))
	for _, job := range params.Jobs {
		if params.Access.CanSeeJob(job) {
			kept = append(kept, params.Access.RedactJob(job))
		}
	}
	return VisibleJobsResult{Jobs: kept}
}

// ErrCreatorInactive reports a job whose creator's account was deleted or is
// no longer active, so the job can't run as them.
var ErrCreatorInactive = errors.New("the account that queued this job can no longer sign in")

// LoadCreatorParams loads the access a job runs with.
type LoadCreatorParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	Storage  *storageutil.StorageService
	// UserID is the job's creator, 0 for none.
	UserID int64
}

// LoadCreator loads the access of the account that queued a job, with its
// status and role as they are now, since a job always runs as its creator,
// whoever retried it. A job with no creator runs as System. A creator whose
// account is gone or not active gets ErrCreatorInactive.
func LoadCreator(params LoadCreatorParams) (LoadResult, error) {
	if params.UserID == 0 {
		return Load(LoadParams{Ctx: params.Ctx, Principal: System})
	}
	if params.Database == nil {
		return LoadResult{}, ErrNoDatabase
	}
	user, err := params.Database.Queries.GetUserByID(params.Ctx, params.UserID)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && user.Status != authutil.StatusActive) {
		return LoadResult{}, ErrCreatorInactive
	}
	if err != nil {
		return LoadResult{}, err
	}
	return Load(LoadParams{
		Ctx:       params.Ctx,
		Database:  params.Database,
		Storage:   params.Storage,
		Principal: Principal{UserID: user.ID, IsAdmin: user.IsAdmin != 0},
	})
}

// ParseLevel reads a level's spelling, as the path_access table stores it and
// the sharing API accepts it. Anything else is None.
func ParseLevel(s string) Level {
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

// The sharing sentinels' text is written for the app to show, so handlers send
// it out unwrapped (#1911).
var (
	// ErrShareNotFound reports a path the caller can't read, so they may not
	// learn whether it exists.
	ErrShareNotFound = errors.New("no file or folder is at that path")
	// ErrShareForbidden reports a caller who can read a path but doesn't own it.
	ErrShareForbidden = errors.New("only the owner or an admin can change sharing")
	// ErrTrashShare reports a path in the trash.
	ErrTrashShare = errors.New("items in the trash can't be shared")
	// ErrSelfOwner reports a non-admin changing or removing their own owner
	// row, which could lock them out.
	ErrSelfOwner = errors.New("you can't remove your own ownership; ask another owner or an admin")
	// ErrInheritedGrant reports removing access that only a parent folder
	// gives.
	ErrInheritedGrant = errors.New("that access comes from a parent folder; change it there")
	// ErrGrantNotFound reports removing access nobody granted.
	ErrGrantNotFound = errors.New("that account or group doesn't have access to this item")
	// ErrGrantTarget reports a grant naming no principal, or both kinds.
	ErrGrantTarget = errors.New("choose one account or group")
	// ErrPrincipalNotFound reports a grant to an account that is missing or not
	// active, or to a group that doesn't exist.
	ErrPrincipalNotFound = errors.New("no active account or group has that id")
	// ErrInvalidLevel reports a level other than read, write or owner.
	ErrInvalidLevel = errors.New("access is read, write or owner")
)

// Grant is one principal's access to a path, as the sharing sheet shows it.
type Grant struct {
	// UserID is set for a grant to an account.
	UserID int64 `json:"userId,omitempty"`
	// GroupID is set for a grant to a group.
	GroupID int64 `json:"groupId,omitempty"`
	// Name is the account's username or the group's name.
	Name string `json:"name"`
	// Builtin marks the everyone group.
	Builtin bool `json:"builtin"`
	// Level is read, write or owner.
	Level string `json:"level"`
	// From is the path the row is on. A grant whose From is not the path
	// asked about is inherited from that folder, and is changed there.
	From string `json:"from"`
}

// GrantsResult is who may reach a path, for a caller who manages its sharing.
type GrantsResult struct {
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
	// CanManage is whether the caller may change the grants. Only a caller who
	// may manage sees them at all, so it is true in every result.
	CanManage bool `json:"canManage"`
	// CanGrantOwner is whether the caller may grant, change or revoke owner.
	// Every owner may, so it equals CanManage.
	CanGrantOwner bool `json:"canGrantOwner"`
	// Grants lists the rows on the path, then one inherited grant per principal
	// holding the highest level any parent folder gives it.
	Grants []Grant `json:"grants"`
}

// ListGrantsParams asks who may reach a path.
type ListGrantsParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// Access is the caller's access as loaded for the request.
	Access       Access
	DeviceSerial string
	Path         string
}

// ListGrants lists a path's grants for an owner of it or an admin. A caller who
// can't read the path gets ErrShareNotFound, one who can but doesn't own it
// ErrShareForbidden, and a path in the trash ErrTrashShare.
func ListGrants(params ListGrantsParams) (GrantsResult, error) {
	if params.Database == nil {
		return GrantsResult{}, ErrNoDatabase
	}
	rel, err := shareablePath(params.Access, params.DeviceSerial, params.Path)
	if err != nil {
		return GrantsResult{}, err
	}
	rows, err := params.Database.Queries.ListPathAccessOnAncestors(params.Ctx, db.ListPathAccessOnAncestorsParams{
		DeviceSerial: params.DeviceSerial,
		RelPath:      rel,
	})
	if err != nil {
		return GrantsResult{}, err
	}
	return GrantsResult{
		DeviceSerial:  params.DeviceSerial,
		RelPath:       rel,
		CanManage:     true,
		CanGrantOwner: true,
		Grants:        grantsFromRows(rows, rel),
	}, nil
}

// SetGrantParams grants one principal a level on a path. Exactly one of UserID
// and GroupID is set.
type SetGrantParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears access_changed for the path. Nil skips it.
	EventBus *eventbus.Bus
	// Access is the caller's access as loaded for the request.
	Access       Access
	DeviceSerial string
	Path         string
	UserID       int64
	GroupID      int64
	Level        Level
}

// SetGrant adds or changes a principal's row on a path and returns the path's
// grants as they now stand. It answers to the same callers ListGrants does, and
// any of them may grant owner. A non-admin may not change their own owner row
// on the path (ErrSelfOwner). The account must be active and the group must
// exist; a grant a parent folder already covers is still recorded.
func SetGrant(params SetGrantParams) (GrantsResult, error) {
	if (params.UserID == 0) == (params.GroupID == 0) {
		return GrantsResult{}, ErrGrantTarget
	}
	if params.Level < Read || params.Level > Owner {
		return GrantsResult{}, ErrInvalidLevel
	}
	if params.Database == nil {
		return GrantsResult{}, ErrNoDatabase
	}
	rel, err := shareablePath(params.Access, params.DeviceSerial, params.Path)
	if err != nil {
		return GrantsResult{}, err
	}
	queries := params.Database.Queries
	if err := ensurePrincipal(params.Ctx, queries, params.UserID, params.GroupID); err != nil {
		return GrantsResult{}, err
	}
	if params.Level != Owner {
		if err := ensureNotSelfOwner(params.Ctx, queries, params.Access.principal, params.DeviceSerial, rel, params.UserID); err != nil {
			return GrantsResult{}, err
		}
	}

	if params.UserID != 0 {
		err = queries.SetUserPathAccess(params.Ctx, db.SetUserPathAccessParams{
			DeviceSerial: params.DeviceSerial,
			RelPath:      rel,
			UserID:       sql.NullInt64{Int64: params.UserID, Valid: true},
			Level:        params.Level.String(),
		})
	} else {
		err = queries.SetGroupPathAccess(params.Ctx, db.SetGroupPathAccessParams{
			DeviceSerial: params.DeviceSerial,
			RelPath:      rel,
			GroupID:      sql.NullInt64{Int64: params.GroupID, Valid: true},
			Level:        params.Level.String(),
		})
	}
	if err != nil {
		return GrantsResult{}, err
	}
	publishAccessChanged(params.EventBus, params.DeviceSerial, rel)
	return ListGrants(ListGrantsParams{Ctx: params.Ctx, Database: params.Database, Access: params.Access, DeviceSerial: params.DeviceSerial, Path: rel})
}

// RevokeGrantParams removes one principal's row on a path. Exactly one of
// UserID and GroupID is set.
type RevokeGrantParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears access_changed for the path. Nil skips it.
	EventBus *eventbus.Bus
	// Access is the caller's access as loaded for the request.
	Access       Access
	DeviceSerial string
	Path         string
	UserID       int64
	GroupID      int64
}

// RevokeGrant removes a principal's row on a path and returns the path's grants
// as they now stand. It answers to the same callers ListGrants does. Access a
// parent folder gives can't be removed on the path (ErrInheritedGrant), a
// principal with no access at all is ErrGrantNotFound, and a non-admin may not
// remove their own owner row (ErrSelfOwner). An admin or another owner may
// remove the last owner row.
func RevokeGrant(params RevokeGrantParams) (GrantsResult, error) {
	if (params.UserID == 0) == (params.GroupID == 0) {
		return GrantsResult{}, ErrGrantTarget
	}
	if params.Database == nil {
		return GrantsResult{}, ErrNoDatabase
	}
	rel, err := shareablePath(params.Access, params.DeviceSerial, params.Path)
	if err != nil {
		return GrantsResult{}, err
	}
	queries := params.Database.Queries
	if err := ensureNotSelfOwner(params.Ctx, queries, params.Access.principal, params.DeviceSerial, rel, params.UserID); err != nil {
		return GrantsResult{}, err
	}

	var deleted int64
	if params.UserID != 0 {
		deleted, err = queries.DeleteUserPathAccess(params.Ctx, db.DeleteUserPathAccessParams{
			UserID:       sql.NullInt64{Int64: params.UserID, Valid: true},
			DeviceSerial: params.DeviceSerial,
			RelPath:      rel,
		})
	} else {
		deleted, err = queries.DeleteGroupPathAccess(params.Ctx, db.DeleteGroupPathAccessParams{
			GroupID:      sql.NullInt64{Int64: params.GroupID, Valid: true},
			DeviceSerial: params.DeviceSerial,
			RelPath:      rel,
		})
	}
	if err != nil {
		return GrantsResult{}, err
	}
	if deleted == 0 {
		result, err := ListGrants(ListGrantsParams{Ctx: params.Ctx, Database: params.Database, Access: params.Access, DeviceSerial: params.DeviceSerial, Path: rel})
		if err != nil {
			return GrantsResult{}, err
		}
		for _, grant := range result.Grants {
			if grant.UserID == params.UserID && grant.GroupID == params.GroupID {
				return GrantsResult{}, ErrInheritedGrant
			}
		}
		return GrantsResult{}, ErrGrantNotFound
	}
	publishAccessChanged(params.EventBus, params.DeviceSerial, rel)
	return ListGrants(ListGrantsParams{Ctx: params.Ctx, Database: params.Database, Access: params.Access, DeviceSerial: params.DeviceSerial, Path: rel})
}

// PrincipalUser is an account something can be shared with.
type PrincipalUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

// PrincipalGroup is a group something can be shared with.
type PrincipalGroup struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	// Builtin marks the everyone group.
	Builtin bool `json:"builtin"`
}

// ListPrincipalsParams asks who something can be shared with.
type ListPrincipalsParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
}

// ListPrincipalsResult is every active account by username and every group,
// everyone first. Neither slice is nil.
type ListPrincipalsResult struct {
	Users  []PrincipalUser  `json:"users"`
	Groups []PrincipalGroup `json:"groups"`
}

// ListPrincipals lists who something can be shared with (#1911). Any signed-in
// account may ask, so it carries names only: no status, role or membership.
func ListPrincipals(params ListPrincipalsParams) (ListPrincipalsResult, error) {
	if params.Database == nil {
		return ListPrincipalsResult{}, ErrNoDatabase
	}
	users, err := params.Database.Queries.ListActiveUsers(params.Ctx)
	if err != nil {
		return ListPrincipalsResult{}, err
	}
	groups, err := params.Database.Queries.ListGroups(params.Ctx)
	if err != nil {
		return ListPrincipalsResult{}, err
	}
	result := ListPrincipalsResult{
		Users:  make([]PrincipalUser, 0, len(users)),
		Groups: make([]PrincipalGroup, 0, len(groups)),
	}
	for _, user := range users {
		result.Users = append(result.Users, PrincipalUser{ID: user.ID, Username: user.Username})
	}
	for _, group := range groups {
		result.Groups = append(result.Groups, PrincipalGroup{ID: group.ID, Name: group.Name, Builtin: group.Builtin != 0})
	}
	return result, nil
}

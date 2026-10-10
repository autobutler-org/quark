// Package trashutil is the trash as the API and the delete path use it: every
// operation resolves the device's namespace from the VFS registry and goes
// through its [vfs.Trasher], then publishes what changed on the event bus with
// the device's serial (#2641). Access, favorite and album rows stay with the
// callers.
package trashutil

import (
	"context"
	"errors"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ErrNoTrash reports a namespace that has no trash: one that does not
// implement [vfs.Trasher].
var ErrNoTrash = errors.New("this storage has no trash")

// Device names the device whose trash an operation addresses. An unknown
// serial is storageutil.ErrDeviceNotFound.
type Device struct {
	// Ctx is the operation's context; nil is context.Background().
	Ctx context.Context
	// Registry resolves the device's namespace, [vfs.FilesNamespace](Serial).
	// Nil holds no namespaces, so every device is not found.
	Registry vfs.Registry
	// Serial names the device, empty for the internal one.
	Serial string
}

// TrashParams moves files to a device's trash.
type TrashParams struct {
	Device
	// RootDir is the directory Paths are relative to.
	RootDir string
	Paths   []string
	// TrashedBy is the user trashing the files (#1905).
	TrashedBy int64
}

// TrashResult lists what was moved into the trash. When Trash fails partway
// it still lists what was moved before the failure.
type TrashResult struct {
	Trashed []vfs.TrashedItem
}

// Trash moves files into the device's trash. It publishes nothing: the caller
// knows which deletes to announce.
func Trash(params TrashParams) (TrashResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return TrashResult{}, err
	}
	trashed, err := trasher.Trash(ctxOf(params.Device), params.Paths, vfs.TrashOptions{
		RootDir:   params.RootDir,
		TrashedBy: params.TrashedBy,
	})
	return TrashResult{Trashed: trashed}, err
}

// ListParams lists a device's trash.
type ListParams struct {
	Device
}

// ListResult is the device's trash, most recently trashed first.
type ListResult struct {
	Items []vfs.TrashItem
}

// List returns everything in the device's trash.
func List(params ListParams) (ListResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return ListResult{}, err
	}
	items, err := trasher.ListTrash(ctxOf(params.Device))
	return ListResult{Items: items}, err
}

// ReadEntryParams names one trashed item.
type ReadEntryParams struct {
	Device
	TrashName string
}

// ReadEntryResult is what the trash recorded about the item; the zero entry
// when its record is missing.
type ReadEntryResult struct {
	Entry vfs.TrashEntry
}

// ReadEntry reads one trashed item's record, so a caller can decide who may
// act on it before anything is touched (#1905).
func ReadEntry(params ReadEntryParams) (ReadEntryResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return ReadEntryResult{}, err
	}
	entry, err := trasher.ReadTrashEntry(ctxOf(params.Device), params.TrashName)
	return ReadEntryResult{Entry: entry}, err
}

// ListContentsParams names a folder in a device's trash.
type ListContentsParams struct {
	Device
	Ref vfs.TrashRef
}

// ListContentsResult is what the folder holds, where it would be restored to,
// and when the trashed item expires.
type ListContentsResult struct {
	Contents vfs.TrashContents
}

// ListContents lists a trashed folder, or a folder inside one.
func ListContents(params ListContentsParams) (ListContentsResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return ListContentsResult{}, err
	}
	contents, err := trasher.ListTrashContents(ctxOf(params.Device), params.Ref)
	return ListContentsResult{Contents: contents}, err
}

// RestoreParams names trashed items to put back.
type RestoreParams struct {
	Device
	Items []vfs.TrashRef
	// EventBus hears upload (a file) or new_folder (a folder) for each
	// restored item, then trash_changed. Nil skips them.
	EventBus *eventbus.Bus
}

// RestoreResult lists what was restored. When Restore fails partway it still
// lists what made it back before the failure.
type RestoreResult struct {
	Restored []vfs.RestoredItem
}

// Restore moves trashed items back to where they came from.
func Restore(params RestoreParams) (RestoreResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return RestoreResult{}, err
	}
	restored, err := trasher.RestoreTrash(ctxOf(params.Device), params.Items)
	publishRestored(params.EventBus, params.Serial, restored)
	return RestoreResult{Restored: restored}, err
}

// DeleteParams names trashed items to delete for good.
type DeleteParams struct {
	Device
	Items []vfs.TrashRef
	// EventBus hears trash_changed once anything is deleted. Nil skips it.
	EventBus *eventbus.Bus
}

// DeleteResult counts the items deleted and lists each as a TrashPath, so what
// was keyed on it can go too. When the delete fails partway it still lists
// what went.
type DeleteResult struct {
	Deleted int
	Removed []string
}

// Delete permanently deletes the named items from the device's trash.
func Delete(params DeleteParams) (DeleteResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return DeleteResult{}, err
	}
	removed, err := trasher.DeleteTrash(ctxOf(params.Device), params.Items)
	publishTrashChanged(params.EventBus, params.Serial, len(removed))
	return DeleteResult{Deleted: len(removed), Removed: removed}, err
}

// EmptyParams names the device whose trash to empty.
type EmptyParams struct {
	Device
	// EventBus hears trash_changed once anything is deleted. Nil skips it.
	EventBus *eventbus.Bus
}

// EmptyResult counts the items deleted and lists each as a TrashPath.
type EmptyResult struct {
	Deleted int
	Removed []string
}

// Empty permanently deletes everything in the device's trash.
func Empty(params EmptyParams) (EmptyResult, error) {
	trasher, err := trasherFor(params.Device)
	if err != nil {
		return EmptyResult{}, err
	}
	removed, err := trasher.EmptyTrash(ctxOf(params.Device))
	publishTrashChanged(params.EventBus, params.Serial, len(removed))
	return EmptyResult{Deleted: len(removed), Removed: removed}, err
}

// PurgeExpiredParams configures a sweep of every device's trash.
type PurgeExpiredParams struct {
	Ctx context.Context
	// Registry holds a namespace per device; every files namespace with a
	// trash is swept. Nil sweeps nothing.
	Registry vfs.Registry
	// EventBus hears trash_changed for each device that lost an item. Nil
	// skips it.
	EventBus *eventbus.Bus
	// Now is when the sweep runs; zero is time.Now().
	Now time.Time
}

// Removal is one item a sweep deleted.
type Removal struct {
	DeviceSerial string
	// Path is the item as a TrashPath.
	Path string
}

// PurgeExpiredResult counts and lists the items the sweep deleted.
type PurgeExpiredResult struct {
	Purged  int
	Removed []Removal
}

// PurgeExpired deletes the items whose retention ran out from the trash of
// every device. A device that fails does not stop the sweep; its error is
// joined into the one returned.
func PurgeExpired(params PurgeExpiredParams) (PurgeExpiredResult, error) {
	return purgeExpired(params)
}

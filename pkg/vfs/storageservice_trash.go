package vfs

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// trashFilesDir is filesDir for a trash operation. A device namespace whose
// device is gone is both [ErrNotFound] and storageutil.ErrDeviceNotFound, the
// error the trash has always answered an unplugged drive with.
func (v *StorageServiceVFS) trashFilesDir() (string, error) {
	filesDir, err := v.filesDir()
	if errors.Is(err, ErrNotFound) {
		return "", fmt.Errorf("%w: %w: %s", ErrNotFound, storageutil.ErrDeviceNotFound, v.serial)
	}
	return filesDir, err
}

// Trash moves paths into this device's trash. See [Trasher].
func (v *StorageServiceVFS) Trash(_ context.Context, paths []string, opts TrashOptions) ([]TrashedItem, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return nil, err
	}
	return hostTrash(filesDir, paths, opts)
}

// ListTrash lists this device's trash. See [Trasher].
func (v *StorageServiceVFS) ListTrash(_ context.Context) ([]TrashItem, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return nil, err
	}
	return hostListTrash(filesDir)
}

// ReadTrashEntry reads one item's record in this device's trash. See
// [Trasher].
func (v *StorageServiceVFS) ReadTrashEntry(_ context.Context, trashName string) (TrashEntry, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return TrashEntry{}, err
	}
	return hostReadTrashEntry(filesDir, trashName)
}

// ListTrashContents lists a folder in this device's trash. See [Trasher].
func (v *StorageServiceVFS) ListTrashContents(_ context.Context, ref TrashRef) (TrashContents, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return TrashContents{}, err
	}
	return hostListTrashContents(filesDir, ref)
}

// RestoreTrash puts items from this device's trash back. See [Trasher].
func (v *StorageServiceVFS) RestoreTrash(_ context.Context, refs []TrashRef) ([]RestoredItem, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return nil, err
	}
	return hostRestoreTrash(filesDir, refs)
}

// DeleteTrash deletes items from this device's trash for good. See [Trasher].
func (v *StorageServiceVFS) DeleteTrash(_ context.Context, refs []TrashRef) ([]string, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return nil, err
	}
	return hostDeleteTrash(filesDir, refs)
}

// EmptyTrash deletes everything in this device's trash. See [Trasher].
func (v *StorageServiceVFS) EmptyTrash(_ context.Context) ([]string, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return nil, err
	}
	return hostEmptyTrash(filesDir)
}

// PurgeExpiredTrash deletes the expired items in this device's trash. See
// [Trasher].
func (v *StorageServiceVFS) PurgeExpiredTrash(_ context.Context, now time.Time) ([]string, error) {
	filesDir, err := v.trashFilesDir()
	if err != nil {
		return nil, err
	}
	return hostPurgeExpiredTrash(filesDir, now)
}

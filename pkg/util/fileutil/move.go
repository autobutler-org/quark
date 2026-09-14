package fileutil

import (
	"context"
	"log"
	"path"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// MoveFileParams moves or renames a file.
type MoveFileParams struct {
	// Ctx bounds the VFS move.
	Ctx context.Context
	// Registry moves through the VFS for a same-device rename.
	Registry vfs.Registry
	// Storage moves the file when a device serial routes past the VFS.
	Storage *storageutil.StorageService
	// EventBus is told where the file went.
	EventBus *eventbus.Bus
	// Database holds the favorites and album items that follow the file. Nil
	// skips that half.
	Database *db.DatabaseSqlc
	// OldFilePath and NewFilePath are the paths moved between.
	OldFilePath string
	NewFilePath string
	// OldDeviceSerial and NewDeviceSerial name the devices, empty for the
	// internal one. Either one set makes this a cross-device move.
	OldDeviceSerial string
	NewDeviceSerial string
}

// MoveFileResult reports a completed move.
type MoveFileResult struct{}

// MoveFile moves a file and announces where it went.
func MoveFile(params MoveFileParams) (MoveFileResult, error) {
	// Use VFS.Move for same-device renames (no serials); fall through to StorageService for cross-device ops.
	moved := false
	if params.OldDeviceSerial == "" && params.NewDeviceSerial == "" {
		if fsys := FilesVFS(params.Registry); fsys != nil {
			if err := fsys.Move(params.Ctx, params.OldFilePath, params.NewFilePath); err != nil {
				return MoveFileResult{}, err
			}
			moved = true
		}
	}

	if !moved {
		if _, err := params.Storage.MoveFile(storageutil.MoveFileParams{
			OldFilePath:     params.OldFilePath,
			NewFilePath:     params.NewFilePath,
			OldDeviceSerial: params.OldDeviceSerial,
			NewDeviceSerial: params.NewDeviceSerial,
		}); err != nil {
			return MoveFileResult{}, err
		}
	}

	// The file has already moved, so a failure here is logged rather than
	// reported as a failed move; the request's cancellation must not stop it.
	if params.Database != nil {
		if err := movePhotoRows(context.WithoutCancel(params.Ctx), params.Database.Queries,
			params.OldDeviceSerial, params.OldFilePath, params.NewDeviceSerial, params.NewFilePath); err != nil {
			log.Printf("quark: move cleanup: carry favorites and album items from %q to %q: %v",
				params.OldFilePath, params.NewFilePath, err)
		}
	}

	// The serial lets each event stream subscriber check both paths against
	// the device they are on (#1906), and lets the file and content indexes
	// update that device rather than the internal one.
	params.EventBus.Publish(eventbus.Event{
		Kind:         eventbus.EventMove,
		Path:         params.OldFilePath,
		NewPath:      params.NewFilePath,
		DeviceSerial: params.NewDeviceSerial,
	})

	// Access rows follow the file, announced after the move they belong to
	// (#1905). Logged, not returned, for the same reason as the photo rows.
	if _, err := accessutil.MoveRows(accessutil.MoveRowsParams{
		Ctx:       context.WithoutCancel(params.Ctx),
		Database:  params.Database,
		EventBus:  params.EventBus,
		OldSerial: params.OldDeviceSerial,
		OldPath:   params.OldFilePath,
		NewSerial: params.NewDeviceSerial,
		NewPath:   params.NewFilePath,
	}); err != nil {
		log.Printf("quark: move cleanup: carry access rows from %q to %q: %v",
			params.OldFilePath, params.NewFilePath, err)
	}
	return MoveFileResult{}, nil
}

// CreateFolderParams creates one folder under an existing directory.
type CreateFolderParams struct {
	// Ctx bounds the VFS create.
	Ctx context.Context
	// Registry creates through the VFS when no serial routes past it.
	Registry vfs.Registry
	// Storage creates the folder for a device-scoped request.
	Storage *storageutil.StorageService
	// EventBus is told about the new folder.
	EventBus *eventbus.Bus
	// FolderDir is the directory the folder is created in.
	FolderDir string
	// FolderName is the new folder's name.
	FolderName string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// CreateFolderResult reports a created folder.
type CreateFolderResult struct {
	// Path is the folder, files-relative.
	Path string
	// Created is false when the folder was already there, which creating it
	// again does not treat as an error.
	Created bool
}

// CreateFolder creates a folder and announces it.
func CreateFolder(params CreateFolderParams) (CreateFolderResult, error) {
	folderPath := path.Join(params.FolderDir, params.FolderName)
	existed, err := fileExists(params.Ctx, params.Registry, params.Storage, params.Serial, folderPath)
	if err != nil {
		return CreateFolderResult{}, err
	}

	// Use VFS.MkdirAll for no-serial folder creation; fall back for device-scoped ops.
	created := false
	if params.Serial == "" {
		if fsys := FilesVFS(params.Registry); fsys != nil {
			if err := fsys.MkdirAll(params.Ctx, folderPath); err != nil {
				return CreateFolderResult{}, err
			}
			created = true
		}
	}

	if !created {
		if _, err := params.Storage.CreateFolder(storageutil.CreateFolderParams{
			FolderDir:    params.FolderDir,
			FolderName:   params.FolderName,
			DeviceSerial: params.Serial,
		}); err != nil {
			return CreateFolderResult{}, err
		}
	}

	params.EventBus.Publish(eventbus.Event{
		Kind: eventbus.EventNewFolder,
		Path: folderPath,
	})
	return CreateFolderResult{Path: folderPath, Created: !existed}, nil
}

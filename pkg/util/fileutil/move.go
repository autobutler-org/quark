package fileutil

import (
	"context"
	"errors"
	"fmt"
	"log"
	"path"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// MoveFileParams moves or renames a file.
type MoveFileParams struct {
	// Ctx bounds the move.
	Ctx context.Context
	// Registry holds the namespaces of the devices moved between.
	Registry vfs.Registry
	// EventBus is told where the file went.
	EventBus *eventbus.Bus
	// Database holds the favorites and album items that follow the file. Nil
	// skips that half.
	Database *db.DatabaseSqlc
	// OldFilePath and NewFilePath are the paths moved between.
	OldFilePath string
	NewFilePath string
	// OldDeviceSerial and NewDeviceSerial name the devices, empty for the
	// internal one. Two different serials make this a cross-device move.
	OldDeviceSerial string
	NewDeviceSerial string
}

// MoveFileResult reports a completed move.
type MoveFileResult struct{}

// MoveFile moves a file and announces where it went.
func MoveFile(params MoveFileParams) (MoveFileResult, error) {
	for _, p := range []string{params.OldFilePath, params.NewFilePath} {
		if climbsOut(p) {
			return MoveFileResult{}, invalidPath(p)
		}
	}
	if err := movePath(params); err != nil {
		return MoveFileResult{}, err
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
	// Ctx bounds the create.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
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
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return CreateFolderResult{}, err
	}
	existed, err := exists(params.Ctx, fsys, folderPath)
	if err != nil {
		return CreateFolderResult{}, err
	}
	if err := fsys.MkdirAll(params.Ctx, folderPath); err != nil {
		return CreateFolderResult{}, err
	}

	params.EventBus.Publish(eventbus.Event{
		Kind:         eventbus.EventNewFolder,
		Path:         folderPath,
		DeviceSerial: params.Serial,
	})
	return CreateFolderResult{Path: folderPath, Created: !existed}, nil
}

// movePath moves the file or folder itself: a rename within one device's
// namespace, or a copy and a delete between two.
func movePath(params MoveFileParams) error {
	src, err := FilesVFS(params.Registry, params.OldDeviceSerial)
	if err != nil {
		return err
	}
	if params.OldDeviceSerial == params.NewDeviceSerial {
		return src.Move(params.Ctx, params.OldFilePath, params.NewFilePath)
	}
	dst, err := FilesVFS(params.Registry, params.NewDeviceSerial)
	if err != nil {
		return err
	}
	return moveBetween(params.Ctx, src, params.OldFilePath, dst, params.NewFilePath)
}

// moveBetween moves srcPath in src to dstPath in dst, two devices a rename
// cannot cross. Every file goes over through [vfs.CopyBetween], which lands it
// under its name only once it is whole, and the source goes only after
// everything has been copied: a move that fails partway leaves the source as
// it was and no half-written file under the destination.
//
// A file replaces a file already at dstPath, as a rename does. A folder is
// refused with [vfs.ErrConflict] when dstPath is taken, where a rename onto a
// folder with anything in it fails too.
func moveBetween(ctx context.Context, src vfs.VFS, srcPath string, dst vfs.VFS, dstPath string) error {
	info, err := src.Stat(ctx, srcPath)
	if err != nil {
		return err
	}
	if info.IsDir {
		taken, err := exists(ctx, dst, dstPath)
		if err != nil {
			return err
		}
		if taken {
			return fmt.Errorf("%w: %s already exists", vfs.ErrConflict, dstPath)
		}
	}
	if parent := path.Dir(cleanRelPath(dstPath)); parent != "." {
		if err := dst.MkdirAll(ctx, parent); err != nil {
			return err
		}
	}
	if !info.IsDir {
		if err := vfs.CopyBetween(ctx, src, srcPath, dst, dstPath, vfs.CopyOptions{}); err != nil {
			return err
		}
		return src.Delete(ctx, srcPath, vfs.DeleteOptions{})
	}

	entries, err := src.List(ctx, srcPath, &vfs.ListFilter{Recursive: true})
	if err != nil {
		return err
	}
	if err := dst.MkdirAll(ctx, dstPath); err != nil {
		return err
	}
	base := cleanRelPath(srcPath)
	for _, entry := range entries {
		rel := strings.TrimPrefix(strings.TrimPrefix(entry.Path, base), "/")
		target := path.Join(dstPath, rel)
		if entry.IsDir {
			err = dst.MkdirAll(ctx, target)
		} else {
			err = vfs.CopyBetween(ctx, src, entry.Path, dst, target, vfs.CopyOptions{IfNoneMatch: "*"})
		}
		if err != nil {
			return fmt.Errorf("move %s: %w", entry.Path, err)
		}
	}
	return src.Delete(ctx, srcPath, vfs.DeleteOptions{Recursive: true})
}

// exists reports whether something occupies p in fsys.
func exists(ctx context.Context, fsys vfs.VFS, p string) (bool, error) {
	_, err := fsys.Stat(ctx, p)
	if errors.Is(err, vfs.ErrNotFound) {
		return false, nil
	}
	return err == nil, err
}

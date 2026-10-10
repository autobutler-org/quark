package uploadutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"path"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// FilesVFS returns the namespace holding the files of the device with this
// serial, the internal drive for the empty one (#2639), or nil when no such
// namespace is registered: the device is not attached, or the deployment has
// no registry.
func (d Destination) FilesVFS(serial string) vfs.VFS {
	if d.Registry == nil {
		return nil
	}
	fsys, ok := d.Registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		return nil
	}
	return fsys
}

// Writable reports whether an upload for this serial has anywhere to go. A
// session is worth opening only if the bytes it collects can eventually land.
func (d Destination) Writable(serial string) bool {
	return d.FilesVFS(serial) != nil
}

// WriteMultipartVFS streams every file part of a multipart body into the VFS
// namespace. Parts that are not files under the "files" form name are skipped,
// and each one is written straight from the wire — the body is never buffered.
// The caller publishes the upload event once, after the last part lands.
func WriteMultipartVFS(params WriteMultipartParams) (WriteMultipartResult, error) {
	var result WriteMultipartResult
	// Ensure the destination directory exists.
	if params.RootDir != "" {
		if err := params.FS.MkdirAll(params.Ctx, params.RootDir); err != nil {
			return result, err
		}
	}

	for {
		part, err := params.Reader.NextPart()
		if errors.Is(err, io.EOF) {
			return result, nil
		}
		if err != nil {
			return result, fmt.Errorf("%w: %w", ErrInvalidBody, err)
		}

		fileName := part.FileName()
		if part.FormName() != "files" || fileName == "" {
			if params.Sidecar != nil {
				params.Sidecar(part, result.Written)
			}
			part.Close()
			continue
		}

		// The client-supplied name never carries structure; rootDir does (#1603).
		opts := writeOptions(params.Overwrite)
		var created bool
		destPath, err := placeUnderFreeName(params.RootDir, filepath.Base(fileName), params.KeepBoth, func(p string) error {
			created = !params.Overwrite || !vfsExists(params.Ctx, params.FS, p)
			if !created && params.BeforeOverwrite != nil {
				params.BeforeOverwrite(p)
			}
			return params.FS.Write(params.Ctx, p, part, opts)
		})
		part.Close()
		if errors.Is(err, io.ErrUnexpectedEOF) {
			// The body ended inside the part: the client's connection, not
			// the disk. The atomic write left nothing under the name.
			return result, fmt.Errorf("%w: %w", ErrInvalidBody, err)
		}
		if err != nil {
			return result, err
		}
		result.Written = append(result.Written, UploadedFile{
			Path: destPath, Created: created, SourceName: filepath.Base(fileName),
		})
	}
}

// WriteFile streams one file into the destination and publishes the upload
// event the file index and the clients listen for.
func (d Destination) WriteFile(params WriteFileParams) (WriteFileResult, error) {
	// The client-supplied name never carries structure; rootDir does (#1603).
	fileName := filepath.Base(params.FileName)

	fsys := d.FilesVFS(params.Serial)
	if fsys == nil {
		return WriteFileResult{}, ErrNoDestination
	}
	written, err := writeToVFS(fsys, params, fileName)
	if err != nil {
		return WriteFileResult{}, err
	}

	if d.EventBus != nil {
		d.EventBus.Publish(eventbus.Event{
			Kind:         eventbus.EventUpload,
			Path:         params.RootDir,
			DeviceSerial: params.Serial,
		})
	}
	return WriteFileResult{Path: written.Path, Created: written.Created}, nil
}

// writeToVFS lands one file in fsys: moved in when it is already a host file
// and the namespace can take it by rename (#1828), streamed otherwise.
func writeToVFS(fsys vfs.VFS, params WriteFileParams, fileName string) (UploadedFile, error) {
	if params.RootDir != "" {
		if err := fsys.MkdirAll(params.Ctx, params.RootDir); err != nil {
			return UploadedFile{}, err
		}
	}
	opts := writeOptions(params.Overwrite)
	var created bool
	destPath, err := placeUnderFreeName(params.RootDir, fileName, params.KeepBoth, func(p string) error {
		created = !params.Overwrite || !vfsExists(params.Ctx, fsys, p)
		if mover, ok := fsys.(vfs.FileMover); ok && params.SourcePath != "" {
			return mover.MoveFileIn(params.Ctx, params.SourcePath, p, opts)
		}
		return fsys.Write(params.Ctx, p, params.Reader, opts)
	})
	return UploadedFile{Path: destPath, Created: created}, err
}

// vfsExists reports whether something occupies a path. Only a definite "not
// found" counts as absent: an upload that cannot tell is treated as replacing
// a file, which grants nothing, rather than creating one, which would.
func vfsExists(ctx context.Context, fsys vfs.VFS, p string) bool {
	_, err := fsys.Stat(ctx, p)
	return !errors.Is(err, vfs.ErrNotFound) && !errors.Is(err, fs.ErrNotExist)
}

// writeOptions is the precondition a write carries: without overwrite, a
// taken name is vfs.ErrConflict rather than a replaced file.
func writeOptions(overwrite bool) vfs.WriteOptions {
	if overwrite {
		return vfs.WriteOptions{}
	}
	return vfs.WriteOptions{IfNoneMatch: "*"}
}

// placeUnderFreeName calls place with dir/fileName and, when keepBoth is set
// and that name is taken, with each numbered name in turn until one is free.
// It returns the path place last tried. Every VFS reports a taken name before
// it reads anything, so retrying with the same reader is safe.
func placeUnderFreeName(dir, fileName string, keepBoth bool, place func(p string) error) (string, error) {
	for n := 0; ; n++ {
		p := path.Join(dir, storageutil.NumberedName(fileName, n))
		err := place(p)
		if !keepBoth || !errors.Is(err, vfs.ErrConflict) {
			return p, err
		}
	}
}

// taken reports whether a file already sits where an upload would land, so a
// session can be refused before its bytes are sent. Only a definite answer
// counts: an upload that cannot tell goes ahead, and the commit decides.
func (d Destination) taken(ctx context.Context, serial, rootDir, fileName string) bool {
	fsys := d.FilesVFS(serial)
	if fsys == nil {
		return false
	}
	_, err := fsys.Stat(ctx, path.Join(rootDir, fileName))
	return err == nil
}

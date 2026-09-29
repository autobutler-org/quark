package uploadutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"mime/multipart"
	"path"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// filesNamespace is the VFS namespace holding the local file store. Registered
// by deputil.DefaultDependencies; absent in older deployments and in tests that
// exercise the StorageService directly.
const filesNamespace = "files"

// errNothingWritten reports a storage upload that finished without writing the
// one file it was given.
var errNothingWritten = errors.New("uploadutil: the upload wrote no file")

// FilesVFS returns the VFS backing the local namespace, or nil when the write
// has to go through the StorageService instead: a named device serial routes
// past the VFS, and a deployment without the namespace has nothing to route to.
func (d Destination) FilesVFS(serial string) vfs.VFS {
	if serial != "" || d.Registry == nil {
		return nil
	}
	fsys, ok := d.Registry.Get(filesNamespace)
	if !ok {
		return nil
	}
	return fsys
}

// Writable reports whether an upload for this serial has anywhere to go. A
// session is worth opening only if the bytes it collects can eventually land.
func (d Destination) Writable(serial string) bool {
	return d.FilesVFS(serial) != nil || d.Storage != nil
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
		if err != nil {
			break // io.EOF or end of parts
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
			return params.FS.Write(params.Ctx, p, part, opts)
		})
		part.Close()
		if err != nil {
			return result, err
		}
		result.Written = append(result.Written, storageutil.UploadedFile{
			Path: destPath, Created: created, SourceName: filepath.Base(fileName),
		})
	}

	return result, nil
}

// WriteFile streams one file into the destination and publishes the upload
// event the file index and the clients listen for.
func (d Destination) WriteFile(params WriteFileParams) (WriteFileResult, error) {
	// The client-supplied name never carries structure; rootDir does (#1603).
	fileName := filepath.Base(params.FileName)

	var written storageutil.UploadedFile
	var err error
	if fsys := d.FilesVFS(params.Serial); fsys != nil {
		written, err = d.writeToVFS(fsys, params, fileName)
	} else {
		written, err = d.writeToStorageService(params, fileName)
	}
	if err != nil {
		return WriteFileResult{}, err
	}

	if d.EventBus != nil {
		d.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventUpload,
			Path: params.RootDir,
		})
	}
	return WriteFileResult{Path: written.Path, Created: written.Created}, nil
}

func (d Destination) writeToVFS(fsys vfs.VFS, params WriteFileParams, fileName string) (storageutil.UploadedFile, error) {
	if params.RootDir != "" {
		if err := fsys.MkdirAll(params.Ctx, params.RootDir); err != nil {
			return storageutil.UploadedFile{}, err
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
	return storageutil.UploadedFile{Path: destPath, Created: created}, err
}

// writeToStorageService replays the file through the same multipart-streaming
// path POST /files/upload uses, so device routing and name-conflict handling
// stay in one implementation instead of being copied here and
// drifting. The pipe keeps it streaming: only the copy buffer is ever in
// memory, which matters because this path exists for multi-gigabyte files.
func (d Destination) writeToStorageService(params WriteFileParams, fileName string) (storageutil.UploadedFile, error) {
	pr, pw := io.Pipe()
	mw := multipart.NewWriter(pw)

	go func() {
		part, err := mw.CreateFormFile("files", fileName)
		if err != nil {
			pw.CloseWithError(err)
			return
		}
		if _, err := io.Copy(part, params.Reader); err != nil {
			pw.CloseWithError(err)
			return
		}
		pw.CloseWithError(mw.Close())
	}()
	defer pr.Close()

	result, err := d.Storage.UploadFilesStreamed(storageutil.UploadFilesStreamedParams{
		Reader:       multipart.NewReader(pr, mw.Boundary()),
		RootDir:      params.RootDir,
		DeviceSerial: params.Serial,
		Overwrite:    params.Overwrite,
		KeepBoth:     params.KeepBoth,
	})
	if errors.Is(err, fs.ErrExist) {
		// One sentinel for a taken name, whichever writer found it.
		return storageutil.UploadedFile{}, fmt.Errorf("%w: %w", vfs.ErrConflict, err)
	}
	if err != nil {
		return storageutil.UploadedFile{}, err
	}
	// Keeping both may have landed the file as file_(1).ext, so the name the
	// storage service reports is the one the file really landed under.
	if len(result.Written) == 0 {
		return storageutil.UploadedFile{}, errNothingWritten
	}
	return result.Written[0], nil
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
	rel := path.Join(rootDir, fileName)
	if fsys := d.FilesVFS(serial); fsys != nil {
		_, err := fsys.Stat(ctx, rel)
		return err == nil
	}
	if d.Storage == nil {
		return false
	}
	_, err := d.Storage.StatFile(storageutil.StatFileParams{FilePath: rel, DeviceSerial: serial})
	return err == nil
}

package uploadutil

import (
	"io"
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
func WriteMultipartVFS(params WriteMultipartParams) error {
	// Ensure the destination directory exists.
	if params.RootDir != "" {
		if err := params.FS.MkdirAll(params.Ctx, params.RootDir); err != nil {
			return err
		}
	}

	for {
		part, err := params.Reader.NextPart()
		if err != nil {
			break // io.EOF or end of parts
		}

		fileName := part.FileName()
		if part.FormName() != "files" || fileName == "" {
			part.Close()
			continue
		}

		// The client-supplied name never carries structure; rootDir does (#1603).
		destPath := path.Join(params.RootDir, filepath.Base(fileName))
		opts := vfs.WriteOptions{}
		if !params.Overwrite {
			opts.IfNoneMatch = "*"
		}

		if err := params.FS.Write(params.Ctx, destPath, part, opts); err != nil {
			part.Close()
			return err
		}
		part.Close()
	}

	return nil
}

// WriteFile streams one file into the destination and publishes the upload
// event the file index and the clients listen for.
func (d Destination) WriteFile(params WriteFileParams) (WriteFileResult, error) {
	// The client-supplied name never carries structure; rootDir does (#1603).
	fileName := filepath.Base(params.FileName)

	if fsys := d.FilesVFS(params.Serial); fsys != nil {
		if err := d.writeToVFS(fsys, params, fileName); err != nil {
			return WriteFileResult{}, err
		}
	} else if err := d.writeToStorageService(params, fileName); err != nil {
		return WriteFileResult{}, err
	}

	if d.EventBus != nil {
		d.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventUpload,
			Path: params.RootDir,
		})
	}
	return WriteFileResult{Path: path.Join(params.RootDir, fileName)}, nil
}

func (d Destination) writeToVFS(fsys vfs.VFS, params WriteFileParams, fileName string) error {
	if params.RootDir != "" {
		if err := fsys.MkdirAll(params.Ctx, params.RootDir); err != nil {
			return err
		}
	}
	opts := vfs.WriteOptions{}
	if !params.Overwrite {
		// vfs.ErrConflict comes back when the file already exists, which the
		// HTTP layer reports as a 400 the way the multipart endpoint does.
		opts.IfNoneMatch = "*"
	}
	destPath := path.Join(params.RootDir, fileName)
	if mover, ok := fsys.(vfs.FileMover); ok && params.SourcePath != "" {
		return mover.MoveFileIn(params.Ctx, params.SourcePath, destPath, opts)
	}
	return fsys.Write(params.Ctx, destPath, params.Reader, opts)
}

// writeToStorageService replays the file through the same multipart-streaming
// path POST /files/upload uses, so device routing and name-conflict handling
// (file_(1).ext) stay in one implementation instead of being copied here and
// drifting. The pipe keeps it streaming: only the copy buffer is ever in
// memory, which matters because this path exists for multi-gigabyte files.
func (d Destination) writeToStorageService(params WriteFileParams, fileName string) error {
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

	return d.Storage.UploadFilesStreamed(storageutil.UploadFilesStreamedParams{
		Reader:       multipart.NewReader(pr, mw.Boundary()),
		RootDir:      params.RootDir,
		DeviceSerial: params.Serial,
		Overwrite:    params.Overwrite,
	})
}

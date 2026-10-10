package fileutil

import (
	"archive/zip"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	// Registers the HEIC decoder with image.Decode.
	_ "github.com/gen2brain/heic"
	// Register the BMP, TIFF and WebP decoders with image.Decode.
	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/tiff"
	_ "golang.org/x/image/webp"
)

// jpegQuality is the encoder quality every download-time conversion uses.
const jpegQuality = 92

// DownloadKind says how a download has to be answered: the source decides,
// the handler writes.
type DownloadKind string

const (
	// DownloadFolder zips a directory and streams the archive.
	DownloadFolder DownloadKind = "folder"
	// DownloadRawJPEG converts a camera RAW file to JPEG in memory.
	DownloadRawJPEG DownloadKind = "raw-jpeg"
	// DownloadJPEG decodes the source image and re-encodes it as JPEG.
	DownloadJPEG DownloadKind = "jpeg"
	// DownloadContents serves the file as it is on disk.
	DownloadContents DownloadKind = "contents"
)

// OpenVFSDownloadParams resolves a download against one device's files
// namespace.
type OpenVFSDownloadParams struct {
	// Ctx bounds the stat.
	Ctx context.Context
	// FS is the files namespace of the device the request names.
	FS vfs.VFS
	// FilePath is the requested path inside the namespace.
	FilePath string
	// WantsJPEG asks for an image to come back as JPEG.
	WantsJPEG bool
}

// OpenVFSDownloadResult is a resolved VFS download. The stream itself is
// opened by the caller, which for a conversion happens after the IO semaphore
// is in hand.
type OpenVFSDownloadResult struct {
	// Kind says how the response is produced.
	Kind DownloadKind
	// Info is the stat the response headers are built from.
	Info vfs.FileInfo
	// FileName is the name the client is offered in Content-Disposition.
	FileName string
	// ContentType is the type to serve, empty for a folder.
	ContentType string
	// HostPath is the file on the host, set for DownloadRawJPEG only: the
	// tool that extracts a RAW file's preview reads a path, not a stream.
	HostPath string
}

// OpenVFSDownload resolves a download through the VFS layer.
func OpenVFSDownload(params OpenVFSDownloadParams) (OpenVFSDownloadResult, error) {
	fi, err := params.FS.Stat(params.Ctx, params.FilePath)
	if err != nil {
		return OpenVFSDownloadResult{}, notFound(err)
	}

	if fi.IsDir {
		return OpenVFSDownloadResult{
			Kind:     DownloadFolder,
			Info:     fi,
			FileName: fi.Name + ".zip",
		}, nil
	}

	mimeType := fi.MimeType
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}

	if params.WantsJPEG && photoutil.IsRawFile(params.FilePath) {
		hp, ok := params.FS.(vfs.HostPather)
		if !ok {
			return OpenVFSDownloadResult{}, &UnsupportedError{Err: fmt.Errorf("cannot convert %s to JPEG here", fi.Name)}
		}
		hostPath, err := hp.HostPath(params.Ctx, params.FilePath)
		if err != nil {
			return OpenVFSDownloadResult{}, err
		}
		return OpenVFSDownloadResult{
			Kind:        DownloadRawJPEG,
			Info:        fi,
			FileName:    JPEGFileName(params.FilePath),
			ContentType: "image/jpeg",
			HostPath:    hostPath,
		}, nil
	}

	if params.WantsJPEG && strings.HasPrefix(mimeType, "image/") {
		return OpenVFSDownloadResult{
			Kind:        DownloadJPEG,
			Info:        fi,
			FileName:    JPEGFileName(params.FilePath),
			ContentType: "image/jpeg",
		}, nil
	}

	return OpenVFSDownloadResult{
		Kind:        DownloadContents,
		Info:        fi,
		FileName:    fi.Name,
		ContentType: mimeType,
	}, nil
}

// JPEGFileName is the name a converted image is offered under: the source name
// with its extension replaced by .jpg.
func JPEGFileName(filePath string) string {
	ext := strings.ToLower(filepath.Ext(filePath))
	return strings.TrimSuffix(filepath.Base(filePath), ext) + ".jpg"
}

// ZipVFSDir streams a zip of a VFS directory onto w. Entry paths are stored
// under a top-level folder named root, followed by the path relative to
// basePath, so the archive unpacks as the folder the client asked for rather
// than the whole path to it or its loose contents.
//
// Only entries access can read go in. The walk does not descend into a
// symlinked folder, but it does list a symlinked file, and opening it follows
// the link — so a link inside a shared folder would otherwise carry whatever
// it points at into the archive (#1903).
//
// Each entry is stored or deflated as ZipMethod says. Nothing is buffered
// beyond the zip writer's own: the archive goes onto w as it is built, and
// entries over 4 GiB, or archives past 65,535 entries, get zip64 records. The
// listing leaves out the names the storage layer keeps for itself
// (storageutil.IsInternalName), so they never reach the archive either.
func ZipVFSDir(ctx context.Context, fsys vfs.VFS, basePath string, root string, access accessutil.Access, w io.Writer) error {
	zipWriter := newFolderZipWriter(w)
	defer zipWriter.Close()
	buf := make([]byte, zipCopyBuffer)

	// fsys is one device's namespace, so Open and the listing agree on the
	// device. Listing every device put a file only on a USB drive in the
	// archive and then failed to open it, cutting the archive short (#2638).
	entries, err := fsys.List(ctx, basePath, &vfs.ListFilter{Recursive: true})
	if err != nil {
		return fmt.Errorf("failed to list folder: %w", err)
	}
	for _, entry := range entries {
		if entry.IsDir || !access.Check(entry.DeviceSerial, entry.Path, accessutil.Read).Readable {
			continue
		}
		r, err := fsys.Open(ctx, entry.Path)
		if err != nil {
			return fmt.Errorf("failed to open %s: %w", entry.Path, err)
		}
		// Compute a relative path inside the zip (trim the base filePath prefix).
		// Entry paths come back in the VFS's one form, so the base is
		// trimmed in that form too.
		rel := strings.TrimPrefix(entry.Path, accessutil.Canonical(basePath))
		rel = path.Join(root, strings.TrimPrefix(rel, "/"))
		zw, err := zipWriter.CreateHeader(&zip.FileHeader{
			Name:               rel,
			Method:             ZipMethod(entry.Name, entry.MimeType, entry.Size),
			Modified:           entry.ModTime,
			UncompressedSize64: uint64(max(entry.Size, 0)),
		})
		if err != nil {
			r.Close()
			return fmt.Errorf("failed to create zip entry %s: %w", rel, err)
		}
		if _, err := copyEntry(zw, r, buf); err != nil {
			r.Close()
			return fmt.Errorf("failed to write zip entry %s: %w", rel, err)
		}
		r.Close()
	}
	return nil
}

// WriteRawJPEG converts a camera RAW file to JPEG straight onto w by extracting its
// embedded preview.
func WriteRawJPEG(w io.Writer, fullPath string) error {
	if err := photoutil.WriteRawAsJPEG(w, fullPath, jpegQuality); err != nil {
		return fmt.Errorf("failed to convert RAW to JPEG: %w", err)
	}
	return nil
}

// DecodeImage decodes an image stream, refusing one over
// photoutil.MaxDecodePixels with photoutil.ErrImageTooLarge before decoding
// it. Importing this package registers the HEIC, BMP, TIFF and WebP decoders
// alongside the standard library's.
func DecodeImage(r io.Reader) (image.Image, error) {
	img, _, err := photoutil.DecodeImage(r)
	if err != nil {
		return nil, fmt.Errorf("failed to decode image: %w", err)
	}
	return img, nil
}

// EncodeJPEG writes img onto w as JPEG. It is called after the response
// headers are committed, so its error is only ever worth logging.
func EncodeJPEG(w io.Writer, img image.Image) error {
	return jpeg.Encode(w, img, &jpeg.Options{Quality: jpegQuality})
}

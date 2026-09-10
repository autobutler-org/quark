package fileutil

import (
	"archive/zip"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
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

// OpenDownloadParams resolves a download request against the StorageService,
// which is what serial routing and RAW conversion need: both want a real
// filesystem path.
type OpenDownloadParams struct {
	// Storage resolves the request path to a device and a full path.
	Storage *storageutil.StorageService
	// FilePath is the requested files-relative path.
	FilePath string
	// Serial routes the request to one device, empty for the internal one.
	Serial string
	// WantsJPEG asks for an image to come back as JPEG.
	WantsJPEG bool
}

// OpenDownloadResult is a resolved download: what to write, and the open
// source file to write it from.
type OpenDownloadResult struct {
	// Kind says how the response is produced.
	Kind DownloadKind
	// FullPath is the resolved path on disk.
	FullPath string
	// File is the opened source, nil for a folder. The caller closes it.
	File *os.File
	// FileName is the name the client is offered in Content-Disposition.
	FileName string
	// ContentType is the type to serve, set for DownloadContents.
	ContentType string
}

// OpenDownload resolves a download through the StorageService and opens the
// source file, so a missing file is reported before any bytes are written.
func OpenDownload(params OpenDownloadParams) (OpenDownloadResult, error) {
	resolved, err := params.Storage.DownloadFile(storageutil.DownloadFileParams{
		FilePath:     params.FilePath,
		DeviceSerial: params.Serial,
	})
	if err != nil {
		return OpenDownloadResult{}, notFound(err)
	}

	if resolved.IsFolder {
		return OpenDownloadResult{
			Kind:     DownloadFolder,
			FullPath: resolved.FullPath,
			FileName: filepath.Base(resolved.FullPath) + ".zip",
		}, nil
	}

	f, err := os.Open(resolved.FullPath)
	if err != nil {
		if os.IsNotExist(err) {
			return OpenDownloadResult{}, notFoundf("file not found: %s", params.FilePath)
		}
		return OpenDownloadResult{}, fmt.Errorf("failed to open file: %w", err)
	}

	if params.WantsJPEG && resolved.FileType == storageutil.FileTypeImage {
		// RAW files carry a JPEG preview an external tool extracts; everything
		// else is decoded and re-encoded from the file already open here.
		kind := DownloadJPEG
		if photoutil.IsRawFile(resolved.FullPath) {
			kind = DownloadRawJPEG
		}
		return OpenDownloadResult{
			Kind:     kind,
			FullPath: resolved.FullPath,
			File:     f,
			FileName: JPEGFileName(resolved.FullPath),
		}, nil
	}

	return OpenDownloadResult{
		Kind:        DownloadContents,
		FullPath:    resolved.FullPath,
		File:        f,
		FileName:    filepath.Base(resolved.FullPath),
		ContentType: downloadContentType(resolved.FileType, filepath.Ext(resolved.FullPath)),
	}, nil
}

// OpenVFSDownloadParams resolves a download against the VFS namespace. RAW
// files are excluded before this is called: their conversion needs an OS path.
type OpenVFSDownloadParams struct {
	// Ctx bounds the stat.
	Ctx context.Context
	// FS is the files namespace.
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

// downloadContentType is the type a file is served as, which for the media
// types is derived from the extension rather than sniffed.
func downloadContentType(fileType storageutil.FileType, ext string) string {
	switch fileType {
	case storageutil.FileTypePDF:
		return "application/pdf"
	case storageutil.FileTypeImage, storageutil.FileTypeSvg:
		return storageutil.ImageMIMETypeFromExtension(ext)
	case storageutil.FileTypeVideo:
		return storageutil.VideoMIMETypeFromExtension(ext)
	case storageutil.FileTypeAudio:
		return storageutil.AudioMIMETypeFromExtension(ext)
	}
	return "application/octet-stream"
}

// ZipDir streams a zip of the directory at fullPath onto w.
func ZipDir(w io.Writer, fullPath string) error {
	zipWriter := zip.NewWriter(w)
	defer zipWriter.Close()
	if err := zipWriter.AddFS(os.DirFS(fullPath)); err != nil {
		return fmt.Errorf("failed to zip folder: %w", err)
	}
	return nil
}

// ZipVFSDir streams a zip of a VFS directory onto w. Entry paths are stored
// relative to basePath, so the archive unpacks as the folder the client asked
// for rather than the whole path to it.
func ZipVFSDir(ctx context.Context, fsys vfs.VFS, basePath string, w io.Writer) error {
	zipWriter := zip.NewWriter(w)
	defer zipWriter.Close()

	entries, err := fsys.List(ctx, basePath, &vfs.ListFilter{Recursive: true})
	if err != nil {
		return fmt.Errorf("failed to list folder: %w", err)
	}
	for _, entry := range entries {
		if entry.IsDir {
			continue
		}
		r, err := fsys.Open(ctx, entry.Path)
		if err != nil {
			return fmt.Errorf("failed to open %s: %w", entry.Path, err)
		}
		// Compute a relative path inside the zip (trim the base filePath prefix).
		rel := strings.TrimPrefix(entry.Path, basePath)
		rel = strings.TrimPrefix(rel, "/")
		zw, err := zipWriter.Create(rel)
		if err != nil {
			r.Close()
			return fmt.Errorf("failed to create zip entry %s: %w", rel, err)
		}
		if _, err := io.Copy(zw, r); err != nil {
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

// DecodeImage decodes an image stream. Importing this package registers the
// HEIC, BMP, TIFF and WebP decoders alongside the standard library's.
func DecodeImage(r io.Reader) (image.Image, error) {
	img, _, err := image.Decode(r)
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

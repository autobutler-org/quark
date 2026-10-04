package fileutil

// cspell:ignore opendocument

import (
	"archive/zip"
	"compress/flate"
	"io"
	"path/filepath"
	"strings"
	"sync"
)

// zipStoreBelow is the size under which an entry is stored whatever its type:
// deflate saves a handful of bytes on a file this small and costs a
// compressor reset per entry.
const zipStoreBelow = 256

// zipStoredExtensions are formats that are already compressed, so deflating
// them in a folder zip spends a core and saves nothing (#2757). This is the
// one list: ZipMethod reads it for both folder zips.
var zipStoredExtensions = map[string]bool{
	// Images.
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".heic": true, ".heif": true, ".gif": true, ".avif": true,
	// Video.
	".mp4": true, ".m4v": true, ".mov": true, ".mkv": true, ".webm": true, ".avi": true,
	// Audio.
	".mp3": true, ".aac": true, ".m4a": true, ".flac": true, ".ogg": true, ".opus": true,
	// Archives.
	".zip": true, ".gz": true, ".tgz": true, ".7z": true, ".rar": true, ".xz": true, ".bz2": true, ".zst": true,
	// Documents that are themselves zip containers or compressed streams.
	".pdf": true, ".docx": true, ".xlsx": true, ".pptx": true, ".odt": true, ".ods": true, ".odp": true, ".epub": true,
}

// zipStoredMIMETypes catches a compressed file whose name does not say so.
// Matched as a prefix, so "image/jpeg" also covers parameters after it.
var zipStoredMIMETypes = []string{
	"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/gif", "image/avif",
	"video/", "audio/",
	"application/zip", "application/gzip", "application/x-7z-compressed", "application/vnd.rar",
	"application/x-xz", "application/x-bzip2", "application/zstd", "application/pdf",
	"application/vnd.openxmlformats-officedocument.", "application/vnd.oasis.opendocument.", "application/epub+zip",
}

// ZipMethod is the compression a folder zip uses for an entry: zip.Store for
// an already-compressed format, by extension or MIME type, and for a file
// under 256 bytes; zip.Deflate, at the fastest level, for everything else.
func ZipMethod(name string, mimeType string, size int64) uint16 {
	if size < zipStoreBelow || zipStoredExtensions[strings.ToLower(filepath.Ext(name))] {
		return zip.Store
	}
	mimeType = strings.ToLower(mimeType)
	for _, prefix := range zipStoredMIMETypes {
		if strings.HasPrefix(mimeType, prefix) {
			return zip.Store
		}
	}
	return zip.Deflate
}

// zipCopyBuffer is the one copy buffer a folder zip reuses for every entry.
const zipCopyBuffer = 32 << 10

// copyEntry copies an entry's contents through buf. The reader is wrapped so
// an *os.File's WriteTo cannot bypass buf and allocate its own per entry,
// which for 5,000 small files was 160 MB of garbage per archive.
func copyEntry(dst io.Writer, src io.Reader, buf []byte) (int64, error) {
	return io.CopyBuffer(dst, struct{ io.Reader }{src}, buf)
}

// fastFlateWriters pools BestSpeed compressors across entries and archives,
// as archive/zip does for its default-level one: a flate.Writer is ~600 KiB.
var fastFlateWriters sync.Pool

// pooledFlateWriter returns its compressor to fastFlateWriters on Close.
type pooledFlateWriter struct {
	*flate.Writer
}

func (w pooledFlateWriter) Close() error {
	err := w.Writer.Close()
	fastFlateWriters.Put(w.Writer)
	return err
}

// newFolderZipWriter is a zip.Writer onto w whose Deflate is flate.BestSpeed:
// a folder download is bound by how fast it compresses, not by bytes saved.
func newFolderZipWriter(w io.Writer) *zip.Writer {
	zw := zip.NewWriter(w)
	zw.RegisterCompressor(zip.Deflate, func(out io.Writer) (io.WriteCloser, error) {
		if fw, ok := fastFlateWriters.Get().(*flate.Writer); ok {
			fw.Reset(out)
			return pooledFlateWriter{fw}, nil
		}
		fw, err := flate.NewWriter(out, flate.BestSpeed)
		if err != nil {
			return nil, err
		}
		return pooledFlateWriter{fw}, nil
	})
	return zw
}

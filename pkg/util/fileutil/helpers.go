package fileutil

import (
	"archive/zip"
	"context"
	"fmt"
	"io"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
)

// dbRelPath spells a path the way the photo tables key it: slash-separated,
// cleaned, no leading slash. The file routes resolve "/a.jpg" and "a.jpg" to
// the same file, so the rows have to be matched on one spelling.
func dbRelPath(p string) string {
	return strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(p)), "/")
}

// movePhotoRows points favorites and album items at a moved file, or at
// everything under a moved folder. A row whose destination already exists is
// left behind by the update and dropped afterwards: the file it named is gone.
func movePhotoRows(ctx context.Context, q *db.Queries, oldSerial, oldPath, newSerial, newPath string) error {
	oldPath, newPath = dbRelPath(oldPath), dbRelPath(newPath)
	if oldPath == "" || newPath == "" || (oldSerial == newSerial && oldPath == newPath) {
		return nil
	}
	if err := q.MoveFavorites(ctx, db.MoveFavoritesParams{
		OldDeviceSerial: oldSerial, OldRelPath: oldPath,
		NewDeviceSerial: newSerial, NewRelPath: newPath,
	}); err != nil {
		return err
	}
	if err := q.DeleteFavoritesUnder(ctx, db.DeleteFavoritesUnderParams{DeviceSerial: oldSerial, RelPath: oldPath}); err != nil {
		return err
	}
	if err := q.MoveAlbumItems(ctx, db.MoveAlbumItemsParams{
		OldDeviceSerial: oldSerial, OldRelPath: oldPath,
		NewDeviceSerial: newSerial, NewRelPath: newPath,
	}); err != nil {
		return err
	}
	return q.DeletePhotoFromAllAlbums(ctx, db.DeletePhotoFromAllAlbumsParams{DeviceSerial: oldSerial, RelPath: oldPath})
}

// notFound marks an error as a 404 for the handler.
func notFound(err error) error { return &NotFoundError{Err: err} }

// notFoundf marks a formatted message as a 404 for the handler.
func notFoundf(format string, args ...any) error {
	return &NotFoundError{Err: fmt.Errorf(format, args...)}
}

// zipMethodNames names the compression methods a zip may declare. Go's
// archive/zip implements only Store (0) and Deflate (8); everything else comes
// back as the bare "zip: unsupported compression algorithm", which tells the
// user nothing about which archive is at fault or what to do about it.
var zipMethodNames = map[uint16]string{
	1:  "Shrink",
	2:  "Reduce",
	6:  "Implode",
	9:  "Deflate64",
	12: "BZIP2",
	14: "LZMA",
	93: "Zstandard",
	95: "XZ",
	96: "JPEG",
	97: "WavPack",
	98: "PPMd",
}

// openZipEntry opens an entry, translating a method this build cannot
// decompress into an [UnsupportedError] that names the method and the fix.
func openZipEntry(f *zip.File) (io.ReadCloser, error) {
	rc, err := f.Open()
	if err == nil {
		return rc, nil
	}
	if f.Method != zip.Store && f.Method != zip.Deflate {
		name, known := zipMethodNames[f.Method]
		if !known {
			name = fmt.Sprintf("method %d", f.Method)
		}
		return nil, &UnsupportedError{Err: fmt.Errorf(
			"archive entry %s uses %s compression, which is not supported; re-create the archive using standard Deflate compression",
			f.Name, name)}
	}
	return nil, fmt.Errorf("failed to open archive entry %s: %w", f.Name, err)
}

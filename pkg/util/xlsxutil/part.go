package xlsxutil

import (
	"errors"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// openPackage opens an .xlsx through officezip.
//
// MaxPartBytes is the cap this reader already puts on one part. MaxTotalBytes
// has to cover every part a conversion reads: the root relationships, the
// workbook, its relationships and the styles, each worksheet twice (once to
// measure it and once to stream it), and the shared strings. A zero total
// would take officezip's default and reject a workbook that converts today.
// Shared strings are tighter than MaxPartBytes and are read with PartLimited.
func openPackage(src io.ReaderAt, size int64) (*officezip.Package, error) {
	pkg, err := officezip.Open(src, size, officezip.Limits{
		MaxPartBytes:  MaxPartBytes,
		MaxTotalBytes: MaxPartBytes*int64(4+2*MaxSheets) + MaxSharedStringBytes,
	})
	if err != nil {
		return nil, wrapPackage(err)
	}
	return pkg, nil
}

// openPart opens one part for reading, capped at limit uncompressed bytes.
// limit cannot rise above the package's MaxPartBytes. A zip entry declares
// its own uncompressed size, and a small compressed part can expand to an
// arbitrarily large one, so neither the declaration nor the stream is trusted.
func openPart(pkg *officezip.Package, name string, limit int64) (io.ReadCloser, error) {
	rc, err := pkg.PartLimited(name, limit)
	if err != nil {
		return nil, wrapPackage(err)
	}
	return rc, nil
}

// wrapPackage reports an officezip failure as this package's own sentinel.
// A part past a limit is [ErrTooLarge]; anything else about the package is
// [ErrNotSpreadsheet].
func wrapPackage(err error) error {
	if err == nil || errors.Is(err, ErrTooLarge) || errors.Is(err, ErrNotSpreadsheet) {
		return err
	}
	if errors.Is(err, officezip.ErrTooLarge) {
		return fmt.Errorf("%w: %v", ErrTooLarge, err)
	}
	return fmt.Errorf("%w: %v", ErrNotSpreadsheet, err)
}

// partError reports what went wrong reading a part. A part that broke its
// bound says so; anything else is a malformed package.
func partError(name string, err error) error {
	if errors.Is(err, ErrTooLarge) || errors.Is(err, officezip.ErrTooLarge) {
		return wrapPackage(err)
	}
	if errors.Is(err, ErrNotSpreadsheet) {
		return err
	}
	return fmt.Errorf("%w: %s: %v", ErrNotSpreadsheet, name, err)
}

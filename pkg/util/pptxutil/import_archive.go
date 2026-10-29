package pptxutil

import (
	"errors"
	"fmt"
	"io"
	"path"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// archiveLimits is what one import may read. It is a package variable so a
// test can shrink the shared budget without building a multi-gigabyte file.
// Every field is set: a zero one would take officezip's default, and those
// defaults are tighter than a deck this importer already accepts. The part
// cap is the picture cap, which is the larger of the two; an XML part is
// read through [officezip.Package.XMLLimited] at [MaxXMLPartBytes].
var archiveLimits = officezip.Limits{
	MaxEntries:        MaxImportEntries,
	MaxDirectoryBytes: maxCentralDirectoryBytes,
	MaxPartBytes:      max(MaxXMLPartBytes, MaxImageBytes),
	MaxTotalBytes:     MaxImportBytes,
	MaxElements:       MaxXMLElements,
	MaxDepth:          MaxXMLDepth,
}

// openArchive opens a .pptx through officezip, keeping this package's own
// sentinels. A name that could climb out of the package, or that two entries
// share, refuses the archive.
func openArchive(src io.ReaderAt, size int64) (*officezip.Package, error) {
	if size <= 0 {
		return nil, fmt.Errorf("%w: the file is empty", ErrNotPptx)
	}
	pkg, err := officezip.Open(src, size, archiveLimits)
	if err != nil {
		return nil, wrapPackage(err)
	}
	return pkg, nil
}

// wrapPackage reports an officezip failure as this package's own sentinel.
// A part past a limit is [ErrTooLarge], a missing one is [errMissingPart],
// and anything else about the package is [ErrNotPptx].
func wrapPackage(err error) error {
	if err == nil || errors.Is(err, ErrTooLarge) || errors.Is(err, ErrNotPptx) || errors.Is(err, errMissingPart) {
		return err
	}
	switch {
	case errors.Is(err, officezip.ErrTooLarge):
		return fmt.Errorf("%w: %v", ErrTooLarge, err)
	case errors.Is(err, officezip.ErrMissingPart):
		return fmt.Errorf("%w: %v", errMissingPart, err)
	default:
		return fmt.Errorf("%w: %v", ErrNotPptx, err)
	}
}

// errMissingPart is a part the package does not hold.
var errMissingPart = errors.New("pptxutil: missing part")

// decodeXML decodes a part into v; see decodeXMLCounted.
func decodeXML(pkg *officezip.Package, name string, v any) error {
	_, err := decodeXMLCounted(pkg, name, v)
	return err
}

// decodeXMLCounted decodes a part into v and returns how many elements it
// held, refusing one past [MaxXMLPartBytes], [MaxXMLElements] or
// [MaxXMLDepth]. The element cap is what bounds the memory v costs, since a
// part's size alone does not: a few bytes per element add up to millions of
// them. encoding/xml expands no entities a document declares, so a part
// cannot grow past what it holds.
func decodeXMLCounted(pkg *officezip.Package, name string, v any) (int, error) {
	dec, err := pkg.XMLLimited(name, MaxXMLPartBytes)
	if err != nil {
		return 0, wrapPackage(err)
	}
	defer dec.Close()
	if err := dec.Decode(v); err != nil {
		if errors.Is(err, officezip.ErrTooLarge) || errors.Is(err, ErrTooLarge) {
			return dec.Elements(), wrapPackage(err)
		}
		return dec.Elements(), fmt.Errorf("%w: %s: %v", ErrNotPptx, name, err)
	}
	return dec.Elements(), nil
}

// relsPath is the relationships part of a part; the empty name is the
// package's own.
func relsPath(part string) string {
	if part == "" {
		return "_rels/.rels"
	}
	return path.Join(path.Dir(part), "_rels", path.Base(part)+".rels")
}

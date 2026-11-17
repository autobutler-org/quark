package zipselectionutil

import (
	"archive/zip"
	"context"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// copyBuffer is the one buffer a selection zip copies every entry through.
const copyBuffer = 32 << 10

// selectionZip is one archive being built.
type selectionZip struct {
	ctx      context.Context
	registry vfs.Registry
	access   accessutil.Access
	zw       *zip.Writer
	buf      []byte
	names    entryNames
	// seen holds every path already added or skipped, so a path selected
	// twice is zipped once.
	seen   map[Path]bool
	result ZipSelectionResult
}

// entryNames hands out entry names no other entry in the archive has.
type entryNames struct {
	// taken holds every name given out, lowercased: an archive extracted on a
	// case-insensitive disk would otherwise overwrite one with another.
	taken map[string]bool
}

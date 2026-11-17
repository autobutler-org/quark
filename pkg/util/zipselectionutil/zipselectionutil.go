// Package zipselectionutil zips a selection of files, picked from any folders
// on any devices, into one archive streamed straight onto a writer (#4195). It
// is what a "download these photos" from a selection serves, where a folder
// zip covers one folder.
//
// Each entry is copied from the file's VFS namespace through one reused
// buffer, so the heap stays a few MiB however large the files are. A path the
// caller may not read, that does not exist, that is a folder, or that sits on
// a device that is not attached is left out and named in a skipped.txt entry
// at the end, rather than failing the download. Entries are named after the
// file alone; a name already taken in the archive, compared without case,
// gets a " (1)", " (2)", ... before its extension.
package zipselectionutil

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// MaxPaths is the most paths one selection may name.
const MaxPaths = 2000

// SkippedListName is the name of the entry that lists what was left out,
// numbered like any other entry when a selected file already has it.
const SkippedListName = "skipped.txt"

// ErrNoPaths is a selection that names nothing.
var ErrNoPaths = errors.New("select at least one file to download")

// ErrTooManyPaths is a selection over MaxPaths.
var ErrTooManyPaths = fmt.Errorf("a download can hold at most %d files", MaxPaths)

// Path is one selected file: its path in the files namespace of the device
// Serial names, "" for the internal drive.
type Path struct {
	Serial   string `json:"serial"`
	FilePath string `json:"filePath"`
}

// Validate reports whether a selection is one ZipSelection takes: at least
// one path and at most MaxPaths.
func Validate(paths []Path) error {
	switch {
	case len(paths) == 0:
		return ErrNoPaths
	case len(paths) > MaxPaths:
		return ErrTooManyPaths
	}
	return nil
}

// SelectionKey is the stand-in file path a download token for this selection
// is bound to: "selection:" and the SHA-256 of the paths in order. The
// download presents the paths again and must hash to the same key, so a
// token cannot be spent on any other selection.
func SelectionKey(paths []Path) string {
	// Marshaling a slice of string-only structs cannot fail.
	encoded, _ := json.Marshal(paths)
	sum := sha256.Sum256(encoded)
	return "selection:" + hex.EncodeToString(sum[:])
}

// ZipSelectionParams is the selection to zip, who is asking, and where the
// archive goes.
type ZipSelectionParams struct {
	Ctx context.Context
	// Registry holds the files namespace of every attached device.
	Registry vfs.Registry
	// Access is the caller's: every path is checked against it for read.
	Access accessutil.Access
	Paths  []Path
	// Writer receives the archive as it is built.
	Writer io.Writer
}

// ZipSelectionResult is what the archive ended up holding.
type ZipSelectionResult struct {
	// Entries is how many selected files the archive holds, not counting the
	// skipped list.
	Entries int
	// Skipped is every path left out, in selection order.
	Skipped []Path
}

// ZipSelection writes the selected files onto Writer as one zip, then a
// skipped.txt naming anything left out. A file that cannot be read is
// skipped; an error is returned only when the archive itself cannot be
// written, as when the client goes away or a read fails partway through a
// file, and the archive is then incomplete.
func ZipSelection(params ZipSelectionParams) (ZipSelectionResult, error) {
	zw := newSelectionZipWriter(params.Writer)
	z := selectionZip{
		ctx:      params.Ctx,
		registry: params.Registry,
		access:   params.Access,
		zw:       zw,
		buf:      make([]byte, copyBuffer),
		names:    entryNames{taken: map[string]bool{}},
		seen:     map[Path]bool{},
	}
	for _, p := range params.Paths {
		if err := z.add(p); err != nil {
			_ = zw.Close()
			return z.result, err
		}
	}
	if err := z.writeSkipped(); err != nil {
		_ = zw.Close()
		return z.result, err
	}
	if err := zw.Close(); err != nil {
		return z.result, fmt.Errorf("failed to finish zip: %w", err)
	}
	return z.result, nil
}

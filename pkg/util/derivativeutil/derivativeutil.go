// Package derivativeutil stores the thumbnails and display previews clients
// render for the media they upload (#2379). The device cannot regenerate
// them — it does not decode H.264, HEVC or HEIC — so they are durable, not a
// cache.
//
// A file's derivatives live beside it, in a hidden directory of the folder
// that holds it: a/b.heic keeps them in a/.quark-derivatives/b.heic/. Keeping
// them next to the file is what makes them follow it. A folder moved, trashed,
// restored or backed up carries its derivative directory along with
// everything else in it, and a derivative is found from the file's own path,
// so it is on the same device the file is on. Only an operation on a single
// file has to move, copy or remove that file's entry, and those go through
// [Move], [Copy] and [Remove] here.
//
// A derivative older than its file describes content the file no longer has,
// so [Lookup] ignores it. That covers every path that rewrites a file in
// place without having to hook each one.
package derivativeutil

import (
	"errors"
	"io"
	"path/filepath"
	"time"
)

// DirName is the hidden directory a folder keeps its files' derivatives in.
// storageutil.IsInternalName reserves it, so listings, walks and the file
// index skip it.
const DirName = ".quark-derivatives"

// Kind names one derivative of a file.
type Kind string

const (
	// KindThumbnail is a JPEG with a long edge of 400, the largest thumbnail
	// size the server serves; the smaller tiers are resized from it.
	KindThumbnail Kind = "thumbnail"
	// KindPreview is a JPEG with a long edge of about 2048, shown in place of
	// a file clients cannot display directly: HEIC, and video posters.
	KindPreview Kind = "preview"
)

// ErrInvalid reports a derivative that is not a JPEG, is larger than its kind
// allows, or has dimensions no client would send.
var ErrInvalid = errors.New("invalid derivative")

// ParseKind reads a kind from a request. Anything but a known kind is false.
func ParseKind(raw string) (Kind, bool) {
	switch Kind(raw) {
	case KindThumbnail, KindPreview:
		return Kind(raw), true
	default:
		return "", false
	}
}

// MaxBytes is the largest body [Store] accepts for kind.
func MaxBytes(kind Kind) int64 {
	if kind == KindPreview {
		return 16 << 20
	}
	return 2 << 20
}

// Path is where the derivative of kind for the file at source is stored.
func Path(source string, kind Kind) string {
	return filepath.Join(dir(source), string(kind)+".jpg")
}

// StoreParams is one derivative on its way to disk.
type StoreParams struct {
	// SourcePath is the OS path of the file the derivative belongs to.
	SourcePath string
	Kind       Kind
	// Reader is the JPEG, read to EOF or to one byte past MaxBytes(Kind).
	Reader io.Reader
}

// StoreResult reports the committed derivative.
type StoreResult struct {
	Path    string
	ModTime time.Time
}

// Store validates a derivative and commits it, replacing any earlier one of
// the same kind. A reader never sees a half-written file.
func Store(params StoreParams) (StoreResult, error) {
	return store(params)
}

// LookupParams asks for one derivative of a file.
type LookupParams struct {
	SourcePath string
	Kind       Kind
	// SourceModTime is the file's modification time. A derivative older than
	// it is stale.
	SourceModTime time.Time
}

// LookupResult is where the derivative is, when there is a fresh one.
type LookupResult struct {
	Found   bool
	Path    string
	ModTime time.Time
}

// Lookup finds a file's derivative of the given kind. A missing or stale
// derivative is Found false, not an error.
func Lookup(params LookupParams) (LookupResult, error) {
	return lookup(params)
}

// Move carries the derivatives of the file that was at oldSource to
// newSource, after the file itself has moved. Whatever derivatives newSource
// had are dropped: they described the file that was replaced. A folder has no
// derivatives of its own, so moving one is a no-op here; its contents' travel
// inside it.
func Move(oldSource, newSource string) error {
	return move(oldSource, newSource)
}

// Copy duplicates the derivatives of src for its copy at dst.
func Copy(src, dst string) error {
	return copyDerivatives(src, dst)
}

// Remove deletes a file's derivatives. A file without any is fine.
func Remove(source string) error {
	return remove(source)
}

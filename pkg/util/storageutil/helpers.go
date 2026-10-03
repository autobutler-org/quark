package storageutil

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// setupFilesDirIn is SetupFilesDir with an injectable data directory so it can
// be tested against a temp dir instead of the real one.
func setupFilesDirIn(dataDir string) error {
	filesDir := ConstructFilesDir(dataDir)
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return fmt.Errorf("failed to create storage directory: %w", err)
	}
	return nil
}

func readFileTrim(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

// safeJoin joins base with the provided path segments and returns an error if
// the resulting path would escape the base directory (path traversal guard).
func safeJoin(base string, parts ...string) (string, error) {
	cleanBase := filepath.Clean(base)
	joined := filepath.Clean(filepath.Join(append([]string{cleanBase}, parts...)...))
	if !within(cleanBase, joined) || !resolvesWithin(cleanBase, joined) {
		return "", errEscapesBase
	}
	return joined, nil
}

var errEscapesBase = errors.New("invalid path: escapes base directory")

// within reports whether p is base or lies under it, lexically.
func within(base, p string) bool {
	return p == base || strings.HasPrefix(p, base+string(filepath.Separator))
}

// resolvesWithin reports whether joined, a lexical descendant of base, still
// lands inside base once the symlinks already on disk are followed (#2157).
//
// The policy: a symlink that resolves inside base is allowed, one that leaves
// it is not, and a dangling one is refused, since writing through it would
// create its target wherever it points. The deepest existing ancestor of
// joined is resolved and the components that do not exist yet are appended, so
// a file about to be created is checked against the directory it will land in.
// base itself may be a symlink (datalinks/ is). A base that does not exist has
// nothing on disk to follow, and the lexical check stands.
//
// This narrows the window rather than closing it: a link planted between this
// check and the caller's open is not seen.
func resolvesWithin(base, joined string) bool {
	realBase, err := filepath.EvalSymlinks(base)
	if err != nil {
		return true
	}
	current, suffix := joined, ""
	for {
		landed, err := filepath.EvalSymlinks(current)
		if err == nil {
			return within(realBase, filepath.Join(landed, suffix))
		}
		// current exists (it is a dangling link, or unreadable) yet does not
		// resolve; base resolved, so the walk never climbs above it.
		if _, statErr := os.Lstat(current); statErr == nil || current == base {
			return false
		}
		suffix = filepath.Join(filepath.Base(current), suffix)
		current = filepath.Dir(current)
	}
}

// nameTaken is the error for an upload whose name is already in use when the
// caller chose neither to overwrite nor to keep both. It wraps [fs.ErrExist],
// which is how a caller tells it apart from a failed write.
func nameTaken(rootDir, fileName string) error {
	return fmt.Errorf("%w: %s", fs.ErrExist, path.Join(rootDir, fileName))
}

// rootDeviceName is what the UI calls the appliance's own disk.
//
// The mount point's base name where there is one, and a plain-language name
// where there is not — which on a Quark is every time, since its root is "/".
// It used to say "Root Volume", the kind of phrase that tells a household
// owner they are looking at a Linux admin panel rather than their own
// storage (#2047).
func rootDeviceName(mountPoint string) string {
	name := filepath.Base(mountPoint)
	if name == "" || name == "/" || name == "." {
		return "Built-in storage"
	}
	return name
}

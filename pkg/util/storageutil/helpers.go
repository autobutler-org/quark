package storageutil

import (
	"errors"
	"fmt"
	"os"
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
// create its target wherever it points. base itself may be a symlink
// (datalinks/ is). A base that does not exist has nothing on disk to follow,
// and the lexical check stands.
//
// This narrows the window rather than closing it: a link planted between this
// check and the caller's open is not seen.
func resolvesWithin(base, joined string) bool {
	realBase, err := filepath.EvalSymlinks(base)
	if err != nil {
		return true
	}
	landed, ok := resolvePending(base, joined, filepath.EvalSymlinks)
	return ok && within(realBase, landed)
}

// resolvePending is [ResolvePending] with the symlink resolver injected, so a
// test can make a directory appear between two looks at it.
func resolvePending(base, p string, evalSymlinks func(string) (string, error)) (string, bool) {
	current, suffix := p, ""
	for {
		landed, err := evalSymlinks(current)
		if err == nil {
			return filepath.Join(landed, suffix), true
		}
		// current exists yet did not resolve: it is a dangling link, it is
		// unreadable, or it was created after evalSymlinks looked — concurrent
		// uploads into one new folder race to create it (#2767). A second look
		// tells them apart: a directory that appeared now resolves, a dangling
		// link still does not. base resolved, so the walk never climbs above it.
		if _, statErr := os.Lstat(current); statErr == nil {
			if landed, err := evalSymlinks(current); err == nil {
				return filepath.Join(landed, suffix), true
			}
			return "", false
		}
		if current == base {
			return "", false
		}
		suffix = filepath.Join(filepath.Base(current), suffix)
		current = filepath.Dir(current)
	}
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

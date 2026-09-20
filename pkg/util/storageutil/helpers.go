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
	if joined != cleanBase && !strings.HasPrefix(joined, cleanBase+string(filepath.Separator)) {
		return "", errors.New("invalid path: escapes base directory")
	}
	return joined, nil
}

// nameTaken is the error for an upload whose name is already in use when the
// caller chose neither to overwrite nor to keep both. It wraps [fs.ErrExist],
// which is how a caller tells it apart from a failed write.
func nameTaken(rootDir, fileName string) error {
	return fmt.Errorf("%w: %s", fs.ErrExist, path.Join(rootDir, fileName))
}

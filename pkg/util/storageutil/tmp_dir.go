package storageutil

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// tmpDirName is the scratch directory under the data dir. Upload session
// staging, device-path upload temps and transcode staging all live under it,
// and none of them is meant to outlive the process that wrote it.
const tmpDirName = "tmp"

// ClearTmpDirParams names the data dir whose tmp directory is emptied.
type ClearTmpDirParams struct {
	// DataDir is the data dir itself, not its tmp directory. It must be an
	// absolute path other than the filesystem root.
	DataDir string
}

// ClearTmpDirResult reports what the wipe reclaimed.
type ClearTmpDirResult struct {
	// Removed counts the top-level entries removed from tmp.
	Removed int
	// Bytes is the size of the regular files among them.
	Bytes int64
}

// ClearTmpDir empties <DataDir>/tmp and keeps the directory. Everything in it
// is scratch owned by a running process, so at startup it was stranded by one
// that exited mid-write — a crash, a kill, a hot reload — and at shutdown it is
// about to be. A missing tmp dir is not an error; one that is a symlink is
// refused, since the wipe would follow it somewhere that is not Quark's.
//
// An entry that cannot be removed is skipped and reported in the error; the
// rest are still removed and counted.
func ClearTmpDir(params ClearTmpDirParams) (ClearTmpDirResult, error) {
	dataDir := filepath.Clean(params.DataDir)
	if params.DataDir == "" || !filepath.IsAbs(dataDir) || dataDir == filepath.Dir(dataDir) {
		return ClearTmpDirResult{}, fmt.Errorf("refusing to clear the tmp dir of data dir %q", params.DataDir)
	}
	tmpDir := filepath.Join(dataDir, tmpDirName)

	info, err := os.Lstat(tmpDir)
	if errors.Is(err, fs.ErrNotExist) {
		return ClearTmpDirResult{}, nil
	}
	if err != nil {
		return ClearTmpDirResult{}, err
	}
	if !info.IsDir() {
		return ClearTmpDirResult{}, fmt.Errorf("refusing to clear %s: not a directory", tmpDir)
	}
	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		return ClearTmpDirResult{}, err
	}

	var result ClearTmpDirResult
	var errs []error
	for _, entry := range entries {
		// ReadDir names carry no separator, so every path here is a direct
		// child of tmpDir.
		entryPath := filepath.Join(tmpDir, entry.Name())
		size := regularFileBytes(entryPath)
		if err := os.RemoveAll(entryPath); err != nil {
			errs = append(errs, err)
			continue
		}
		result.Removed++
		result.Bytes += size
	}
	return result, errors.Join(errs...)
}

// regularFileBytes sums the regular files at or under root without following
// symlinks. Best effort: it only feeds a log line.
func regularFileBytes(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(_ string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.Type().IsRegular() {
			if info, infoErr := d.Info(); infoErr == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return total
}

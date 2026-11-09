package backup

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const manifestFilename = "backup_manifest.json"

// ErrNoManifest is what verifying a drive with no finished backup returns: a
// manifest is written only when a snapshot completes, so there is nothing to
// check yet.
var ErrNoManifest = errors.New("nothing to verify yet: run Back Up on this drive first")

// GenerateManifest hashes every file under dir in fsys but the manifest
// itself, keyed by its path relative to dir. An empty dir is the root.
func GenerateManifest(ctx context.Context, fsys vfs.VFS, dir string) (*Manifest, error) {
	m := &Manifest{
		CreatedAt: time.Now(),
		Drives:    []ManifestDrive{},
		Files:     make(map[string]ManifestFile),
	}

	err := vfs.Walk(ctx, fsys, dir, func(fi vfs.FileInfo) error {
		rel := relTo(dir, fi.Path)
		if fi.IsDir || rel == manifestFilename {
			return nil
		}
		hash, err := hashFile(ctx, fsys, fi.Path)
		if err != nil {
			return fmt.Errorf("hash %s: %w", rel, err)
		}
		m.Files[rel] = ManifestFile{SHA256: hash, Size: fi.Size}
		m.TotalFiles++
		m.TotalBytes += fi.Size
		return nil
	})
	if err != nil {
		return nil, err
	}

	return m, nil
}

// WriteManifest writes m in dir on fsys, replacing any earlier one whole.
func WriteManifest(ctx context.Context, m *Manifest, fsys vfs.VFS, dir string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return fsys.Write(ctx, path.Join(dir, manifestFilename), bytes.NewReader(data), vfs.WriteOptions{ContentType: "application/json"})
}

// ReadManifest reads the manifest in dir on fsys: a run's folder,
// backups/<run>.
func ReadManifest(ctx context.Context, fsys vfs.VFS, dir string) (*Manifest, error) {
	f, err := fsys.Open(ctx, path.Join(dir, manifestFilename))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var m Manifest
	if err := json.NewDecoder(f).Decode(&m); err != nil {
		return nil, err
	}
	return &m, nil
}

// VerifyBackupParams names the device whose snapshot backup to check.
type VerifyBackupParams struct {
	Ctx context.Context
	// Registry holds the device's files namespace.
	Registry vfs.Registry
	// DeviceSerial is the device holding the backup.
	DeviceSerial string
	// Full hashes every file; otherwise only sizes are compared.
	Full bool
	// Run is the run to verify, a folder under backups/. Empty is the newest
	// complete run.
	Run string
}

// VerifyBackup checks one run on a device against its manifest. A device
// that is not attached is the error [fileutil.FilesVFS] reports for it, one
// with no complete run is [ErrNoManifest], and a run it does not hold is
// [ErrRunNotFound].
func VerifyBackup(params VerifyBackupParams) (*VerifyResult, error) {
	fsys, err := fileutil.FilesVFS(params.Registry, params.DeviceSerial)
	if err != nil {
		return nil, err
	}
	run, err := resolveRun(params.Ctx, fsys, params.Run)
	if errors.Is(err, ErrNoSnapshot) {
		return nil, ErrNoManifest
	}
	if err != nil {
		return nil, err
	}
	result, err := verifyTree(params.Ctx, fsys, runDir(run.Folder), params.Full)
	if err != nil {
		return nil, err
	}
	result.Run = run.Folder
	return result, nil
}

// verifyTree checks the files under dir in fsys against the manifest there.
func verifyTree(ctx context.Context, fsys vfs.VFS, dir string, full bool) (*VerifyResult, error) {
	m, err := ReadManifest(ctx, fsys, dir)
	if errors.Is(err, vfs.ErrNotFound) {
		return nil, ErrNoManifest
	}
	if err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}

	result := &VerifyResult{}
	checked := make(map[string]bool)

	for rel, mf := range m.Files {
		checked[rel] = true

		info, err := fsys.Stat(ctx, path.Join(dir, rel))
		if err != nil || info.IsDir {
			result.Missing = append(result.Missing, rel)
			continue
		}

		if !full {
			if info.Size == mf.Size {
				result.OK++
			} else {
				result.Corrupted = append(result.Corrupted, rel)
			}
			continue
		}

		hash, err := hashFile(ctx, fsys, path.Join(dir, rel))
		if err != nil {
			result.Errors = append(result.Errors, fmt.Sprintf("%s: %v", rel, err))
			continue
		}

		if hash != mf.SHA256 {
			result.Corrupted = append(result.Corrupted, rel)
		} else {
			result.OK++
		}
	}

	// Find files on the device not in the manifest. The walk is best-effort
	// and the callback never fails, so neither can the walk.
	_ = vfs.Walk(ctx, fsys, dir, func(fi vfs.FileInfo) error {
		if rel := relTo(dir, fi.Path); !fi.IsDir && rel != manifestFilename && !checked[rel] {
			result.Added = append(result.Added, rel)
		}
		return nil
	})

	return result, nil
}

// relTo is p, a path a walk of dir visited, relative to dir.
func relTo(dir, p string) string {
	if dir == "" {
		return p
	}
	return strings.TrimPrefix(p, dir+"/")
}

// hashFile streams the file at path in fsys through SHA-256.
func hashFile(ctx context.Context, fsys vfs.VFS, path string) (string, error) {
	f, err := fsys.Open(ctx, path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

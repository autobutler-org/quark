package backup

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"time"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const manifestFilename = "backup_manifest.json"

// GenerateManifest hashes every file in fsys but the manifest itself.
func GenerateManifest(ctx context.Context, fsys vfs.VFS) (*Manifest, error) {
	m := &Manifest{
		CreatedAt: time.Now(),
		Files:     make(map[string]ManifestFile),
	}

	err := vfs.Walk(ctx, fsys, "", func(fi vfs.FileInfo) error {
		if fi.IsDir || fi.Path == manifestFilename {
			return nil
		}
		hash, err := hashFile(ctx, fsys, fi.Path)
		if err != nil {
			return fmt.Errorf("hash %s: %w", fi.Path, err)
		}
		m.Files[fi.Path] = ManifestFile{SHA256: hash, Size: fi.Size}
		m.TotalFiles++
		m.TotalBytes += fi.Size
		return nil
	})
	if err != nil {
		return nil, err
	}

	return m, nil
}

// WriteManifest writes m at the root of fsys, replacing any earlier one whole.
func WriteManifest(ctx context.Context, m *Manifest, fsys vfs.VFS) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return fsys.Write(ctx, manifestFilename, bytes.NewReader(data), vfs.WriteOptions{ContentType: "application/json"})
}

// ReadManifest reads the manifest at the root of fsys.
func ReadManifest(ctx context.Context, fsys vfs.VFS) (*Manifest, error) {
	f, err := fsys.Open(ctx, manifestFilename)
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
}

// VerifyBackup checks the backup on a device against its manifest. A device
// that is not attached is the error [fileutil.FilesVFS] reports for it.
func VerifyBackup(params VerifyBackupParams) (*VerifyResult, error) {
	fsys, err := fileutil.FilesVFS(params.Registry, params.DeviceSerial)
	if err != nil {
		return nil, err
	}
	return verifyTree(params.Ctx, fsys, params.Full)
}

// verifyTree checks the backup in fsys against its manifest.
func verifyTree(ctx context.Context, fsys vfs.VFS, full bool) (*VerifyResult, error) {
	m, err := ReadManifest(ctx, fsys)
	if err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}

	result := &VerifyResult{}
	checked := make(map[string]bool)

	for rel, mf := range m.Files {
		checked[rel] = true

		info, err := fsys.Stat(ctx, rel)
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

		hash, err := hashFile(ctx, fsys, rel)
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
	_ = vfs.Walk(ctx, fsys, "", func(fi vfs.FileInfo) error {
		if !fi.IsDir && fi.Path != manifestFilename && !checked[fi.Path] {
			result.Added = append(result.Added, fi.Path)
		}
		return nil
	})

	return result, nil
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

package backup

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

const manifestFilename = "backup_manifest.json"

func GenerateManifest(rootDir string) (*Manifest, error) {
	m := &Manifest{
		CreatedAt: time.Now(),
		Files:     make(map[string]ManifestFile),
	}

	err := filepath.WalkDir(rootDir, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}

		rel, err := filepath.Rel(rootDir, path)
		if err != nil {
			return err
		}
		if rel == manifestFilename {
			return nil
		}

		info, err := d.Info()
		if err != nil {
			return err
		}

		hash, err := hashFile(path)
		if err != nil {
			return fmt.Errorf("hash %s: %w", rel, err)
		}

		m.Files[rel] = ManifestFile{SHA256: hash, Size: info.Size()}
		m.TotalFiles++
		m.TotalBytes += info.Size()
		return nil
	})
	if err != nil {
		return nil, err
	}

	return m, nil
}

func WriteManifest(m *Manifest, dir string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return storageutil.WriteFileAtomic(filepath.Join(dir, manifestFilename), bytes.NewReader(data))
}

func ReadManifest(dir string) (*Manifest, error) {
	data, err := os.ReadFile(filepath.Join(dir, manifestFilename))
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	return &m, nil
}

func VerifyBackup(rootDir string, full bool) (*VerifyResult, error) {
	m, err := ReadManifest(rootDir)
	if err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}

	result := &VerifyResult{}
	checked := make(map[string]bool)

	for rel, mf := range m.Files {
		checked[rel] = true
		path := filepath.Join(rootDir, rel)

		info, err := os.Stat(path)
		if err != nil {
			result.Missing = append(result.Missing, rel)
			continue
		}

		if !full {
			if info.Size() == mf.Size {
				result.OK++
			} else {
				result.Corrupted = append(result.Corrupted, rel)
			}
			continue
		}

		hash, err := hashFile(path)
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

	// Find files on disk not in manifest. The callback swallows per-entry
	// errors and always returns nil, so the walk itself cannot fail.
	_ = filepath.WalkDir(rootDir, func(path string, d fs.DirEntry, _ error) error {
		if d == nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(rootDir, path)
		if rel == manifestFilename {
			return nil
		}
		if !checked[rel] {
			result.Added = append(result.Added, rel)
		}
		return nil
	})

	return result, nil
}

func hashFile(path string) (string, error) {
	f, err := os.Open(path)
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

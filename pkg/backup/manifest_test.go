package backup

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/vfs"
)

func makeBackupDir(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for path, content := range files {
		full := filepath.Join(dir, path)
		os.MkdirAll(filepath.Dir(full), 0755)
		os.WriteFile(full, []byte(content), 0644)
	}
	return dir
}

// localFS is a disk-backed files namespace over dir.
func localFS(t *testing.T, dir string) vfs.VFS {
	t.Helper()
	fsys, err := vfs.NewLocalVFS(dir, vfs.FilesNamespace(""))
	if err != nil {
		t.Fatal(err)
	}
	return fsys
}

func TestGenerateManifest(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"photos/a.jpg": "photo-a",
		"docs/b.txt":   "doc-b",
	})

	m, err := GenerateManifest(t.Context(), localFS(t, dir))
	if err != nil {
		t.Fatal(err)
	}

	if m.TotalFiles != 2 {
		t.Errorf("expected 2 files, got %d", m.TotalFiles)
	}
	if _, ok := m.Files["photos/a.jpg"]; !ok {
		t.Error("missing photos/a.jpg in manifest")
	}
	if _, ok := m.Files["docs/b.txt"]; !ok {
		t.Error("missing docs/b.txt in manifest")
	}
	if m.Files["photos/a.jpg"].SHA256 == "" {
		t.Error("SHA256 should not be empty")
	}
	if m.Files["photos/a.jpg"].Size != 7 {
		t.Errorf("expected size 7 for 'photo-a', got %d", m.Files["photos/a.jpg"].Size)
	}
}

func TestManifest_ExcludesItself(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"file.txt": "data",
	})

	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	WriteManifest(t.Context(), m, localFS(t, dir))

	m2, _ := GenerateManifest(t.Context(), localFS(t, dir))
	if _, ok := m2.Files[manifestFilename]; ok {
		t.Error("manifest should exclude itself")
	}
	if m2.TotalFiles != 1 {
		t.Errorf("expected 1 file, got %d", m2.TotalFiles)
	}
}

func TestWriteAndReadManifest(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{"a.txt": "hello"})

	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	if err := WriteManifest(t.Context(), m, localFS(t, dir)); err != nil {
		t.Fatal(err)
	}

	read, err := ReadManifest(t.Context(), localFS(t, dir))
	if err != nil {
		t.Fatal(err)
	}
	if read.TotalFiles != 1 {
		t.Errorf("expected 1 file, got %d", read.TotalFiles)
	}
	if read.Files["a.txt"].SHA256 != m.Files["a.txt"].SHA256 {
		t.Error("hash mismatch after read")
	}
}

func TestVerifyBackup_AllOK(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"a.txt": "aaa",
		"b.txt": "bbb",
	})
	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	WriteManifest(t.Context(), m, localFS(t, dir))

	result, err := verifyTree(t.Context(), localFS(t, dir), true)
	if err != nil {
		t.Fatal(err)
	}
	if result.OK != 2 {
		t.Errorf("expected 2 OK, got %d", result.OK)
	}
	if len(result.Missing) != 0 || len(result.Corrupted) != 0 || len(result.Added) != 0 {
		t.Errorf("expected clean verify, got missing=%d corrupted=%d added=%d",
			len(result.Missing), len(result.Corrupted), len(result.Added))
	}
}

func TestVerifyBackup_MissingFile(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"a.txt": "aaa",
		"b.txt": "bbb",
	})
	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	WriteManifest(t.Context(), m, localFS(t, dir))

	os.Remove(filepath.Join(dir, "b.txt"))

	result, _ := verifyTree(t.Context(), localFS(t, dir), true)
	if len(result.Missing) != 1 || result.Missing[0] != "b.txt" {
		t.Errorf("expected b.txt missing, got %v", result.Missing)
	}
	if result.OK != 1 {
		t.Errorf("expected 1 OK, got %d", result.OK)
	}
}

func TestVerifyBackup_CorruptedFile(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"a.txt": "original",
	})
	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	WriteManifest(t.Context(), m, localFS(t, dir))

	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("tampered"), 0644)

	result, _ := verifyTree(t.Context(), localFS(t, dir), true)
	if len(result.Corrupted) != 1 || result.Corrupted[0] != "a.txt" {
		t.Errorf("expected a.txt corrupted, got %v", result.Corrupted)
	}
}

func TestVerifyBackup_AddedFile(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"a.txt": "aaa",
	})
	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	WriteManifest(t.Context(), m, localFS(t, dir))

	os.WriteFile(filepath.Join(dir, "new.txt"), []byte("new"), 0644)

	result, _ := verifyTree(t.Context(), localFS(t, dir), true)
	if len(result.Added) != 1 || result.Added[0] != "new.txt" {
		t.Errorf("expected new.txt added, got %v", result.Added)
	}
}

func TestVerifyBackup_QuickMode(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{
		"a.txt": "aaa",
	})
	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	WriteManifest(t.Context(), m, localFS(t, dir))

	// Same size but different content — quick mode uses size only, should pass.
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("bbb"), 0644)

	result, _ := verifyTree(t.Context(), localFS(t, dir), false)
	if result.OK != 1 {
		t.Errorf("quick mode should pass on same-size file, got OK=%d corrupted=%v", result.OK, result.Corrupted)
	}

	// Different size — quick mode should catch.
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("longer content"), 0644)
	result, _ = verifyTree(t.Context(), localFS(t, dir), false)
	if len(result.Corrupted) != 1 {
		t.Errorf("quick mode should catch size mismatch, got corrupted=%v", result.Corrupted)
	}
}

func TestVerifyBackup_NoManifest(t *testing.T) {
	dir := t.TempDir()
	_, err := verifyTree(t.Context(), localFS(t, dir), true)
	if err == nil {
		t.Error("expected error when manifest is missing")
	}
}

// TestWriteManifestReplacesTheFileWhole checks a rewritten manifest is renamed
// into place rather than truncating the old one, so a power cut mid-write
// cannot leave an empty manifest (#2611).
func TestWriteManifestReplacesTheFileWhole(t *testing.T) {
	dir := makeBackupDir(t, map[string]string{"a.txt": "hello"})
	m, _ := GenerateManifest(t.Context(), localFS(t, dir))
	if err := WriteManifest(t.Context(), m, localFS(t, dir)); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, manifestFilename)
	old, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Link(path, path+".old"); err != nil {
		t.Fatal(err)
	}

	m.TotalFiles = 42
	if err := WriteManifest(t.Context(), m, localFS(t, dir)); err != nil {
		t.Fatal(err)
	}

	linked, err := os.ReadFile(path + ".old")
	if err != nil {
		t.Fatal(err)
	}
	if string(linked) != string(old) {
		t.Fatal("manifest was rewritten in place")
	}
	read, err := ReadManifest(t.Context(), localFS(t, dir))
	if err != nil {
		t.Fatal(err)
	}
	if read.TotalFiles != 42 {
		t.Errorf("TotalFiles = %d, want 42", read.TotalFiles)
	}
}

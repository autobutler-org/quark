package bundleutil_test

import (
	"archive/tar"
	"bytes"
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/bundleutil"
)

var sqlite = db.Config{Backend: db.SQLite}

// sourceInstall returns the data directory of a SQLite install with one
// account and a file in each bundled directory, plus two that are not bundled.
func sourceInstall(t *testing.T) string {
	t.Helper()
	database := dbtest.NewDB(t)
	var path string
	if err := database.Db.QueryRow(`SELECT file FROM pragma_database_list WHERE name = 'main'`).Scan(&path); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Db.Exec(`INSERT INTO users (id, username, password_hash, recovery_phrase_hash) VALUES (7, 'ada', 'p', 'r')`); err != nil {
		t.Fatal(err)
	}
	if err := database.Db.Close(); err != nil {
		t.Fatal(err)
	}
	dataDir := filepath.Dir(path)
	for name, content := range map[string]string{
		"files/docs/notes.txt":   "hello",
		"files/empty.bin":        "",
		"trash/1/old.txt":        "gone",
		"avatars/7.jpg":          "jpeg",
		"certs/server.key":       "this machine's own",
		"tmp/upload/part-0":      "staging",
		"cache/thumbnails/a.jpg": "derived",
	} {
		write(t, filepath.Join(dataDir, name), content)
	}
	if err := os.Symlink("docs/notes.txt", filepath.Join(dataDir, "files", "link.txt")); err != nil {
		t.Fatal(err)
	}
	return dataDir
}

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestExportThenImport(t *testing.T) {
	ctx := context.Background()
	var bundle bytes.Buffer
	exported, err := bundleutil.Export(ctx, bundleutil.ExportParams{DataDir: sourceInstall(t), Database: sqlite, Out: &bundle})
	if err != nil {
		t.Fatalf("Export: %v", err)
	}
	// quark.db and the four regular files under files, trash and avatars.
	if exported.Files != 5 {
		t.Errorf("Export wrote %d files, want 5", exported.Files)
	}

	target := filepath.Join(t.TempDir(), "data")
	params := bundleutil.ImportParams{DataDir: target, Database: sqlite, Bundle: bytes.NewReader(bundle.Bytes())}
	imported, err := bundleutil.Import(ctx, params)
	if err != nil {
		t.Fatalf("Import: %v", err)
	}
	if imported.Files != 4 {
		t.Errorf("Import placed %d files, want 4", imported.Files)
	}
	for name, want := range map[string]string{
		"files/docs/notes.txt": "hello", "files/empty.bin": "", "files/link.txt": "hello",
		"trash/1/old.txt": "gone", "avatars/7.jpg": "jpeg",
	} {
		got, err := os.ReadFile(filepath.Join(target, name))
		if err != nil || string(got) != want {
			t.Errorf("%s = %q, %v; want %q", name, got, err, want)
		}
	}
	if link, err := os.Readlink(filepath.Join(target, "files", "link.txt")); err != nil || link != "docs/notes.txt" {
		t.Errorf("files/link.txt links to %q, %v; want docs/notes.txt", link, err)
	}
	for _, name := range []string{"certs", "tmp", "cache"} {
		if _, err := os.Stat(filepath.Join(target, name)); !os.IsNotExist(err) {
			t.Errorf("%s was carried over: %v", name, err)
		}
	}
	targetDB, err := sql.Open("sqlite", db.DSN(filepath.Join(target, "quark.db")))
	if err != nil {
		t.Fatal(err)
	}
	defer targetDB.Close()
	var username string
	if err := targetDB.QueryRow(`SELECT username FROM users WHERE id = 7`).Scan(&username); err != nil || username != "ada" {
		t.Errorf("account 7 = %q, %v; want ada", username, err)
	}

	// The install is in use now: a second import is refused before any file is written.
	write(t, filepath.Join(target, "files", "docs", "notes.txt"), "edited since")
	params.Bundle = bytes.NewReader(bundle.Bytes())
	if _, err := bundleutil.Import(ctx, params); err == nil || !strings.Contains(err.Error(), "already has 1 account") {
		t.Fatalf("second Import = %v, want a refusal", err)
	}
	if got, _ := os.ReadFile(filepath.Join(target, "files", "docs", "notes.txt")); string(got) != "edited since" {
		t.Errorf("the refused import overwrote a file: %q", got)
	}
}

func TestImportRefusesAnEntryOutsideTheBundledDirectories(t *testing.T) {
	var bundle bytes.Buffer
	tw := tar.NewWriter(&bundle)
	for _, name := range []string{"quark.db", "../escaped.txt"} {
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	parent := t.TempDir()
	_, err := bundleutil.Import(context.Background(), bundleutil.ImportParams{
		DataDir: filepath.Join(parent, "data"), Database: sqlite, Bundle: &bundle,
	})
	if err == nil || !strings.Contains(err.Error(), "not a Quark bundle") {
		t.Fatalf("Import = %v, want a refusal", err)
	}
	if _, err := os.Stat(filepath.Join(parent, "escaped.txt")); !os.IsNotExist(err) {
		t.Fatalf("an entry escaped the data directory: %v", err)
	}
}

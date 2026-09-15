package fileutil

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestSearchFilesKeepsOnlyReadableMatches runs a name search on every branch it
// can take, the index, the VFS listing and the disk walk, as a non-admin with
// read on one folder of a USB drive (#1907).
func TestSearchFilesKeepsOnlyReadableMatches(t *testing.T) {
	const serial = "USB-1907"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	for _, rel := range []string{"shared/a.txt", "private/b.txt"} {
		full := filepath.Join(filesDir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(rel), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	svc := storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: serial})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: filesNamespace}, vfs.NewStorageServiceVFS(svc, filesNamespace)); err != nil {
		t.Fatal(err)
	}
	devices, err := svc.GetManagedDevices()
	if err != nil {
		t.Fatal(err)
	}
	index := storageutil.NewFileIndex()
	index.Build(devices)

	ctx := context.Background()
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		DeviceSerial: serial,
		RelPath:      "shared",
		UserID:       sql.NullInt64{Int64: user.ID, Valid: true},
		Level:        accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	loaded, err := accessutil.Load(accessutil.LoadParams{
		Ctx: ctx, Database: database, Storage: svc, Principal: accessutil.Principal{UserID: user.ID},
	})
	if err != nil {
		t.Fatal(err)
	}

	for name, params := range map[string]SearchFilesParams{
		"index":     {Index: index, Storage: svc},
		"vfs":       {Registry: registry, Storage: svc},
		"disk walk": {Storage: svc},
	} {
		t.Run(name, func(t *testing.T) {
			params.Ctx = ctx
			params.Query = ".txt"
			params.Access = loaded.Access
			result, err := SearchFiles(params)
			if err != nil {
				t.Fatal(err)
			}
			if len(result.Files) != 1 || filepath.ToSlash(result.Files[0].DirPath) != "shared/a.txt" {
				t.Errorf("matches = %+v, want only shared/a.txt", result.Files)
			}
		})
	}
}

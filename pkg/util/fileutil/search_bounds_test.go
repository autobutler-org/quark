package fileutil

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// homesFixture is a USB drive holding two homes, users/alice and users/bob,
// searched as alice, who owns hers and has no access to bob's (#2758).
type homesFixture struct {
	filesDir string
	branches map[string]SearchFilesParams
}

func newHomesFixture(t *testing.T, aliceFiles, bobFiles int) homesFixture {
	t.Helper()
	const serial = "USB-2758"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	for owner, count := range map[string]int{"alice": aliceFiles, "bob": bobFiles} {
		dir := filepath.Join(filesDir, "users", owner)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		for i := range count {
			if err := os.WriteFile(filepath.Join(dir, fmt.Sprintf("%s-%04d.txt", owner, i)), []byte("x"), 0o644); err != nil {
				t.Fatal(err)
			}
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
	alice, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "alice", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		DeviceSerial: serial,
		RelPath:      "users/alice",
		UserID:       sql.NullInt64{Int64: alice.ID, Valid: true},
		Level:        accessutil.Owner.String(),
	}); err != nil {
		t.Fatal(err)
	}
	loaded, err := accessutil.Load(accessutil.LoadParams{
		Ctx: ctx, Database: database, Storage: svc, Principal: accessutil.Principal{UserID: alice.ID},
	})
	if err != nil {
		t.Fatal(err)
	}
	branches := map[string]SearchFilesParams{
		"index":     {Index: index, Storage: svc},
		"vfs":       {Registry: registry, Storage: svc},
		"disk walk": {Storage: svc},
	}
	for name, params := range branches {
		params.Ctx = ctx
		params.Access = loaded.Access
		branches[name] = params
	}
	return homesFixture{filesDir: filesDir, branches: branches}
}

// An index match alice cannot read is never passed to stat, so its size and time
// are not even read on her behalf, and none of it comes back (#2758).
func TestSearchFilesNeverStatsUnreadableMatches(t *testing.T) {
	f := newHomesFixture(t, 2, 3)
	var statCalls []string
	statFile = func(name string) (os.FileInfo, error) {
		statCalls = append(statCalls, name)
		return os.Stat(name)
	}
	t.Cleanup(func() { statFile = os.Stat })

	params := f.branches["index"]
	params.Query = ".txt"
	result, err := SearchFiles(params)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Files) != 2 {
		t.Errorf("matches = %+v, want alice's two files", result.Files)
	}
	for _, file := range result.Files {
		if !strings.HasPrefix(filepath.ToSlash(file.DirPath), "users/alice/") {
			t.Errorf("returned %q from outside alice's home", file.DirPath)
		}
	}
	for _, name := range statCalls {
		if strings.Contains(filepath.ToSlash(name), "users/bob/") {
			t.Errorf("ran stat on %s, which alice cannot read", name)
		}
	}
}

// An empty query matches every file on the appliance; it answers nothing
// rather than walking all of them (#2758).
func TestSearchFilesEmptyQueryFindsNothing(t *testing.T) {
	f := newHomesFixture(t, 2, 0)
	for name, params := range f.branches {
		t.Run(name, func(t *testing.T) {
			for _, query := range []string{"", "   "} {
				params.Query = query
				result, err := SearchFiles(params)
				if err != nil {
					t.Fatal(err)
				}
				if result.Files == nil || len(result.Files) != 0 {
					t.Errorf("query %q: matches = %+v, want an empty list", query, result.Files)
				}
			}
		})
	}
}

// A search returns at most MaxSearchResults, and the cap counts only files
// the caller can read: bob's many matches do not crowd out alice's (#2758).
func TestSearchFilesCapsReadableMatches(t *testing.T) {
	f := newHomesFixture(t, MaxSearchResults+5, MaxSearchResults+5)
	for name, params := range f.branches {
		t.Run(name, func(t *testing.T) {
			params.Query = "alice-"
			result, err := SearchFiles(params)
			if err != nil {
				t.Fatal(err)
			}
			if len(result.Files) != MaxSearchResults {
				t.Errorf("got %d matches, want the cap of %d", len(result.Files), MaxSearchResults)
			}

			params.Query = ".txt"
			result, err = SearchFiles(params)
			if err != nil {
				t.Fatal(err)
			}
			for _, file := range result.Files {
				if !strings.HasPrefix(filepath.ToSlash(file.DirPath), "users/alice/") {
					t.Fatalf("returned %q from outside alice's home", file.DirPath)
				}
			}
			if len(result.Files) != MaxSearchResults {
				t.Errorf("got %d of alice's matches, want the cap of %d", len(result.Files), MaxSearchResults)
			}
		})
	}
}

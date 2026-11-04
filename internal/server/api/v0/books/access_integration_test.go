package v0_books_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_books "github.com/autobutler-org/quark/internal/server/api/v0/books"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory is the one
// the books walk reads under HOME.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// TestListBooks_Access lists only the books a non-admin can read, against a
// real files directory and a migrated database, while an admin sees every book
// (#1904).
func TestListBooks_Access(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	for _, rel := range []string{"shared/a.pdf", "private/b.epub"} {
		full := filepath.Join(filesDir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("book"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	database := dbtest.NewDB(t)
	ctx := context.Background()
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(systemDevice{})).
		WithVFSRegistry(internalRegistry(t)).
		WithDatabase(database)
	principal := accessutil.System

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_books.NewRouter())

	list := func() []string {
		t.Helper()
		w := doGet(engine, "/api/v0/books")
		var books []v0_books.BookJSON
		if err := json.Unmarshal(w.Body.Bytes(), &books); w.Code != http.StatusOK || err != nil {
			t.Fatalf("list = %d %s: %v", w.Code, w.Body.String(), err)
		}
		paths := make([]string, 0, len(books))
		for _, b := range books {
			paths = append(paths, filepath.ToSlash(b.RelPath))
		}
		slices.Sort(paths)
		return paths
	}

	if got := list(); len(got) != 2 {
		t.Errorf("admin books = %v, want both", got)
	}

	principal = accessutil.Principal{UserID: user.ID}
	if got := list(); len(got) != 0 {
		t.Errorf("books with no rows = %v, want none", got)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "shared",
		UserID:  sql.NullInt64{Int64: user.ID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	if got := list(); !slices.Equal(got, []string{"shared/a.pdf"}) {
		t.Errorf("books with a read share = %v, want [shared/a.pdf]", got)
	}
}

// A read grant on one drive does not reveal the same path on another. The
// book the grant names comes back with that drive's serial (#3712).
func TestListBooks_AccessOnSecondNamespace(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	internalFiles, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	usbMount := t.TempDir()
	const serial = "STICK"
	svc := storageutil.NewStorageService(driveDetector{devices: []storageutil.Device{
		{Name: "Internal", MountPoint: "/", IsInternal: true},
		{Name: "USB", MountPoint: usbMount, UsbInfo: serialUsb{serial: serial}},
	}})
	usbFiles, err := storageutil.GetFilesDirForDevice(usbMount)
	if err != nil {
		t.Fatal(err)
	}
	writeBook := func(dir, rel string) {
		t.Helper()
		full := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("book"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	writeBook(internalFiles, "shared/a.pdf")
	writeBook(usbFiles, "shared/a.pdf")
	writeBook(usbFiles, "library/novel.epub")

	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}

	database := dbtest.NewDB(t)
	ctx := context.Background()
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	grant := func(drive, rel string) {
		t.Helper()
		if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
			DeviceSerial: drive,
			RelPath:      rel,
			UserID:       sql.NullInt64{Int64: user.ID, Valid: true},
			Level:        accessutil.Read.String(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	grant("", "shared")
	grant(serial, "library")

	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithDatabase(database)
	principal := accessutil.Principal{UserID: user.ID}

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_books.NewRouter())

	w := doGet(engine, "/api/v0/books")
	var books []v0_books.BookJSON
	if err := json.Unmarshal(w.Body.Bytes(), &books); w.Code != http.StatusOK || err != nil {
		t.Fatalf("list = %d %s: %v", w.Code, w.Body.String(), err)
	}
	got := map[string]string{}
	for _, book := range books {
		got[book.DeviceSerial+"\t"+filepath.ToSlash(book.RelPath)] = book.DeviceSerial
	}
	want := map[string]string{
		"\tshared/a.pdf":                "",
		serial + "\tlibrary/novel.epub": serial,
	}
	if len(got) != len(want) {
		t.Fatalf("books = %v, want %v", got, want)
	}
	for key, drive := range want {
		if got[key] != drive {
			t.Errorf("%s deviceSerial = %q, want %q", key, got[key], drive)
		}
	}
}

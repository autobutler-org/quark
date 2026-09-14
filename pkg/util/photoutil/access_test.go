package photoutil_test

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// systemAccess is an admin's access, which filters nothing.
func systemAccess(t *testing.T) accessutil.Access {
	t.Helper()
	loaded, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access
}

// internalDevice is the internal drive at "/", whose files directory lives
// under HOME.
type internalDevice struct{}

func (internalDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// usbDetector presents a single USB drive with a serial, rooted at a temp dir.
type usbDetector struct {
	mountPoint string
	serial     string
}

func (d usbDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{
		Name:       "USB Disk",
		MountPoint: d.mountPoint,
		UsbInfo:    serialOnlyUsbDevice{serial: d.serial},
	}}, nil
}

// serialOnlyUsbDevice implements only GetSerial; any other call panics on the
// nil embedded interface.
type serialOnlyUsbDevice struct {
	storageutil.UsbDevice
	serial string
}

func (u serialOnlyUsbDevice) GetSerial() string { return u.serial }

// TestListPhotos_VFSCarriesTheSerial checks a photo listed through the VFS
// reports the drive it is on. Without the serial, thumbnails, metadata,
// favorites, albums and video actions for a USB photo resolve against the
// internal drive, and a non-admin's access to it is checked there too.
func TestListPhotos_VFSCarriesTheSerial(t *testing.T) {
	const serial = "USB-PHOTOS"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filepath.Join(filesDir, "trip"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "trip", "beach.jpg"), []byte("jpg"), 0o644); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(usbDetector{mountPoint: mountPoint, serial: serial})
	fsys := vfs.NewStorageServiceVFS(svc, "files")

	ctx := context.Background()
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		DeviceSerial: serial,
		RelPath:      "trip",
		UserID:       sql.NullInt64{Int64: user.ID, Valid: true},
		Level:        accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	member, err := accessutil.Load(accessutil.LoadParams{
		Ctx: ctx, Database: database, Storage: svc, Principal: accessutil.Principal{UserID: user.ID},
	})
	if err != nil {
		t.Fatal(err)
	}

	for name, access := range map[string]accessutil.Access{"admin": systemAccess(t), "member": member.Access} {
		t.Run(name, func(t *testing.T) {
			page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{Ctx: ctx, FS: fsys, Access: access, Offset: 0, Limit: 10})
			if err != nil {
				t.Fatal(err)
			}
			if len(page.Photos) != 1 {
				t.Fatalf("photos = %+v, want the one on the USB drive", page.Photos)
			}
			p := page.Photos[0]
			if p.Serial != serial {
				t.Errorf("Serial = %q, want %q", p.Serial, serial)
			}
			if !access.Check(p.Serial, p.RelPath, accessutil.Read).Readable {
				t.Errorf("the listed serial %q and path %q are not readable together", p.Serial, p.RelPath)
			}
		})
	}
}

// userAccess is the access of a non-admin granted read on each of paths, on
// the internal drive.
func userAccess(t *testing.T, database *db.DatabaseSqlc, paths ...string) accessutil.Access {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	ctx := context.Background()
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range paths {
		if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
			RelPath: p,
			UserID:  sql.NullInt64{Int64: user.ID, Valid: true},
			Level:   accessutil.Read.String(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	loaded, err := accessutil.Load(accessutil.LoadParams{
		Ctx:       ctx,
		Database:  database,
		Storage:   storageutil.NewStorageService(internalDevice{}),
		Principal: accessutil.Principal{UserID: user.ID},
	})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access
}

// TestListPhotos_FiltersBeforePaging drops unreadable photos before the page is
// cut, so a page stays full and Total counts only what the caller can see.
func TestListPhotos_FiltersBeforePaging(t *testing.T) {
	mem := newPhotoMemVFS(t, "shared/a.jpg", "shared/b.jpg", "private/c.jpg", "private/d.jpg")
	access := userAccess(t, dbtest.NewDB(t), "shared")

	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), FS: mem, Access: access, Offset: 0, Limit: 2,
	})
	if err != nil {
		t.Fatal(err)
	}
	got := make([]string, 0, len(page.Photos))
	for _, p := range page.Photos {
		got = append(got, p.RelPath)
	}
	slices.Sort(got)
	if page.Total != 2 || !slices.Equal(got, []string{"shared/a.jpg", "shared/b.jpg"}) {
		t.Errorf("got total %d and %v, want 2 and the two shared photos", page.Total, got)
	}
}

// TestListDuplicates_Filtered drops unreadable photos from every group and any
// group left with fewer than two, while an admin sees every group whole.
func TestListDuplicates_Filtered(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	for _, row := range []struct{ path, dhash, content string }{
		{"shared/a.jpg", "", "h1"},
		{"shared/b.jpg", "", "h1"},
		{"private/c.jpg", "", "h1"},
		{"shared/d.jpg", "", "h2"},
		{"private/e.jpg", "", "h2"},
		{"shared/n1.jpg", "0000000000000000", ""},
		{"private/n2.jpg", "0000000000000000", ""},
		{"shared/n3.jpg", "0000000000000001", ""},
	} {
		if err := database.Queries.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{
			RelPath:     row.path,
			Dhash:       sql.NullString{String: row.dhash, Valid: row.dhash != ""},
			ContentHash: sql.NullString{String: row.content, Valid: row.content != ""},
		}); err != nil {
			t.Fatal(err)
		}
	}
	sizes := func(access accessutil.Access) map[string][]string {
		t.Helper()
		result, err := photoutil.ListDuplicates(photoutil.ListDuplicatesParams{
			Ctx: ctx, Queries: database.Queries, Threshold: 10, Access: access,
		})
		if err != nil {
			t.Fatal(err)
		}
		groups := map[string][]string{}
		for _, g := range result.Groups {
			paths := make([]string, 0, len(g.Photos))
			for _, p := range g.Photos {
				paths = append(paths, p.RelPath)
			}
			slices.Sort(paths)
			groups[paths[0]] = paths
		}
		return groups
	}

	if got := sizes(systemAccess(t)); len(got) != 3 || len(got["private/c.jpg"]) != 3 || len(got["private/n2.jpg"]) != 3 {
		t.Errorf("admin groups = %v, want h1 and the near group whole, plus h2", got)
	}
	got := sizes(userAccess(t, database, "shared"))
	want := map[string][]string{
		"shared/a.jpg":  {"shared/a.jpg", "shared/b.jpg"},
		"shared/n1.jpg": {"shared/n1.jpg", "shared/n3.jpg"},
	}
	if len(got) != len(want) || !slices.Equal(got["shared/a.jpg"], want["shared/a.jpg"]) || !slices.Equal(got["shared/n1.jpg"], want["shared/n1.jpg"]) {
		t.Errorf("user groups = %v, want %v", got, want)
	}
}

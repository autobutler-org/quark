package photoutil_test

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const usbSerial = "USB-1"

// twoDevices is a registry holding the internal drive and one USB drive, each
// a MemVFS with the given files.
func twoDevices(t *testing.T, internal, usb map[string]string) vfs.Registry {
	t.Helper()
	registry := vfs.NewRegistry()
	for serial, files := range map[string]map[string]string{"": internal, usbSerial: usb} {
		fsys := vfs.NewMemVFS(vfs.FilesNamespace(serial))
		for p, content := range files {
			if err := fsys.Write(context.Background(), p, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
				t.Fatal(err)
			}
		}
		if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	return registry
}

// TestMetadata_ReadsTheDevicesFile: a photo's metadata used to be read from
// the internal drive whatever its serial (#2645), so a USB photo reported the
// size, date and Live Photo of whatever the internal drive held at that path.
func TestMetadata_ReadsTheDevicesFile(t *testing.T) {
	registry := twoDevices(t,
		map[string]string{"trip/a.jpg": "internal"},
		map[string]string{"trip/a.jpg": "the usb drive's photo", "trip/a.MOV": "video"},
	)
	database := dbtest.NewDB(t)
	params := photoutil.MetadataParams{
		Ctx: context.Background(), Queries: database.Queries, Registry: registry, RelPath: "trip/a.jpg",
	}

	params.Serial = usbSerial
	usb, err := photoutil.Metadata(params)
	if err != nil {
		t.Fatal(err)
	}
	if usb.FileSize != int64(len("the usb drive's photo")) || usb.LivePhotoVideoPath != "trip/a.MOV" {
		t.Errorf("usb metadata = size %d, live %q; want the usb drive's file", usb.FileSize, usb.LivePhotoVideoPath)
	}
	if time.Since(time.Unix(usb.MTime, 0)) > time.Hour {
		t.Errorf("usb mtime = %d, want the file's", usb.MTime)
	}

	params.Serial = ""
	internal, err := photoutil.Metadata(params)
	if err != nil {
		t.Fatal(err)
	}
	if internal.FileSize != int64(len("internal")) || internal.LivePhotoVideoPath != "" {
		t.Errorf("internal metadata = size %d, live %q; want the internal drive's file", internal.FileSize, internal.LivePhotoVideoPath)
	}
}

func TestMetadata_Errors(t *testing.T) {
	registry := twoDevices(t, map[string]string{"a.jpg": "x"}, nil)
	database := dbtest.NewDB(t)
	cases := []struct {
		name, serial, relPath string
		want                  error
	}{
		{"missing file", "", "gone.jpg", storageutil.ErrPathNotFound},
		// An unplugged drive's photo is missing, not the internal drive's.
		{"unknown device", "UNPLUGGED", "a.jpg", storageutil.ErrPathNotFound},
		{"the root", "", "/", photoutil.ErrInvalidRelPath},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := photoutil.Metadata(photoutil.MetadataParams{
				Ctx: context.Background(), Queries: database.Queries, Registry: registry,
				Serial: tc.serial, RelPath: tc.relPath,
			})
			if !errors.Is(err, tc.want) {
				t.Errorf("err = %v, want %v", err, tc.want)
			}
		})
	}
}

// TestListPhotos_MarksLivePhotos: the Live Photo flag came only from the disk
// walk the VFS listing replaced, so a listing through the VFS never set it.
func TestListPhotos_MarksLivePhotos(t *testing.T) {
	registry := twoDevices(t,
		map[string]string{"a.HEIC": "x", "a.mov": "v", "b.jpg": "x", "c.png": "x", "c.mov": "v", "d/e.jpg": "x"},
		map[string]string{"e.jpg": "x", "d/e.MOV": "v"},
	)
	page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t), Limit: 50,
	})
	if err != nil {
		t.Fatal(err)
	}
	live := map[string]bool{}
	for _, p := range page.Photos {
		live[p.Serial+"|"+p.RelPath] = p.HasLiveVideo
	}
	want := map[string]bool{
		"|a.HEIC": true, "|b.jpg": false, "|c.png": false, "|d/e.jpg": false,
		usbSerial + "|e.jpg": false,
	}
	if len(live) != len(want) {
		t.Fatalf("listed %v, want %v", live, want)
	}
	for k, v := range want {
		if got, ok := live[k]; !ok || got != v {
			t.Errorf("%s: live = %v (listed %v), want %v", k, got, ok, v)
		}
	}
}

func TestCopyPhoto_OnTheDevice(t *testing.T) {
	registry := twoDevices(t,
		map[string]string{"trip/a.jpg": "internal"},
		map[string]string{"trip/a.jpg": "usb", "trip/a_copy.jpg": "taken"},
	)
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	defer unsubscribe()

	result, err := photoutil.CopyPhoto(photoutil.CopyPhotoParams{
		Ctx: context.Background(), Registry: registry, EventBus: bus, Serial: usbSerial, RelPath: "/trip/a.jpg",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.RelPath != "trip/a_copy_2.jpg" {
		t.Errorf("copy = %q, want trip/a_copy_2.jpg", result.RelPath)
	}
	usb, _ := photoutil.DeviceFS(registry, usbSerial)
	if got := readAll(t, usb, result.RelPath); got != "usb" {
		t.Errorf("copy holds %q, want the usb photo", got)
	}
	internal, _ := photoutil.DeviceFS(registry, "")
	if _, err := internal.Stat(context.Background(), result.RelPath); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("the copy landed on the internal drive too: %v", err)
	}
	select {
	case e := <-events:
		if e.Kind != eventbus.EventUpload || e.Path != result.RelPath || e.DeviceSerial != usbSerial {
			t.Errorf("event = %+v, want an upload of the copy on %s", e, usbSerial)
		}
	case <-time.After(time.Second):
		t.Error("no event for the copy")
	}

	for _, serial := range []string{"", "UNPLUGGED"} {
		_, err := photoutil.CopyPhoto(photoutil.CopyPhotoParams{
			Ctx: context.Background(), Registry: registry, Serial: serial, RelPath: "gone.jpg",
		})
		if !errors.Is(err, vfs.ErrNotFound) {
			t.Errorf("serial %q: err = %v, want vfs.ErrNotFound", serial, err)
		}
	}
}

func TestExistsIn(t *testing.T) {
	registry := twoDevices(t, map[string]string{"a.jpg": "x"}, map[string]string{"b.jpg": "x"})
	exists := photoutil.ExistsIn(context.Background(), registry)
	for _, tc := range []struct {
		serial, relPath string
		want            bool
	}{
		{"", "a.jpg", true},
		{"", "b.jpg", false},
		{usbSerial, "b.jpg", true},
		{usbSerial, "a.jpg", false},
		{"UNPLUGGED", "a.jpg", false},
	} {
		if got := exists(tc.serial, tc.relPath); got != tc.want {
			t.Errorf("exists(%q, %q) = %v, want %v", tc.serial, tc.relPath, got, tc.want)
		}
	}
}

// TestBackfillHashes_ThroughTheVFS: the backfill used to resolve each photo to
// a disk path and open it there; a namespace with no disk behind it now
// hashes the same.
func TestBackfillHashes_ThroughTheVFS(t *testing.T) {
	registry := twoDevices(t, nil, map[string]string{"a.jpg": string(photoJPEG(t, 1))})
	database := dbtest.NewDB(t)
	res, err := photoutil.BackfillHashes(photoutil.BackfillHashesParams{
		Ctx: context.Background(), Queries: database.Queries, Registry: registry,
	})
	if err != nil {
		t.Fatal(err)
	}
	if res != (photoutil.BackfillHashesResult{Scanned: 1, Hashed: 1}) {
		t.Fatalf("result = %+v, want one photo hashed", res)
	}
	if row := hashRows(t, database.Queries)["a.jpg"]; row.DeviceSerial != usbSerial || !row.Dhash.Valid || !row.ContentHash.Valid {
		t.Errorf("row = %+v, want both hashes on %s", row, usbSerial)
	}
}

func readAll(t *testing.T, fsys vfs.VFS, p string) string {
	t.Helper()
	f, err := fsys.Open(context.Background(), p)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	data, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

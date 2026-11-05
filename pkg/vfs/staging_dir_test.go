package vfs_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// TestStagingDirSitsBesideTheDevicesFiles checks a device namespace stages on
// its own drive, beside its files directory the way its trash is, outside the
// tree a listing walks (#3970), and refuses a name that is not one element.
func TestStagingDirSitsBesideTheDevicesFiles(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device(""), usb.device("A")))
	ctx := context.Background()

	for _, tc := range []struct {
		fsys     vfs.FileMover
		filesDir string
	}{
		{vfs.NewDeviceStorageServiceVFS(svc, "A"), usb.filesDir},
		{vfs.NewDeviceStorageServiceVFS(svc, ""), internal.filesDir},
	} {
		dir, err := tc.fsys.StagingDir(ctx, "upload-sessions")
		if err != nil {
			t.Fatalf("StagingDir: %v", err)
		}
		if want := filepath.Join(filepath.Dir(tc.filesDir), "tmp", "upload-sessions"); dir != want {
			t.Errorf("StagingDir = %s, want %s", dir, want)
		}
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			t.Errorf("StagingDir did not create %s: %v", dir, err)
		}
		for _, name := range []string{"", ".", "..", "../files", "a/b"} {
			if _, err := tc.fsys.StagingDir(ctx, name); !errors.Is(err, vfs.ErrPermissionDenied) {
				t.Errorf("StagingDir(%q) = %v, want ErrPermissionDenied", name, err)
			}
		}
	}
}

// TestStagingDirOfAGoneDevice checks a namespace whose drive was unplugged
// answers ErrNotFound rather than staging on the internal drive.
func TestStagingDirOfAGoneDevice(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	detector := newDevicesDetector(internal.device(""), usb.device("A"))
	svc := storageutil.NewStorageService(detector)
	stale := vfs.NewDeviceStorageServiceVFS(svc, "A")
	detector.set(internal.device(""))
	svc.InvalidateDeviceCache()

	if dir, err := stale.StagingDir(context.Background(), "upload-sessions"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("StagingDir on a gone device = %q, %v, want ErrNotFound", dir, err)
	}
}

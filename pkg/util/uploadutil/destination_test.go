package uploadutil_test

import (
	"bytes"
	"context"
	"errors"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// Every upload, to any device, lands through the device's files namespace
// (#2643). These pin what the StorageService writer it replaced guaranteed,
// against a USB drive's namespace: refusal of a taken name, keepBoth's
// numbered names, Created on an overwrite, and the sidecar hand-off.

const deviceSerial = "USB-UPLOAD"

// usbDrive is a USB drive known only by its serial.
type usbDrive struct {
	storageutil.UsbDevice
}

func (usbDrive) GetSerial() string { return deviceSerial }

// usbDetector reports one USB drive mounted at mountPoint.
type usbDetector struct{ mountPoint string }

func (d usbDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "USB", MountPoint: d.mountPoint, UsbInfo: usbDrive{}}}, nil
}

// newDeviceDestination registers the USB drive's namespace the way
// production does and returns a destination over it, with the drive's files
// directory.
func newDeviceDestination(t *testing.T) (uploadutil.Destination, string) {
	t.Helper()
	mountPoint := t.TempDir()
	svc := storageutil.NewStorageService(usbDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}
	return uploadutil.Destination{Registry: registry, EventBus: eventbus.New()},
		storageutil.ConstructFilesDir(storageutil.GetDataDirForDevice(mountPoint))
}

// multipartBody builds a body with one "files" part per name, each holding
// content, in order.
func multipartBody(t *testing.T, content string, names ...string) *multipart.Reader {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for _, name := range names {
		part, err := mw.CreateFormFile("files", name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := part.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return multipart.NewReader(&buf, mw.Boundary())
}

func writeDeviceFile(t *testing.T, filesDir, rel, content string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readDeviceFile(t *testing.T, filesDir, rel string) string {
	t.Helper()
	got, err := os.ReadFile(filepath.Join(filesDir, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	return string(got)
}

func TestWriteMultipartToDeviceLandsInRootDir(t *testing.T) {
	dest, filesDir := newDeviceDestination(t)
	fsys := dest.FilesVFS(deviceSerial)
	if fsys == nil {
		t.Fatal("the device has no files namespace")
	}

	result, err := uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
		Ctx: context.Background(), FS: fsys, Reader: multipartBody(t, "nested file", "notes.txt"), RootDir: "docs/2024",
	})
	if err != nil {
		t.Fatalf("WriteMultipartVFS: %v", err)
	}
	if got := readDeviceFile(t, filesDir, "docs/2024/notes.txt"); got != "nested file" {
		t.Errorf("notes.txt holds %q", got)
	}
	want := uploadutil.UploadedFile{Path: "docs/2024/notes.txt", Created: true, SourceName: "notes.txt"}
	if len(result.Written) != 1 || result.Written[0] != want {
		t.Errorf("wrote %+v, want [%+v]", result.Written, want)
	}
}

// A taken name is the caller's to resolve (#2016): without Overwrite or
// KeepBoth the upload is refused and nothing is written, not renamed.
func TestWriteMultipartToDeviceRefusesATakenName(t *testing.T) {
	dest, filesDir := newDeviceDestination(t)
	writeDeviceFile(t, filesDir, "file.txt", "old")

	result, err := uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
		Ctx: context.Background(), FS: dest.FilesVFS(deviceSerial), Reader: multipartBody(t, "new", "file.txt"),
	})
	if !errors.Is(err, vfs.ErrConflict) {
		t.Fatalf("upload over a taken name returned %v, want vfs.ErrConflict", err)
	}
	if len(result.Written) != 0 {
		t.Errorf("a refused upload reports writing %+v", result.Written)
	}
	if got := readDeviceFile(t, filesDir, "file.txt"); got != "old" {
		t.Errorf("the original now reads %q", got)
	}
	if _, err := os.Stat(filepath.Join(filesDir, "file_(1).txt")); !os.IsNotExist(err) {
		t.Errorf("a refused upload was renamed instead: %v", err)
	}
}

// The names the access layer grants ownership on (#1903): keeping both
// reports the name the file really landed under, and an overwrite reports
// that it created nothing.
func TestWriteMultipartToDeviceReportsWhatItWrote(t *testing.T) {
	dest, filesDir := newDeviceDestination(t)
	writeDeviceFile(t, filesDir, "docs/file.txt", "old")
	upload := func(overwrite bool) []uploadutil.UploadedFile {
		t.Helper()
		result, err := uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
			Ctx: context.Background(), FS: dest.FilesVFS(deviceSerial), Reader: multipartBody(t, "new", "file.txt"),
			RootDir: "docs", Overwrite: overwrite, KeepBoth: !overwrite,
		})
		if err != nil {
			t.Fatalf("WriteMultipartVFS: %v", err)
		}
		return result.Written
	}

	renamed := upload(false)
	if want := (uploadutil.UploadedFile{Path: "docs/file_(1).txt", Created: true, SourceName: "file.txt"}); len(renamed) != 1 || renamed[0] != want {
		t.Errorf("keepBoth wrote %+v, want [%+v]", renamed, want)
	}
	if got := readDeviceFile(t, filesDir, "docs/file.txt"); got != "old" {
		t.Errorf("keepBoth replaced the original, which now reads %q", got)
	}
	replaced := upload(true)
	if want := (uploadutil.UploadedFile{Path: "docs/file.txt", Created: false, SourceName: "file.txt"}); len(replaced) != 1 || replaced[0] != want {
		t.Errorf("overwrite wrote %+v, want [%+v]", replaced, want)
	}
	if got := readDeviceFile(t, filesDir, "docs/file.txt"); got != "new" {
		t.Errorf("overwrite left %q", got)
	}
}

// A part that is not a file is handed to the sidecar with the files written
// before it (#2379).
func TestWriteMultipartHandsSidecarsTheFilesSoFar(t *testing.T) {
	dest, _ := newDeviceDestination(t)
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for _, p := range []struct{ form, name string }{{"files", "a.mov"}, {"thumbnail", "a.mov"}, {"files", "b.mov"}} {
		w, err := mw.CreateFormFile(p.form, p.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte("x")); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}

	var seen [][]uploadutil.UploadedFile
	_, err := uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
		Ctx: context.Background(), FS: dest.FilesVFS(deviceSerial), Reader: multipart.NewReader(&buf, mw.Boundary()),
		Sidecar: func(_ *multipart.Part, written []uploadutil.UploadedFile) {
			seen = append(seen, append([]uploadutil.UploadedFile(nil), written...))
		},
	})
	if err != nil {
		t.Fatalf("WriteMultipartVFS: %v", err)
	}
	if len(seen) != 1 || len(seen[0]) != 1 || seen[0][0].Path != "a.mov" {
		t.Errorf("sidecar saw %+v, want one call with a.mov written", seen)
	}
}

// A body that ends inside a part is ErrInvalidBody, and leaves nothing under
// the part's name.
func TestWriteMultipartCutShortIsInvalidBody(t *testing.T) {
	dest, filesDir := newDeviceDestination(t)
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	w, err := mw.CreateFormFile("files", "cut.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte(strings.Repeat("x", 64))); err != nil {
		t.Fatal(err)
	}
	cut := bytes.NewReader(buf.Bytes()[:buf.Len()-8])

	_, err = uploadutil.WriteMultipartVFS(uploadutil.WriteMultipartParams{
		Ctx: context.Background(), FS: dest.FilesVFS(deviceSerial), Reader: multipart.NewReader(cut, mw.Boundary()),
	})
	if !errors.Is(err, uploadutil.ErrInvalidBody) {
		t.Fatalf("a cut-short body returned %v, want ErrInvalidBody", err)
	}
	if _, err := os.Stat(filepath.Join(filesDir, "cut.txt")); !os.IsNotExist(err) {
		t.Errorf("a cut-short part left a file under its name: %v", err)
	}
}

// WriteFile to a device lands on the device and announces it with the
// device's serial; a serial with no namespace is ErrNoDestination.
func TestWriteFileToDevice(t *testing.T) {
	dest, filesDir := newDeviceDestination(t)
	events, unsubscribe := dest.EventBus.Subscribe(t.Name())
	defer unsubscribe()

	result, err := dest.WriteFile(uploadutil.WriteFileParams{
		Ctx: context.Background(), Reader: strings.NewReader("staged"), RootDir: "clips", FileName: "big.bin", Serial: deviceSerial,
	})
	if err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	if result.Path != "clips/big.bin" || !result.Created {
		t.Errorf("WriteFile reported %+v", result)
	}
	if got := readDeviceFile(t, filesDir, "clips/big.bin"); got != "staged" {
		t.Errorf("big.bin holds %q", got)
	}
	select {
	case e := <-events:
		if e.Kind != eventbus.EventUpload || e.DeviceSerial != deviceSerial {
			t.Errorf("published %+v, want an upload event for %s", e, deviceSerial)
		}
	default:
		t.Error("no upload event was published")
	}

	_, err = dest.WriteFile(uploadutil.WriteFileParams{
		Ctx: context.Background(), Reader: strings.NewReader("lost"), FileName: "a.bin", Serial: "GONE",
	})
	if !errors.Is(err, uploadutil.ErrNoDestination) {
		t.Errorf("WriteFile to an unknown serial returned %v, want ErrNoDestination", err)
	}
	if dest.Writable("GONE") {
		t.Error("an unknown serial is reported writable")
	}
}

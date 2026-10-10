package v0_files_test

import (
	"bytes"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// testUsbSerial names the USB drive the device-scoped upload tests write to.
const testUsbSerial = "USB1"

// deviceUploadHarness is an internal drive and a USB drive, each with its own
// files namespace the way production registers them (#2639), so an upload with
// ?serial= can be checked to land on the device it names and nowhere else.
type deviceUploadHarness struct {
	engine      *gin.Engine
	internalDir string
	usbDir      string
	events      <-chan eventbus.Event
}

// newDeviceUploadDeps builds the dependency graph behind the harness, for a
// test that has to add to it. It returns the internal and USB files
// directories.
func newDeviceUploadDeps(t *testing.T) (deputil.Dependencies, string, string) {
	t.Helper()
	mountPoint := t.TempDir()
	usbMount := t.TempDir()
	internalDir := filepath.Join(mountPoint, "quark", "data", "files")
	usbDir := filepath.Join(usbMount, "quark", "data", "files")
	for _, dir := range []string{internalDir, usbDir} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	svc := storageutil.NewStorageService(&fakeDetector{
		mountPoint: mountPoint,
		extra: []storageutil.Device{{
			Name: "USB", MountPoint: usbMount, UsbInfo: fakeUsb{serial: testUsbSerial},
		}},
	})
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(newFilesRegistry(t, svc)).
		WithEventBus(eventbus.New()).
		WithUploadSessions(newTestSessionStore(mountPoint))
	return deps, internalDir, usbDir
}

// newFilesRegistry registers a files namespace for every managed device of
// svc, the way deputil.DefaultDependencies does.
func newFilesRegistry(t *testing.T, svc *storageutil.StorageService) vfs.Registry {
	t.Helper()
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}
	return registry
}

func newDeviceUploadHarness(t *testing.T) deviceUploadHarness {
	t.Helper()
	deps, internalDir, usbDir := newDeviceUploadDeps(t)
	events, unsubscribe := deps.EventBus().Subscribe(t.Name())
	t.Cleanup(unsubscribe)
	return deviceUploadHarness{engine: newEngineForDeps(deps), internalDir: internalDir, usbDir: usbDir, events: events}
}

// uploadTarget is a device an upload test runs against: the engine, the files
// directory of the device the requests name, and its serial, empty for the
// internal drive.
type uploadTarget struct {
	name   string
	serial string
	engine func(t *testing.T) (*gin.Engine, string)
}

// uploadTargets are the internal drive and a USB drive, which every upload
// path has to treat alike (#2643).
var uploadTargets = []uploadTarget{
	{name: "internal", engine: newStorageVFSTestEngine},
	{name: "device", serial: testUsbSerial, engine: func(t *testing.T) (*gin.Engine, string) {
		h := newDeviceUploadHarness(t)
		return h.engine, h.usbDir
	}},
}

// on adds the target's serial to an upload URL.
func (u uploadTarget) on(url string) string {
	if u.serial == "" {
		return url
	}
	sep := "?"
	if strings.Contains(url, "?") {
		sep = "&"
	}
	return url + sep + "serial=" + u.serial
}

// session adds the target's serial to a session request.
func (u uploadTarget) session(body map[string]any) map[string]any {
	if u.serial != "" {
		body["serial"] = u.serial
	}
	return body
}

// nextUpload returns the next upload event, failing if none was published.
func (h deviceUploadHarness) nextUpload(t *testing.T) eventbus.Event {
	t.Helper()
	for {
		select {
		case e := <-h.events:
			if e.Kind == eventbus.EventUpload {
				return e
			}
		default:
			t.Fatal("no upload event was published")
			return eventbus.Event{}
		}
	}
}

func assertContent(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("expected a file at %s: %v", path, err)
	}
	if string(got) != want {
		t.Errorf("%s holds %q, want %q", path, got, want)
	}
}

func assertAbsent(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("%s exists (stat err %v); nothing should have been written there", path, err)
	}
}

// A multipart upload to a device serial lands in that device's namespace, and
// the event that announces it names the device (#2643).
func TestUploadToDeviceLandsOnTheDevice(t *testing.T) {
	t.Parallel()
	h := newDeviceUploadHarness(t)

	w := uploadFile(t, h.engine, "/api/v0/files/upload/docs?serial="+testUsbSerial, "a.txt", "on usb")
	if w.Code != http.StatusOK {
		t.Fatalf("upload returned %d: %s", w.Code, w.Body.String())
	}
	assertContent(t, filepath.Join(h.usbDir, "docs", "a.txt"), "on usb")
	assertAbsent(t, filepath.Join(h.internalDir, "docs", "a.txt"))
	if e := h.nextUpload(t); e.DeviceSerial != testUsbSerial {
		t.Errorf("upload event carries serial %q, want %q", e.DeviceSerial, testUsbSerial)
	}
}

// A serial with no namespace is not a device to upload to. The StorageService
// used to resolve an unknown serial to the internal drive, so an admin's
// upload to a drive that had just been unplugged landed somewhere else.
func TestUploadToUnknownDeviceIsNotFound(t *testing.T) {
	t.Parallel()
	h := newDeviceUploadHarness(t)

	w := uploadFile(t, h.engine, "/api/v0/files/upload?serial=GONE", "a.txt", "lost")
	if w.Code != http.StatusNotFound {
		t.Fatalf("upload returned %d, want 404: %s", w.Code, w.Body.String())
	}
	assertAbsent(t, filepath.Join(h.internalDir, "a.txt"))
}

// A device upload refuses a taken name and keeps both on request, the same
// as the internal drive (#2016).
func TestUploadToDeviceConflict(t *testing.T) {
	t.Parallel()
	h := newDeviceUploadHarness(t)
	base := "/api/v0/files/upload?serial=" + testUsbSerial

	if w := uploadFile(t, h.engine, base, "a.txt", "first"); w.Code != http.StatusOK {
		t.Fatalf("first upload returned %d: %s", w.Code, w.Body.String())
	}
	if w := uploadFile(t, h.engine, base, "a.txt", "second"); w.Code != http.StatusConflict {
		t.Fatalf("taken name returned %d, want 409: %s", w.Code, w.Body.String())
	}
	if w := uploadFile(t, h.engine, base+"&keepBoth=true", "a.txt", "both"); w.Code != http.StatusOK {
		t.Fatalf("keepBoth returned %d: %s", w.Code, w.Body.String())
	}
	if w := uploadFile(t, h.engine, base+"&overwrite=true", "a.txt", "replaced"); w.Code != http.StatusOK {
		t.Fatalf("overwrite returned %d: %s", w.Code, w.Body.String())
	}
	assertContent(t, filepath.Join(h.usbDir, "a.txt"), "replaced")
	assertContent(t, filepath.Join(h.usbDir, "a_(1).txt"), "both")
}

// A chunked upload to a device serial commits into that device's namespace.
func TestUploadSessionToDeviceLandsOnTheDevice(t *testing.T) {
	t.Parallel()
	h := newDeviceUploadHarness(t)
	content := []byte("chunked onto the usb drive")

	w := openSession(t, h.engine, map[string]any{
		"rootDir": "docs", "fileName": "big.bin", "totalSize": len(content), "serial": testUsbSerial,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", w.Code, w.Body.String())
	}
	w = putSlice(t, h.engine, decodeSession(t, w).SessionID, content, 0, len(content))
	if w.Code != http.StatusOK {
		t.Fatalf("chunk returned %d: %s", w.Code, w.Body.String())
	}
	if got := decodeSession(t, w); !got.Complete || got.Path != "docs/big.bin" {
		t.Errorf("commit reported %+v, want complete at docs/big.bin", got)
	}
	assertContent(t, filepath.Join(h.usbDir, "docs", "big.bin"), string(content))
	assertAbsent(t, filepath.Join(h.internalDir, "docs", "big.bin"))
	if e := h.nextUpload(t); e.DeviceSerial != testUsbSerial {
		t.Errorf("upload event carries serial %q, want %q", e.DeviceSerial, testUsbSerial)
	}
}

// A session for a serial with no namespace has nowhere to land, so it is
// refused before a byte is sent.
func TestUploadSessionToUnknownDeviceIsNotFound(t *testing.T) {
	t.Parallel()
	h := newDeviceUploadHarness(t)

	w := openSession(t, h.engine, map[string]any{"fileName": "a.bin", "totalSize": 4, "serial": "GONE"})
	if w.Code != http.StatusNotFound {
		t.Fatalf("open session returned %d, want 404: %s", w.Code, w.Body.String())
	}
}

// A body cut off in the middle of a file is the client's fault, and says so;
// nothing is left under the file's name. The StorageService writer answered
// 400, and the VFS writer has to as well now that it takes every upload.
func TestUploadTruncatedBodyIsBadRequest(t *testing.T) {
	t.Parallel()
	h := newDeviceUploadHarness(t)

	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, err := mw.CreateFormFile("files", "cut.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(fw, "the first half and the second half"); err != nil {
		t.Fatal(err)
	}
	// No closing boundary: the connection dropped partway through the file.
	body := buf.Bytes()[:buf.Len()-10]

	w := doRequest(h.engine, http.MethodPost, "/api/v0/files/upload?serial="+testUsbSerial, bytes.NewReader(body), mw.FormDataContentType())
	if w.Code != http.StatusBadRequest {
		t.Fatalf("truncated upload returned %d, want 400: %s", w.Code, w.Body.String())
	}
	assertAbsent(t, filepath.Join(h.usbDir, "cut.txt"))
}

package v0_files_test

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// The /files routes serve a device through its own namespace, the way they
// serve the internal drive (#2642). These cases name the USB drive of
// newDeviceUploadHarness with ?serial=.

// nextEvent waits for the next event on the bus, failing if none comes.
func (h deviceUploadHarness) nextEvent(t *testing.T) eventbus.Event {
	t.Helper()
	select {
	case e := <-h.events:
		return e
	case <-time.After(2 * time.Second):
		t.Fatal("no event was published")
		return eventbus.Event{}
	}
}

// moveBetween moves oldPath on oldSerial to newPath on newSerial.
func (h deviceUploadHarness) moveBetween(oldSerial, oldPath, newSerial, newPath string) (int, string) {
	body, _ := json.Marshal(map[string]string{
		"oldFilePath": oldPath, "newFilePath": newPath,
		"oldDeviceSerial": oldSerial, "newDeviceSerial": newSerial,
	})
	w := doRequest(h.engine, http.MethodPut, "/api/v0/files", bytes.NewReader(body), "application/json")
	return w.Code, w.Body.String()
}

// The stat handler dropped the serial and stat-ed the internal drive.
func TestDevice_StatReadsTheNamedDevice(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeFixture(t, h.usbDir, "usb-only.qdoc")
	if err := os.MkdirAll(filepath.Join(h.usbDir, "album.jpg"), 0o755); err != nil {
		t.Fatal(err)
	}

	w := doRequest(h.engine, http.MethodGet, "/api/v0/files/stat?filePath=usb-only.qdoc&serial="+testUsbSerial, nil, "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"fileType":"qdoc"`) {
		t.Errorf("stat on the device = %d %s, want 200 qdoc", w.Code, w.Body.String())
	}
	w = doRequest(h.engine, http.MethodGet, "/api/v0/files/stat?filePath=album.jpg&serial="+testUsbSerial, nil, "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"fileType":"folder"`) {
		t.Errorf("stat of a device folder named like an image = %d %s, want 200 folder", w.Code, w.Body.String())
	}
	for _, url := range []string{
		"/api/v0/files/stat?filePath=usb-only.qdoc",
		"/api/v0/files/stat?filePath=usb-only.qdoc&serial=NOPE",
	} {
		if w := doRequest(h.engine, http.MethodGet, url, nil, ""); w.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", url, w.Code)
		}
	}
}

// A file on the device downloads whole and by range, through the same
// http.ServeContent the internal drive uses.
func TestDevice_DownloadServesRanges(t *testing.T) {
	h := newDeviceUploadHarness(t)
	const content = "0123456789abcdef"
	if err := os.WriteFile(filepath.Join(h.usbDir, "clip.mp4"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	url := "/api/v0/files/download?filePath=clip.mp4&serial=" + testUsbSerial

	w := doRequest(h.engine, http.MethodGet, url, nil, "")
	if w.Code != http.StatusOK || w.Body.String() != content {
		t.Fatalf("download = %d %q, want 200 %q", w.Code, w.Body.String(), content)
	}
	if got := w.Header().Get("Content-Type"); got != "video/mp4" {
		t.Errorf("Content-Type = %q, want video/mp4", got)
	}

	req := httptest.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Range", "bytes=4-7")
	rec := httptest.NewRecorder()
	h.engine.ServeHTTP(rec, req)
	if rec.Code != http.StatusPartialContent || rec.Body.String() != "4567" {
		t.Errorf("range = %d %q, want 206 %q", rec.Code, rec.Body.String(), "4567")
	}
	if got := rec.Header().Get("Content-Range"); got != "bytes 4-7/16" {
		t.Errorf("Content-Range = %q, want bytes 4-7/16", got)
	}
}

// A device folder zips through its namespace, so it keeps to what the
// caller may read the way the internal drive's does (#1903), and the
// storage layer's own names stay out of it.
func TestDownloadDeviceFolderKeepsToWhatTheCallerReads(t *testing.T) {
	usbMount := t.TempDir()
	h := newAccessHarness(t, false, storageutil.Device{
		Name: "USB", MountPoint: usbMount, UsbInfo: fakeUsb{serial: testUsbSerial},
	})
	usbDir := filepath.Join(usbMount, "quark", "data", "files")
	writeFixture(t, usbDir, "Photos/shared/a.txt")
	writeFixture(t, usbDir, "Photos/private/b.txt")
	writeFixture(t, usbDir, "Photos/shared/"+storageutil.WriteTempPrefix+"partial")
	writeFixture(t, usbDir, "secret.txt")
	if err := os.Symlink(filepath.Join(usbDir, "secret.txt"), filepath.Join(usbDir, "Photos", "shared", "link.txt")); err != nil {
		t.Fatal(err)
	}
	grantOn(t, h, testUsbSerial, "Photos/shared", accessutil.Read)

	w := h.get("/api/v0/files/download?filePath=Photos/shared&serial=" + testUsbSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("folder download = %d: %s", w.Code, w.Body.String())
	}
	if want := []string{"shared/a.txt"}; !slices.Equal(zipNames(t, w.Body.Bytes()), want) {
		t.Errorf("zipped entries = %v, want %v", zipNames(t, w.Body.Bytes()), want)
	}

	// Photos itself bob only passes through on the way to the share.
	if w := h.get("/api/v0/files/download?filePath=Photos&serial=" + testUsbSerial); w.Code != http.StatusNotFound {
		t.Errorf("download of a folder bob only passes through = %d, want 404", w.Code)
	}
}

// A file moves from the internal drive to a device and back, landing whole
// under its new name and leaving nothing where it was. The event names the
// device it went to.
func TestDevice_MoveFileAcrossDevices(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeFixture(t, h.internalDir, "docs/report.txt")

	if code, body := h.moveBetween("", "docs/report.txt", testUsbSerial, "archive/report.txt"); code != http.StatusOK {
		t.Fatalf("move to the device = %d %s", code, body)
	}
	assertContent(t, filepath.Join(h.usbDir, "archive", "report.txt"), "fixture docs/report.txt")
	assertAbsent(t, filepath.Join(h.internalDir, "docs", "report.txt"))
	assertNoTempFiles(t, h.usbDir)
	if e := h.nextEvent(t); e.Kind != eventbus.EventMove || e.DeviceSerial != testUsbSerial || e.NewPath != "archive/report.txt" {
		t.Errorf("event = %+v, want a move onto %s", e, testUsbSerial)
	}

	if code, body := h.moveBetween(testUsbSerial, "archive/report.txt", "", "report.txt"); code != http.StatusOK {
		t.Fatalf("move back = %d %s", code, body)
	}
	assertContent(t, filepath.Join(h.internalDir, "report.txt"), "fixture docs/report.txt")
	assertAbsent(t, filepath.Join(h.usbDir, "archive", "report.txt"))
}

// A folder crosses devices too: the copy it used to try opened the folder as
// a file and failed.
func TestDevice_MoveFolderAcrossDevices(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeFixture(t, h.internalDir, "trip/day1/a.jpg")
	writeFixture(t, h.internalDir, "trip/day2/b.jpg")
	writeFixture(t, h.internalDir, "trip/notes.txt")
	if err := os.MkdirAll(filepath.Join(h.internalDir, "trip", "empty"), 0o755); err != nil {
		t.Fatal(err)
	}

	if code, body := h.moveBetween("", "trip", testUsbSerial, "Trips/trip"); code != http.StatusOK {
		t.Fatalf("move = %d %s", code, body)
	}
	for _, rel := range []string{"trip/day1/a.jpg", "trip/day2/b.jpg", "trip/notes.txt"} {
		assertContent(t, filepath.Join(h.usbDir, "Trips", filepath.FromSlash(rel)), "fixture "+rel)
	}
	if fi, err := os.Stat(filepath.Join(h.usbDir, "Trips", "trip", "empty")); err != nil || !fi.IsDir() {
		t.Errorf("the empty folder did not come along: %v", err)
	}
	assertAbsent(t, filepath.Join(h.internalDir, "trip"))
	assertNoTempFiles(t, h.usbDir)
}

// A folder moved onto one already on the device is refused before anything is
// copied, as a rename onto it would be, and both stay as they were.
func TestDevice_MoveFolderOntoATakenNameIsAConflict(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeFixture(t, h.internalDir, "trip/a.txt")
	writeFixture(t, h.usbDir, "trip/b.txt")

	if code, body := h.moveBetween("", "trip", testUsbSerial, "trip"); code == http.StatusOK {
		t.Fatalf("move onto a taken folder = %d %s, want a refusal", code, body)
	}
	assertContent(t, filepath.Join(h.internalDir, "trip", "a.txt"), "fixture trip/a.txt")
	assertAbsent(t, filepath.Join(h.usbDir, "trip", "a.txt"))
}

// A folder whose copy fails partway keeps its source, and no file under the
// destination is ever half written: each lands under its name only once it
// is whole.
func TestDevice_MoveFolderThatFailsPartwayKeepsTheSource(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads a file whatever its mode")
	}
	h := newDeviceUploadHarness(t)
	writeFixture(t, h.internalDir, "trip/a.txt")
	writeFixture(t, h.internalDir, "trip/z.txt")
	locked := filepath.Join(h.internalDir, "trip", "z.txt")
	if err := os.Chmod(locked, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o644) })

	if code, body := h.moveBetween("", "trip", testUsbSerial, "trip"); code == http.StatusOK {
		t.Fatalf("move with an unreadable file = %d %s, want a failure", code, body)
	}
	assertContent(t, filepath.Join(h.internalDir, "trip", "a.txt"), "fixture trip/a.txt")
	if _, err := os.Lstat(locked); err != nil {
		t.Errorf("the source lost %s: %v", locked, err)
	}
	assertAbsent(t, filepath.Join(h.usbDir, "trip", "z.txt"))
	assertNoTempFiles(t, h.usbDir)
}

// A new folder on a device is made there and announced with its serial.
func TestDevice_NewFolderPublishesTheSerial(t *testing.T) {
	h := newDeviceUploadHarness(t)
	w := doRequest(h.engine, http.MethodPost, "/api/v0/files/folder/?serial="+testUsbSerial,
		strings.NewReader("folderName=Projects"), "application/x-www-form-urlencoded")
	if w.Code/100 != 2 {
		t.Fatalf("new folder = %d %s", w.Code, w.Body.String())
	}
	if fi, err := os.Stat(filepath.Join(h.usbDir, "Projects")); err != nil || !fi.IsDir() {
		t.Fatalf("Projects was not made on the device: %v", err)
	}
	assertAbsent(t, filepath.Join(h.internalDir, "Projects"))
	if e := h.nextEvent(t); e.Kind != eventbus.EventNewFolder || e.DeviceSerial != testUsbSerial {
		t.Errorf("event = %+v, want a new folder on %s", e, testUsbSerial)
	}
}

// grantOn gives the harness's user level on rel of the device serial names.
func grantOn(t *testing.T, h accessHarness, serial, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		DeviceSerial: serial,
		RelPath:      accessutil.Canonical(rel),
		UserID:       sql.NullInt64{Int64: h.userID, Valid: true},
		Level:        level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

// zipNames lists an archive's entries, sorted.
func zipNames(t *testing.T, body []byte) []string {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("read zip: %v", err)
	}
	names := make([]string, 0, len(zr.File))
	for _, f := range zr.File {
		names = append(names, f.Name)
	}
	slices.Sort(names)
	return names
}

// assertNoTempFiles fails on any half-written file the vfs left under dir.
func assertNoTempFiles(t *testing.T, dir string) {
	t.Helper()
	_ = filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
		if err == nil && strings.HasPrefix(d.Name(), storageutil.WriteTempPrefix) {
			t.Errorf("temp file left behind: %s", p)
		}
		return nil
	})
}

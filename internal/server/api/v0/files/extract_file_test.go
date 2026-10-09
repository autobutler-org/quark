package v0_files_test

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// An archive on a device extracts on that device, through its namespace, and
// the new folder is announced with the device's serial (#2644).
func TestExtract_ExtractsOnTheNamedDevice(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeArchive(t, h.usbDir, "in/bundle.tar.gz", tarGzWith(t, map[string]string{
		"docs/a.txt": "a",
		"top.txt":    "top",
	}))

	w := doRequest(h.engine, http.MethodPost, "/api/v0/files/extract?filePath=in/bundle.tar.gz&serial="+testUsbSerial, nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("extract on the device = %d %s", w.Code, w.Body.String())
	}
	for rel, want := range map[string]string{"in/bundle/docs/a.txt": "a", "in/bundle/top.txt": "top"} {
		got, err := os.ReadFile(filepath.Join(h.usbDir, filepath.FromSlash(rel)))
		if err != nil || string(got) != want {
			t.Errorf("%s = %q, %v; want %q", rel, got, err, want)
		}
	}
	assertAbsent(t, filepath.Join(h.internalDir, "in", "bundle"))
	assertNoStagingDir(t, filepath.Join(h.usbDir, "in"))
	if e := h.nextEvent(t); e.Kind != eventbus.EventNewFolder || e.Path != "in/bundle" || e.DeviceSerial != testUsbSerial {
		t.Errorf("event = %+v, want a new folder in/bundle on %s", e, testUsbSerial)
	}
}

// A device that is not attached is a 404, never the internal drive, and an
// archive that cannot be read is the caller's 400 — both decided from typed
// errors, not by matching message text.
func TestExtract_StatusCodes(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeArchive(t, h.internalDir, "bundle.zip", []byte("internal"))
	writeArchive(t, h.usbDir, "broken.zip", []byte("not a zip"))
	writeArchive(t, h.usbDir, "notes.txt", []byte("plain"))

	cases := map[string]int{
		"filePath=bundle.zip&serial=NOPE":                     http.StatusNotFound,
		"filePath=missing.zip&serial=" + testUsbSerial:        http.StatusNotFound,
		"filePath=broken.zip&serial=" + testUsbSerial:         http.StatusBadRequest,
		"filePath=notes.txt&serial=" + testUsbSerial:          http.StatusBadRequest,
		"filePath=" + "../escape.zip&serial=" + testUsbSerial: http.StatusNotFound,
	}
	for query, want := range cases {
		if w := doRequest(h.engine, http.MethodPost, "/api/v0/files/extract?"+query, nil, ""); w.Code != want {
			t.Errorf("extract %s = %d %s, want %d", query, w.Code, w.Body.String(), want)
		}
	}
	assertAbsent(t, filepath.Join(h.internalDir, "bundle"))
	assertNoStagingDir(t, h.usbDir)
}

// assertNoStagingDir fails when an extraction left its hidden folder in dir.
func assertNoStagingDir(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), storageutil.WriteTempPrefix) {
			t.Errorf("%s was left in %s", e.Name(), dir)
		}
	}
}

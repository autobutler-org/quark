package v0_files_test

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"testing"
)

// A device's archive is listed from that device, in every format, and an
// unattached drive is a 404 (#2644).
func TestListArchive_ListsTheNamedDevice(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeArchive(t, h.usbDir, "bundle.tar.gz", tarGzWith(t, map[string]string{
		"docs/a.txt": "a",
		"top.txt":    "top",
	}))
	writeArchive(t, h.internalDir, "bundle.tar.gz", tarGzWith(t, map[string]string{"internal.txt": "x"}))

	w := doRequest(h.engine, http.MethodGet, "/api/v0/files/list-archive?filePath=bundle.tar.gz&serial="+testUsbSerial, nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("list-archive on the device = %d %s", w.Code, w.Body.String())
	}
	var listed []struct {
		Name         string `json:"name"`
		DeviceSerial string `json:"deviceSerial"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &listed); err != nil {
		t.Fatalf("decode: %v: %s", err, w.Body.String())
	}
	var names []string
	for _, e := range listed {
		names = append(names, e.Name)
		if e.DeviceSerial != testUsbSerial {
			t.Errorf("%s carries serial %q, want %q", e.Name, e.DeviceSerial, testUsbSerial)
		}
	}
	if !slices.Equal(names, []string{"docs", "top.txt"}) {
		t.Errorf("listed %v, want the device archive's docs and top.txt", names)
	}

	w = doRequest(h.engine, http.MethodGet, "/api/v0/files/list-archive?filePath=bundle.tar.gz&serial=NOPE", nil, "")
	if w.Code != http.StatusNotFound {
		t.Errorf("list-archive on an unattached device = %d, want 404", w.Code)
	}
}

// writeArchive writes archive bytes at rel under filesDir.
func writeArchive(t *testing.T, filesDir, rel string, data []byte) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

// tarGzWith builds a tar.gz of entries, in name order.
func tarGzWith(t *testing.T, entries map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gw := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gw)
	names := make([]string, 0, len(entries))
	for name := range entries {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		if err := tw.WriteHeader(&tar.Header{Name: name, Typeflag: tar.TypeReg, Size: int64(len(entries[name])), Mode: 0o644}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(entries[name])); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

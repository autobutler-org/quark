package v0_files_test

import (
	"archive/zip"
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/image/bmp"
)

// writeZipWithBMP writes photos.zip into dir holding one small BMP entry and
// returns the BMP's bytes.
func writeZipWithBMP(t *testing.T, dir string) []byte {
	t.Helper()

	img := image.NewRGBA(image.Rect(0, 0, 4, 4))
	img.Set(1, 1, color.RGBA{R: 255, A: 255})
	var bmpBytes bytes.Buffer
	if err := bmp.Encode(&bmpBytes, img); err != nil {
		t.Fatalf("bmp.Encode: %v", err)
	}

	var archive bytes.Buffer
	zw := zip.NewWriter(&archive)
	w, err := zw.Create("pics/red.bmp")
	if err != nil {
		t.Fatalf("zip Create: %v", err)
	}
	if _, err := w.Write(bmpBytes.Bytes()); err != nil {
		t.Fatalf("zip Write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip Close: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "photos.zip"), archive.Bytes(), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	return bmpBytes.Bytes()
}

// TestDownloadArchiveFile_FormatJPEG covers #1851: a BMP inside a zip comes
// back as a JPEG when the client asks for one, and as its original bytes when
// it does not, on the internal drive and on a device alike (#2644).
func TestDownloadArchiveFile_FormatJPEG(t *testing.T) {
	for _, target := range uploadTargets {
		t.Run(target.name, func(t *testing.T) {
			engine, dir := target.engine(t)
			original := writeZipWithBMP(t, dir)
			base := target.on("/api/v0/files/download-archive-file?filePath=photos.zip&entryPath=pics/red.bmp")

			w := doRequest(engine, http.MethodGet, base+"&format=jpeg", nil, "")
			if w.Code != http.StatusOK {
				t.Fatalf("format=jpeg: got %d: %s", w.Code, w.Body.String())
			}
			if ct := w.Header().Get("Content-Type"); ct != "image/jpeg" {
				t.Errorf("format=jpeg Content-Type: got %q, want image/jpeg", ct)
			}
			if _, err := jpeg.Decode(w.Body); err != nil {
				t.Errorf("format=jpeg body is not a JPEG: %v", err)
			}

			w = doRequest(engine, http.MethodGet, base, nil, "")
			if w.Code != http.StatusOK {
				t.Fatalf("no format: got %d: %s", w.Code, w.Body.String())
			}
			if ct := w.Header().Get("Content-Type"); ct != "application/octet-stream" {
				t.Errorf("no format Content-Type: got %q, want application/octet-stream", ct)
			}
			if !bytes.Equal(w.Body.Bytes(), original) {
				t.Error("no format: body differs from the archived BMP")
			}
		})
	}
}

// An entry inside an archive on a device is read from that device: the
// internal drive's archive of the same name is not consulted, and a drive that
// is not attached is a 404 rather than the internal drive (#2644).
func TestDownloadArchiveFile_ReadsTheNamedDevice(t *testing.T) {
	h := newDeviceUploadHarness(t)
	writeArchive(t, h.usbDir, "bundle.tar.gz", tarGzWith(t, map[string]string{"docs/a.txt": "on the device"}))
	writeArchive(t, h.internalDir, "bundle.tar.gz", tarGzWith(t, map[string]string{"docs/a.txt": "internal"}))

	const url = "/api/v0/files/download-archive-file?filePath=bundle.tar.gz&entryPath=docs/a.txt"
	w := doRequest(h.engine, http.MethodGet, url+"&serial="+testUsbSerial, nil, "")
	if w.Code != http.StatusOK || w.Body.String() != "on the device" {
		t.Errorf("device entry = %d %q, want 200 %q", w.Code, w.Body.String(), "on the device")
	}
	for _, missing := range []string{
		url + "&serial=NOPE",
		"/api/v0/files/download-archive-file?filePath=bundle.tar.gz&entryPath=docs/nope.txt&serial=" + testUsbSerial,
	} {
		if w := doRequest(h.engine, http.MethodGet, missing, nil, ""); w.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404", missing, w.Code)
		}
	}
}

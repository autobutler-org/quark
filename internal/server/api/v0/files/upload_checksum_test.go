package v0_files_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// A resumable upload may carry the SHA-256 its client computed. The Quark
// checks the staged bytes against it before the file lands, so phone backup
// can call a photo safe only when the Quark holds an identical copy (#4160).

const checksumMismatchMessage = "The uploaded file did not match its checksum."

type checksumResponse struct {
	Complete bool   `json:"complete"`
	Path     string `json:"path"`
	SHA256   string `json:"sha256"`
	Error    string `json:"error"`
}

func decodeChecksum(t *testing.T, w *httptest.ResponseRecorder) checksumResponse {
	t.Helper()
	var decoded checksumResponse
	if err := json.Unmarshal(w.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("decode response: %v\nbody: %s", err, w.Body.String())
	}
	return decoded
}

func TestUploadWithAMatchingChecksumCompletesAndReturnsIt(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, 3*uploadChunkSize+17)
	want := sha256Hex(content)

	opened := openSession(t, engine, map[string]any{
		"rootDir": "photos", "fileName": "IMG_0001.jpg", "totalSize": len(content), "sha256": want,
	})
	if opened.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", opened.Code, opened.Body.String())
	}
	sessionID := decodeSession(t, opened).SessionID

	final := decodeChecksum(t, uploadInChunks(t, engine, sessionID, content, uploadChunkSize))
	if !final.Complete {
		t.Fatalf("the last chunk did not complete the upload: %+v", final)
	}
	if final.SHA256 != want {
		t.Errorf("completed upload reports sha256 %q, want %q", final.SHA256, want)
	}
	uploaded := filepath.Join(filesDir, "photos", "IMG_0001.jpg")
	if got := sha256File(t, uploaded); got != want {
		t.Errorf("uploaded file hashes to %s, want %s", got, want)
	}
}

func TestUploadWithAMismatchedChecksumIsRefusedAndLeavesNoFile(t *testing.T) {
	t.Parallel()

	engine, filesDir, store := newUploadSessionEngine(t)
	content := randomContent(t, 2*uploadChunkSize+5)
	wrong := sha256Hex([]byte("some other photo"))

	opened := openSession(t, engine, map[string]any{
		"rootDir": "photos", "fileName": "IMG_0002.jpg", "totalSize": len(content), "sha256": wrong,
	})
	if opened.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", opened.Code, opened.Body.String())
	}
	sessionID := decodeSession(t, opened).SessionID

	var last *httptest.ResponseRecorder
	for start := 0; start < len(content); start += uploadChunkSize {
		end := min(start+uploadChunkSize, len(content))
		last = putSlice(t, engine, sessionID, content, start, end)
	}
	if last.Code != http.StatusUnprocessableEntity {
		t.Fatalf("mismatched upload returned %d, want %d: %s",
			last.Code, http.StatusUnprocessableEntity, last.Body.String())
	}
	if got := decodeChecksum(t, last).Error; got != checksumMismatchMessage {
		t.Errorf("mismatch error is %q, want %q", got, checksumMismatchMessage)
	}

	if _, err := os.Stat(filepath.Join(filesDir, "photos", "IMG_0002.jpg")); !os.IsNotExist(err) {
		t.Errorf("a mismatched upload left a file behind (stat error: %v)", err)
	}
	if w := getSession(t, engine, sessionID); w.Code != http.StatusNotFound {
		t.Errorf("mismatched session returned %d, want %d", w.Code, http.StatusNotFound)
	}
	if staged := stagedFileCount(t, store.StagingDir()); staged != 0 {
		t.Errorf("a mismatched upload left %d staged file(s)", staged)
	}
}

func TestMismatchedOverwriteKeepsTheFileItWouldHaveReplaced(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	original := randomContent(t, uploadChunkSize)
	firstID := openSessionOK(t, engine, "photos", "IMG_0003.jpg", len(original))
	uploadInChunks(t, engine, firstID, original, uploadChunkSize)

	replacement := []byte(strings.Repeat("replacement", 100))
	opened := openSession(t, engine, map[string]any{
		"rootDir": "photos", "fileName": "IMG_0003.jpg", "totalSize": len(replacement),
		"overwrite": true, "sha256": sha256Hex([]byte("not the replacement")),
	})
	if opened.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", opened.Code, opened.Body.String())
	}
	sessionID := decodeSession(t, opened).SessionID
	if w := putSlice(t, engine, sessionID, replacement, 0, len(replacement)); w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("mismatched overwrite returned %d, want %d: %s",
			w.Code, http.StatusUnprocessableEntity, w.Body.String())
	}

	kept := filepath.Join(filesDir, "photos", "IMG_0003.jpg")
	if got, want := sha256File(t, kept), sha256Hex(original); got != want {
		t.Errorf("the file a mismatched overwrite targeted hashes to %s, want the original %s", got, want)
	}
}

func TestOpenUploadSessionRejectsAMalformedChecksum(t *testing.T) {
	t.Parallel()

	engine, _, _ := newUploadSessionEngine(t)
	valid := sha256Hex([]byte("photo"))

	cases := map[string]string{
		"uppercase hex": strings.ToUpper(valid),
		"too short":     valid[:63],
		"too long":      valid + "0",
		"not hex":       strings.Repeat("z", 64),
		"prefixed":      "sha256:" + valid[:57],
	}
	for name, checksum := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			w := openSession(t, engine, map[string]any{
				"rootDir": "photos", "fileName": "IMG_0004.jpg", "totalSize": 10, "sha256": checksum,
			})
			if w.Code != http.StatusBadRequest {
				t.Errorf("checksum %q returned %d, want %d: %s", checksum, w.Code, http.StatusBadRequest, w.Body.String())
			}
		})
	}
}

func TestUploadWithoutAChecksumReportsNone(t *testing.T) {
	t.Parallel()

	engine, _, _ := newUploadSessionEngine(t)
	content := randomContent(t, uploadChunkSize+1)
	sessionID := openSessionOK(t, engine, "photos", "IMG_0005.jpg", len(content))
	last := uploadInChunks(t, engine, sessionID, content, uploadChunkSize)

	var raw map[string]any
	if err := json.Unmarshal(last.Body.Bytes(), &raw); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if _, present := raw["sha256"]; present {
		t.Errorf("an upload opened without a checksum reports one: %s", last.Body.String())
	}
}

func TestAResumedUploadStillVerifiesItsChecksum(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, 4*uploadChunkSize)
	want := sha256Hex(content)

	opened := openSession(t, engine, map[string]any{
		"rootDir": "photos", "fileName": "IMG_0006.jpg", "totalSize": len(content), "sha256": want,
	})
	if opened.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", opened.Code, opened.Body.String())
	}
	sessionID := decodeSession(t, opened).SessionID

	if w := putSlice(t, engine, sessionID, content, 0, uploadChunkSize); w.Code != http.StatusOK {
		t.Fatalf("first chunk returned %d: %s", w.Code, w.Body.String())
	}
	resumeAt := int(decodeSession(t, getSession(t, engine, sessionID)).Offset)
	if resumeAt != uploadChunkSize {
		t.Fatalf("session reports offset %d, want %d", resumeAt, uploadChunkSize)
	}

	tampered := append([]byte(nil), content...)
	tampered[len(tampered)-1] ^= 0xff
	var last *httptest.ResponseRecorder
	for start := resumeAt; start < len(tampered); start += uploadChunkSize {
		last = putSlice(t, engine, sessionID, tampered, start, min(start+uploadChunkSize, len(tampered)))
	}
	if last.Code != http.StatusUnprocessableEntity {
		t.Fatalf("a resumed upload with a changed byte returned %d, want %d: %s",
			last.Code, http.StatusUnprocessableEntity, last.Body.String())
	}
	if _, err := os.Stat(filepath.Join(filesDir, "photos", "IMG_0006.jpg")); !os.IsNotExist(err) {
		t.Errorf("a resumed upload that failed its checksum left a file behind (stat error: %v)", err)
	}
}

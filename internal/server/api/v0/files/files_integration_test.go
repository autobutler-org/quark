package v0_files_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// fakeDetector implements storageutil.Detector and returns a single internal
// device pointing at the provided temp directory. Used to inject a controlled
// device into the StorageService without touching the real filesystem.
type fakeDetector struct {
	mountPoint string
	// extra devices are reported after the internal one.
	extra []storageutil.Device
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return append([]storageutil.Device{
		{
			Name:       "Test Device",
			MountPoint: f.mountPoint,
			IsInternal: true,
		},
	}, f.extra...), nil
}

// newTestEngine creates a gin engine with the files routes registered and
// a fake StorageService pointing at a temp directory injected via deps.
// This avoids relying on HOME env var tricks and works across all platforms.
func newTestEngine(t *testing.T) (*gin.Engine, string) {
	t.Helper()

	// Create a temp dir to act as the device mount point.
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}

	// Build a deps with a fake StorageService so handlers get a real-looking
	// device list pointing at our temp dir — no real device detection happens.
	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithEventBus(eventbus.New()).
		WithUploadSessions(newTestSessionStore(mountPoint))

	// Inject deps so handlers can call deps.StorageService().GetManagedDevices().
	return newEngineForDeps(deps), filesDir
}

// doRequest fires an HTTP request against the test engine.
func doRequest(engine *gin.Engine, method, path string, body io.Reader, contentType string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, body)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// uploadFile uploads a file via multipart/form-data using the "files" field name
// (matching the storageutil.UploadFilesStreamedImpl expectation).
func uploadFile(t *testing.T, engine *gin.Engine, uploadPath, filename, content string) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, err := mw.CreateFormFile("files", filename)
	if err != nil {
		t.Fatalf("failed to create form file: %v", err)
	}
	if _, err := io.WriteString(fw, content); err != nil {
		t.Fatalf("failed to write file content: %v", err)
	}
	mw.Close()
	return doRequest(engine, http.MethodPost, uploadPath, &buf, mw.FormDataContentType())
}

// listFiles returns parsed file nodes from GET /api/v0/files.
func listFiles(t *testing.T, engine *gin.Engine, rootDir string) []map[string]any {
	t.Helper()
	path := "/api/v0/files"
	if rootDir != "" {
		path += "?rootDir=" + rootDir
	}
	w := doRequest(engine, http.MethodGet, path, nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("list files returned %d: %s", w.Code, w.Body.String())
	}
	var result []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to unmarshal list response: %v", err)
	}
	return result
}

// fileNames extracts the "name" field from a list of file nodes, stripping
// any trailing slash (directories may have trailing slashes from os.DirEntry).
func fileNames(files []map[string]any) []string {
	names := make([]string, 0, len(files))
	for _, f := range files {
		if n, ok := f["name"].(string); ok {
			names = append(names, strings.TrimRight(n, "/"))
		}
	}
	return names
}

func contains(names []string, target string) bool {
	return slices.Contains(names, target)
}

// --- Tests ---

func TestListFiles_EmptyDir(t *testing.T) {
	engine, _ := newTestEngine(t)

	files := listFiles(t, engine, "")
	if len(files) != 0 {
		t.Errorf("expected empty list, got %d items", len(files))
	}
}

func TestUploadAndList(t *testing.T) {
	engine, _ := newTestEngine(t)

	w := uploadFile(t, engine, "/api/v0/files/upload", "hello.txt", "hello world")
	if w.Code != http.StatusOK {
		t.Fatalf("upload returned %d: %s", w.Code, w.Body.String())
	}

	files := listFiles(t, engine, "")
	if len(files) != 1 {
		t.Fatalf("expected 1 file, got %d: %v", len(files), fileNames(files))
	}
	name := strings.TrimRight(fmt.Sprintf("%v", files[0]["name"]), "/")
	if name != "hello.txt" {
		t.Errorf("expected name 'hello.txt', got %q", name)
	}
	if files[0]["isDir"] != false {
		t.Errorf("expected isDir=false, got %v", files[0]["isDir"])
	}
}

func TestUploadMultipleFiles(t *testing.T) {
	engine, _ := newTestEngine(t)

	for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
		w := uploadFile(t, engine, "/api/v0/files/upload", name, "content of "+name)
		if w.Code != http.StatusOK {
			t.Fatalf("upload %s returned %d: %s", name, w.Code, w.Body.String())
		}
	}

	files := listFiles(t, engine, "")
	if len(files) != 3 {
		t.Errorf("expected 3 files, got %d: %v", len(files), fileNames(files))
	}
}

func TestUploadToSubdirectory(t *testing.T) {
	engine, _ := newTestEngine(t)

	// The route is registered as /files//upload/*rootDir (double slash avoids gin conflict
	// with the top-level /files/upload route), but gin normalizes request URLs so the
	// actual path to call is /files/upload/{subdir}.
	w := uploadFile(t, engine, "/api/v0/files/upload/docs", "readme.txt", "docs content")
	if w.Code != http.StatusOK {
		t.Fatalf("upload to subdir returned %d: %s", w.Code, w.Body.String())
	}

	// Root listing should show the docs folder
	files := listFiles(t, engine, "")
	if !contains(fileNames(files), "docs") {
		t.Errorf("expected 'docs' folder in root listing, got: %v", fileNames(files))
	}

	// Subdirectory listing should show readme.txt
	subFiles := listFiles(t, engine, "docs")
	if !contains(fileNames(subFiles), "readme.txt") {
		t.Errorf("expected 'readme.txt' in docs/, got: %v", fileNames(subFiles))
	}
}

func TestListFiles_NonExistentSubdirectoryReturnsNotFound(t *testing.T) {
	engine, _ := newTestEngine(t)

	w := doRequest(engine, http.MethodGet, "/api/v0/files?rootDir=ghosts", nil, "")
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestDownloadFile(t *testing.T) {
	engine, filesDir := newTestEngine(t)

	// Write file directly to disk (bypasses upload multipart parsing in test env)
	content := "download me"
	if err := os.WriteFile(filepath.Join(filesDir, "download.txt"), []byte(content), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	w := doRequest(engine, http.MethodGet, "/api/v0/files/download?filePath=download.txt", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("download returned %d: %s", w.Code, w.Body.String())
	}
	if w.Body.String() != content {
		t.Errorf("expected body %q, got %q", content, w.Body.String())
	}
}

func TestDownloadNonExistentFile(t *testing.T) {
	engine, _ := newTestEngine(t)

	w := doRequest(engine, http.MethodGet, "/api/v0/files/download?filePath=ghost.txt", nil, "")
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestDeleteFile(t *testing.T) {
	engine, filesDir := newTestEngine(t)

	if err := os.WriteFile(filepath.Join(filesDir, "todelete.txt"), []byte("bye"), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	w := doRequest(engine, http.MethodDelete, "/api/v0/files?filePaths=todelete.txt", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}

	files := listFiles(t, engine, "")
	if contains(fileNames(files), "todelete.txt") {
		t.Error("file still present after deletion")
	}
}

func TestDeleteFile_BatchMovedToTrash(t *testing.T) {
	engine, filesDir := newTestEngine(t)

	// Write three files that will be batch-deleted.
	for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
		if err := os.WriteFile(filepath.Join(filesDir, name), []byte(name), 0644); err != nil {
			t.Fatalf("failed to write %s: %v", name, err)
		}
	}

	// Delete all three in one request (no serial → falls back to DeleteFiles sync path).
	w := doRequest(engine, http.MethodDelete,
		"/api/v0/files?filePaths=a.txt&filePaths=b.txt&filePaths=c.txt", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}

	files := listFiles(t, engine, "")
	names := fileNames(files)
	for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
		if contains(names, name) {
			t.Errorf("file %s still visible after batch delete", name)
		}
	}
}

func TestDeleteWithoutFilePaths(t *testing.T) {
	engine, _ := newTestEngine(t)

	w := doRequest(engine, http.MethodDelete, "/api/v0/files", nil, "")
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestMoveFile(t *testing.T) {
	engine, filesDir := newTestEngine(t)

	if err := os.WriteFile(filepath.Join(filesDir, "original.txt"), []byte("move me"), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	body, _ := json.Marshal(map[string]string{
		"oldFilePath": "original.txt",
		"newFilePath": "renamed.txt",
	})
	w := doRequest(engine, http.MethodPut, "/api/v0/files", bytes.NewReader(body), "application/json")
	if w.Code != http.StatusOK {
		t.Fatalf("move returned %d: %s", w.Code, w.Body.String())
	}

	files := listFiles(t, engine, "")
	names := fileNames(files)
	if !contains(names, "renamed.txt") {
		t.Errorf("renamed.txt not found after move, got: %v", names)
	}
	if contains(names, "original.txt") {
		t.Errorf("original.txt still present after move")
	}
}

func TestCreateFolder(t *testing.T) {
	engine, _ := newTestEngine(t)

	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	mw.WriteField("folderName", "myfolder")
	mw.Close()

	w := doRequest(engine, http.MethodPost, "/api/v0/files/folder//", &buf, mw.FormDataContentType())
	if w.Code != http.StatusOK {
		t.Fatalf("create folder returned %d: %s", w.Code, w.Body.String())
	}

	files := listFiles(t, engine, "")
	if !contains(fileNames(files), "myfolder") {
		t.Errorf("folder 'myfolder' not found after creation, got: %v", fileNames(files))
	}

	// Verify it is marked as a directory
	for _, f := range files {
		name := strings.TrimRight(fmt.Sprintf("%v", f["name"]), "/")
		if name == "myfolder" && f["isDir"] != true {
			t.Errorf("expected isDir=true for myfolder, got %v", f["isDir"])
		}
	}
}

func TestSearchFiles(t *testing.T) {
	engine, filesDir := newTestEngine(t)

	for _, name := range []string{"apple.txt", "apricot.txt", "banana.txt"} {
		if err := os.WriteFile(filepath.Join(filesDir, name), []byte("content"), 0644); err != nil {
			t.Fatalf("failed to write %s: %v", name, err)
		}
	}

	w := doRequest(engine, http.MethodGet, "/api/v0/files/search?query=ap", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("search returned %d: %s", w.Code, w.Body.String())
	}

	var results []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &results); err != nil {
		t.Fatalf("failed to unmarshal search response: %v", err)
	}

	if len(results) != 2 {
		t.Errorf("expected 2 results for 'ap', got %d: %v", len(results), fileNames(results))
	}
	for _, r := range results {
		name := strings.TrimRight(fmt.Sprintf("%v", r["name"]), "/")
		if !strings.HasPrefix(strings.ToLower(name), "ap") {
			t.Errorf("unexpected result %q in search for 'ap'", name)
		}
	}
}

func TestFileSize(t *testing.T) {
	engine, filesDir := newTestEngine(t)

	content := "exact content"
	if err := os.WriteFile(filepath.Join(filesDir, "sized.txt"), []byte(content), 0644); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	files := listFiles(t, engine, "")
	if len(files) != 1 {
		t.Fatalf("expected 1 file, got %d: %v", len(files), fileNames(files))
	}

	size, ok := files[0]["size"].(float64)
	if !ok {
		t.Fatalf("size field missing or wrong type: %v", files[0]["size"])
	}
	if int(size) != len(content) {
		t.Errorf("expected size %d, got %d", len(content), int(size))
	}
}

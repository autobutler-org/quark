package v0_trash_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	v0_trash "github.com/autobutler-org/quark/internal/server/api/v0/trash"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// fakeDetector reports one internal device mounted at a temp directory.
type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

type trashItem struct {
	TrashName    string    `json:"trashName"`
	Name         string    `json:"name"`
	OriginalPath string    `json:"originalPath"`
	IsDir        bool      `json:"isDir"`
	Size         int64     `json:"size"`
	TrashedAt    time.Time `json:"trashedAt"`
	ExpiresAt    time.Time `json:"expiresAt"`
}

type listResponse struct {
	RetentionDays int         `json:"retentionDays"`
	Items         []trashItem `json:"items"`
}

type harness struct {
	engine   *gin.Engine
	filesDir string
	events   <-chan eventbus.Event
}

// newHarness mounts the trash and files routers over an internal device in a
// temp directory, and subscribes to the event bus they publish on.
func newHarness(t *testing.T) harness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	bus := eventbus.New()
	events, unsub := bus.Subscribe("trash-test")
	t.Cleanup(unsub)
	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})).
		WithEventBus(bus)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_trash.NewRouter())
	serverutil.RegisterRouterWithGroup(group, v0_files.NewRouter())
	return harness{engine: engine, filesDir: filesDir, events: events}
}

func (h harness) do(method, path string, body any) *httptest.ResponseRecorder {
	var reader *bytes.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		reader = bytes.NewReader(b)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func (h harness) write(t *testing.T, rel, content string) {
	t.Helper()
	full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// deleteFile deletes through DELETE /files the way the file browser does:
// the parent folder as rootDir, the base name as the path. It waits for the
// events the delete publishes in the background — trash_changed, then delete
// with the path relative to the files directory — so a later waitFor cannot be
// satisfied by one of them.
func (h harness) deleteFile(t *testing.T, rootDir, name string) {
	t.Helper()
	w := h.do(http.MethodDelete, "/api/v0/files?rootDir="+rootDir+"&filePaths="+name, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}
	h.waitFor(t, event(eventbus.EventTrashChanged, ""), event(eventbus.EventDelete, filepath.ToSlash(filepath.Join(rootDir, name))))
}

func (h harness) list(t *testing.T) listResponse {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/trash", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list trash returned %d: %s", w.Code, w.Body.String())
	}
	var resp listResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	return resp
}

// waitFor drains events until every wanted kind/path pair has arrived, in any
// order.
func (h harness) waitFor(t *testing.T, want ...eventbus.Event) {
	t.Helper()
	pending := map[eventbus.Event]bool{}
	for _, w := range want {
		pending[w] = true
	}
	timeout := time.After(2 * time.Second)
	for len(pending) > 0 {
		select {
		case evt := <-h.events:
			delete(pending, eventbus.Event{Kind: evt.Kind, Path: evt.Path})
		case <-timeout:
			t.Fatalf("missing events: %v", pending)
		}
	}
}

// refs addresses whole trashed items by name, as restore and delete take them.
func refs(names ...string) []map[string]string {
	out := make([]map[string]string, len(names))
	for i, name := range names {
		out[i] = map[string]string{"trashName": name}
	}
	return out
}

func event(kind eventbus.EventKind, path string) eventbus.Event {
	return eventbus.Event{Kind: kind, Path: path}
}

func TestDeleteOnInternalStorageGoesToTrash(t *testing.T) {
	h := newHarness(t)
	h.write(t, "docs/notes.txt", "hello")

	h.deleteFile(t, "docs", "notes.txt")

	resp := h.list(t)
	if resp.RetentionDays != storageutil.TrashRetentionDays {
		t.Errorf("retentionDays = %d, want %d", resp.RetentionDays, storageutil.TrashRetentionDays)
	}
	if len(resp.Items) != 1 {
		t.Fatalf("expected 1 trash item, got %+v", resp.Items)
	}
	item := resp.Items[0]
	if item.Name != "notes.txt" || item.OriginalPath != "docs/notes.txt" || item.Size != 5 || item.IsDir {
		t.Errorf("unexpected item %+v", item)
	}
	if !item.ExpiresAt.Equal(item.TrashedAt.AddDate(0, 0, storageutil.TrashRetentionDays)) {
		t.Errorf("expiresAt %v is not trashedAt %v + retention", item.ExpiresAt, item.TrashedAt)
	}

	// The trash never shows up in a listing, even of the root.
	w := h.do(http.MethodGet, "/api/v0/files", nil)
	if bytes.Contains(w.Body.Bytes(), []byte(storageutil.TrashDir)) {
		t.Errorf("file listing exposes the trash: %s", w.Body.String())
	}
}

func TestListTrash_EmptyIsAnArray(t *testing.T) {
	h := newHarness(t)
	w := h.do(http.MethodGet, "/api/v0/trash", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	if !bytes.Contains(w.Body.Bytes(), []byte(`"items":[]`)) {
		t.Errorf("empty trash should list items as []: %s", w.Body.String())
	}
}

func TestListTrash_UnknownSerialIs404(t *testing.T) {
	h := newHarness(t)
	w := h.do(http.MethodGet, "/api/v0/trash?serial=NOPE", nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestRestore(t *testing.T) {
	h := newHarness(t)
	h.write(t, "docs/notes.txt", "hello")
	h.write(t, "album/one.jpg", "1")
	h.deleteFile(t, "docs", "notes.txt")
	h.deleteFile(t, "", "album")

	names := []string{}
	for _, item := range h.list(t).Items {
		names = append(names, item.TrashName)
	}
	w := h.do(http.MethodPost, "/api/v0/trash/restore", map[string]any{"serial": "", "items": refs(names...)})
	if w.Code != http.StatusOK {
		t.Fatalf("restore returned %d: %s", w.Code, w.Body.String())
	}
	var resp struct {
		RestoredPaths []string `json:"restoredPaths"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	if len(resp.RestoredPaths) != 2 {
		t.Errorf("expected 2 restored paths, got %v", resp.RestoredPaths)
	}
	h.waitFor(t,
		event(eventbus.EventUpload, "docs/notes.txt"),
		event(eventbus.EventNewFolder, "album"),
		event(eventbus.EventTrashChanged, ""),
	)

	if got, err := os.ReadFile(filepath.Join(h.filesDir, "docs", "notes.txt")); err != nil || string(got) != "hello" {
		t.Errorf("notes.txt not restored: %q %v", got, err)
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "album", "one.jpg")); err != nil {
		t.Errorf("album not restored: %v", err)
	}
	if items := h.list(t).Items; len(items) != 0 {
		t.Errorf("trash should be empty after restore, got %+v", items)
	}
}

func TestRestore_OccupiedPathIs409(t *testing.T) {
	h := newHarness(t)
	h.write(t, "a.txt", "old")
	h.deleteFile(t, "", "a.txt")
	h.write(t, "a.txt", "new")
	name := h.list(t).Items[0].TrashName

	w := h.do(http.MethodPost, "/api/v0/trash/restore", map[string]any{"items": refs(name)})
	if w.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", w.Code, w.Body.String())
	}
	if got, _ := os.ReadFile(filepath.Join(h.filesDir, "a.txt")); string(got) != "new" {
		t.Errorf("restore overwrote the file now at a.txt: %q", got)
	}
}

func TestRestoreAndDelete_BadNames(t *testing.T) {
	h := newHarness(t)
	h.write(t, "keep.txt", "keep")

	cases := []struct {
		names []string
		want  int
	}{
		{nil, http.StatusBadRequest},
		{[]string{"../keep.txt"}, http.StatusBadRequest},
		{[]string{".."}, http.StatusBadRequest},
		{[]string{"unknown"}, http.StatusNotFound},
	}
	for _, route := range []string{"/api/v0/trash/restore", "/api/v0/trash/delete"} {
		for _, tc := range cases {
			w := h.do(http.MethodPost, route, map[string]any{"items": refs(tc.names...)})
			if w.Code != tc.want {
				t.Errorf("%s %v: expected %d, got %d: %s", route, tc.names, tc.want, w.Code, w.Body.String())
			}
		}
		w := h.do(http.MethodPost, route, map[string]any{"serial": "NOPE", "items": refs("x")})
		if w.Code != http.StatusNotFound {
			t.Errorf("%s unknown serial: expected 404, got %d", route, w.Code)
		}
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "keep.txt")); err != nil {
		t.Errorf("a traversal name touched a file outside the trash: %v", err)
	}
}

func TestDeletePermanently(t *testing.T) {
	h := newHarness(t)
	h.write(t, "a.txt", "a")
	h.write(t, "b.txt", "b")
	h.deleteFile(t, "", "a.txt")
	h.deleteFile(t, "", "b.txt")

	var target string
	for _, item := range h.list(t).Items {
		if item.Name == "a.txt" {
			target = item.TrashName
		}
	}
	w := h.do(http.MethodPost, "/api/v0/trash/delete", map[string]any{"items": refs(target)})
	if w.Code != http.StatusOK || !bytes.Contains(w.Body.Bytes(), []byte(`"deleted":1`)) {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}
	h.waitFor(t, event(eventbus.EventTrashChanged, ""))

	items := h.list(t).Items
	if len(items) != 1 || items[0].Name != "b.txt" {
		t.Errorf("expected only b.txt left, got %+v", items)
	}
}

func TestEmpty(t *testing.T) {
	h := newHarness(t)
	h.write(t, "a.txt", "a")
	h.write(t, "dir/b.txt", "b")
	h.deleteFile(t, "", "a.txt")
	h.deleteFile(t, "", "dir")

	w := h.do(http.MethodPost, "/api/v0/trash/empty", map[string]any{"serial": ""})
	if w.Code != http.StatusOK || !bytes.Contains(w.Body.Bytes(), []byte(`"deleted":2`)) {
		t.Fatalf("empty returned %d: %s", w.Code, w.Body.String())
	}
	h.waitFor(t, event(eventbus.EventTrashChanged, ""))
	if items := h.list(t).Items; len(items) != 0 {
		t.Errorf("trash not empty: %+v", items)
	}

	if w := h.do(http.MethodPost, "/api/v0/trash/empty", nil); w.Code != http.StatusBadRequest {
		t.Errorf("empty with no body: expected 400, got %d", w.Code)
	}
}

type contentsResponse struct {
	Items []struct {
		Name       string    `json:"name"`
		Path       string    `json:"path"`
		IsDir      bool      `json:"isDir"`
		Size       int64     `json:"size"`
		ModifiedAt time.Time `json:"modifiedAt"`
	} `json:"items"`
	OriginalPath string    `json:"originalPath"`
	ExpiresAt    time.Time `json:"expiresAt"`
}

// trashAlbum deletes a folder holding a file and a subfolder, returning its
// trash name.
func (h harness) trashAlbum(t *testing.T) string {
	t.Helper()
	h.write(t, "pics/album/cover.jpg", "cover")
	h.write(t, "pics/album/2024/one.jpg", "1")
	h.deleteFile(t, "pics", "album")
	return h.list(t).Items[0].TrashName
}

func (h harness) contents(t *testing.T, trashName, path string) contentsResponse {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/trash/contents?trashName="+url.QueryEscape(trashName)+"&path="+url.QueryEscape(path), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("contents returned %d: %s", w.Code, w.Body.String())
	}
	var resp contentsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	return resp
}

func TestListTrashContents(t *testing.T) {
	h := newHarness(t)
	name := h.trashAlbum(t)
	expires := h.list(t).Items[0].ExpiresAt

	root := h.contents(t, name, "")
	if root.OriginalPath != "pics/album" || !root.ExpiresAt.Equal(expires) || len(root.Items) != 2 {
		t.Fatalf("unexpected root listing %+v", root)
	}
	if got := root.Items[0]; got.Name != "2024" || got.Path != "2024" || !got.IsDir || got.Size != 1 {
		t.Errorf("unexpected folder entry %+v", got)
	}

	sub := h.contents(t, name, root.Items[0].Path)
	if sub.OriginalPath != "pics/album/2024" || len(sub.Items) != 1 || sub.Items[0].Path != "2024/one.jpg" {
		t.Errorf("unexpected subfolder listing %+v", sub)
	}
}

func TestListTrashContents_Errors(t *testing.T) {
	h := newHarness(t)
	name := h.trashAlbum(t)
	cases := []struct {
		query string
		want  int
	}{
		{"trashName=" + url.QueryEscape(name) + "&path=..", http.StatusBadRequest},
		{"trashName=" + url.QueryEscape(name) + "&path=" + url.QueryEscape("/etc"), http.StatusBadRequest},
		{"trashName=" + url.QueryEscape(name) + "&path=cover.jpg", http.StatusBadRequest},
		{"trashName=" + url.QueryEscape(name) + "&path=missing", http.StatusNotFound},
		{"trashName=unknown", http.StatusNotFound},
		{"trashName=", http.StatusBadRequest},
		{"serial=NOPE&trashName=" + url.QueryEscape(name), http.StatusNotFound},
	}
	for _, tc := range cases {
		w := h.do(http.MethodGet, "/api/v0/trash/contents?"+tc.query, nil)
		if w.Code != tc.want {
			t.Errorf("%s: expected %d, got %d: %s", tc.query, tc.want, w.Code, w.Body.String())
		}
	}
}

func TestRestore_NestedItem(t *testing.T) {
	h := newHarness(t)
	name := h.trashAlbum(t)

	w := h.do(http.MethodPost, "/api/v0/trash/restore", map[string]any{"items": []map[string]string{
		{"trashName": name, "path": "2024"},
		{"trashName": name, "path": "cover.jpg"},
	}})
	if w.Code != http.StatusOK {
		t.Fatalf("restore returned %d: %s", w.Code, w.Body.String())
	}
	h.waitFor(t,
		event(eventbus.EventNewFolder, "pics/album/2024"),
		event(eventbus.EventUpload, "pics/album/cover.jpg"),
		event(eventbus.EventTrashChanged, ""),
	)
	if _, err := os.Stat(filepath.Join(h.filesDir, "pics", "album", "2024", "one.jpg")); err != nil {
		t.Errorf("nested folder not restored: %v", err)
	}
	if items := h.list(t).Items; len(items) != 1 || items[0].TrashName != name {
		t.Errorf("the trashed folder should stay in the trash, got %+v", items)
	}

	// The child left the trash with the restore.
	w = h.do(http.MethodPost, "/api/v0/trash/restore", map[string]any{"items": []map[string]string{{"trashName": name, "path": "2024"}}})
	if w.Code != http.StatusNotFound {
		t.Errorf("restoring a child already restored: expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestRestore_NestedConflictsAre409(t *testing.T) {
	h := newHarness(t)
	name := h.trashAlbum(t)
	h.write(t, "pics/album/cover.jpg", "new")

	batches := [][]map[string]string{
		{{"trashName": name, "path": "cover.jpg"}},
		{{"trashName": name, "path": "2024"}, {"trashName": name, "path": "2024/one.jpg"}},
		{{"trashName": name}, {"trashName": name, "path": "2024"}},
	}
	for _, batch := range batches {
		w := h.do(http.MethodPost, "/api/v0/trash/restore", map[string]any{"items": batch})
		if w.Code != http.StatusConflict {
			t.Errorf("%v: expected 409, got %d: %s", batch, w.Code, w.Body.String())
		}
	}
	if got, _ := os.ReadFile(filepath.Join(h.filesDir, "pics", "album", "cover.jpg")); string(got) != "new" {
		t.Errorf("restore overwrote cover.jpg: %q", got)
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "pics", "album", "2024")); !os.IsNotExist(err) {
		t.Errorf("a conflicting batch restored something: %v", err)
	}
}

func TestDeletePermanently_NestedItem(t *testing.T) {
	h := newHarness(t)
	name := h.trashAlbum(t)

	w := h.do(http.MethodPost, "/api/v0/trash/delete", map[string]any{"items": []map[string]string{{"trashName": name, "path": "2024/one.jpg"}}})
	if w.Code != http.StatusOK || !bytes.Contains(w.Body.Bytes(), []byte(`"deleted":1`)) {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}
	h.waitFor(t, event(eventbus.EventTrashChanged, ""))
	if sub := h.contents(t, name, "2024"); len(sub.Items) != 0 {
		t.Errorf("nested file not deleted: %+v", sub.Items)
	}
	if root := h.contents(t, name, ""); len(root.Items) != 2 {
		t.Errorf("the rest of the folder should stay: %+v", root.Items)
	}
}

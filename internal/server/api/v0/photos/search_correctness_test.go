package v0_photos_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/indexutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// The Photos search box asks GET /files/search for the library's matches and
// keeps the images; the grid itself pages through GET /photos (#3489). This
// is the reduced 1k library the PR leg runs: deterministic names and dates,
// one photo in four named beach_*, half the library shared with the user and
// half private.
const (
	searchLibrarySize = 1000
	searchQuery       = "beach"
)

// searchLibraryPath is photo i of the library: the first half under shared/,
// the rest under private/, every fourth one a beach match.
func searchLibraryPath(i int) string {
	dir := "shared"
	if i >= searchLibrarySize/2 {
		dir = "private"
	}
	name := "IMG"
	if i%4 == 0 {
		name = searchQuery
	}
	return fmt.Sprintf("%s/%s_%04d.jpg", dir, name, i)
}

// searchHarness serves the photos and files routes over one real files
// directory, the production file index kept current by the event bus, and a
// migrated database, acting as whoever principal names.
type searchHarness struct {
	engine    *gin.Engine
	filesDir  string
	database  *db.DatabaseSqlc
	userID    int64
	principal *accessutil.Principal
	jpeg      []byte
	// index learns of a file written once it is built, as an upload's event
	// would tell it.
	index *indexutil.FileIndex
}

func newSearchHarness(t *testing.T) searchHarness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 8, 8)), nil); err != nil {
		t.Fatal(err)
	}
	h := searchHarness{filesDir: filesDir, jpeg: buf.Bytes()}

	// Photo i was added i minutes after the first, so every date sort has one
	// right answer.
	start := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	for i := range searchLibrarySize {
		h.write(t, searchLibraryPath(i), start.Add(time.Duration(i)*time.Minute))
	}

	svc := storageutil.NewStorageService(systemDevice{})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	bus := eventbus.New()
	index := indexutil.NewFileIndex(dbtest.NewDB(t))
	index.BuildAndWatch(indexutil.BuildAndWatchParams{Ctx: ctx, Bus: bus, Registry: registry})
	h.index = index

	h.database = dbtest.NewDB(t)
	user, err := h.database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	h.userID = user.ID
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithDatabase(h.database).
		WithEventBus(bus).
		WithFileIndex(index)
	system := accessutil.System
	h.principal = &system

	gin.SetMode(gin.TestMode)
	h.engine = gin.New()
	h.engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *h.principal)
		c.Next()
	})
	group := h.engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_photos.NewRouter())
	serverutil.RegisterRouterWithGroup(group, v0_files.NewRouter())
	return h
}

func (h searchHarness) write(t *testing.T, rel string, mtime time.Time) {
	t.Helper()
	full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, h.jpeg, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(full, mtime, mtime); err != nil {
		t.Fatal(err)
	}
	if h.index != nil {
		h.index.HandleAdd("", rel, int64(len(h.jpeg)), mtime.UnixNano())
	}
}

func (h searchHarness) do(t *testing.T, method, path, contentType string, body []byte) []byte {
	t.Helper()
	w := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, bytes.NewReader(body))
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	h.engine.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("%s %s = %d: %s", method, path, w.Code, w.Body.String())
	}
	return w.Body.Bytes()
}

// search answers the search box's question for query, the relPath of every
// match in response order.
func (h searchHarness) search(t *testing.T, query string) []string {
	t.Helper()
	body := h.do(t, http.MethodGet, "/api/v0/files/search?query="+query, "", nil)
	var files []struct {
		FullPath string `json:"fullPath"`
	}
	if err := json.Unmarshal(body, &files); err != nil {
		t.Fatalf("decode %s: %v", body, err)
	}
	paths := make([]string, 0, len(files))
	for _, f := range files {
		paths = append(paths, f.FullPath)
	}
	return paths
}

// eventually searches until want holds of the matches, the way a client
// re-queries after the change event its stream delivered; the index applies
// that event on its own goroutine.
func (h searchHarness) eventually(t *testing.T, what string, want func([]string) bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		got := h.search(t, searchQuery)
		if want(got) {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("search never showed %s; last answer had %d matches", what, len(got))
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// listAll pages through GET /photos limit at a time and returns every
// relPath in the order the pages gave them, and the total each page claimed.
func (h searchHarness) listAll(t *testing.T, query string, limit int) ([]string, []int) {
	t.Helper()
	var paths []string
	var totals []int
	for offset := 0; ; offset += limit {
		body := h.do(t, http.MethodGet, fmt.Sprintf("/api/v0/photos?%s&offset=%d&limit=%d", query, offset, limit), "", nil)
		var page v0_photos.PaginatedPhotosResponse
		if err := json.Unmarshal(body, &page); err != nil {
			t.Fatalf("decode %s: %v", body, err)
		}
		totals = append(totals, page.Total)
		for _, p := range page.Photos {
			paths = append(paths, p.RelPath)
		}
		if len(page.Photos) < limit {
			return paths, totals
		}
	}
}

// libraryWhere returns the library's paths that keep accepts, in library
// order.
func libraryWhere(keep func(i int) bool) []string {
	var paths []string
	for i := range searchLibrarySize {
		if keep(i) {
			paths = append(paths, searchLibraryPath(i))
		}
	}
	return paths
}

// sameSet fails unless got holds exactly the paths in want, each once.
func sameSet(t *testing.T, what string, got, want []string) {
	t.Helper()
	seen := make(map[string]bool, len(got))
	for _, p := range got {
		if seen[p] {
			t.Errorf("%s: %s appears twice", what, p)
		}
		seen[p] = true
	}
	expected := make(map[string]bool, len(want))
	for _, p := range want {
		expected[p] = true
		if !seen[p] {
			t.Errorf("%s: missing %s", what, p)
		}
	}
	for p := range seen {
		if !expected[p] {
			t.Errorf("%s: unexpected %s", what, p)
		}
	}
}

func TestPhotoSearch_ReturnsEveryMatchOfALargeLibrary(t *testing.T) {
	h := newSearchHarness(t)
	want := libraryWhere(func(i int) bool { return i%4 == 0 })
	if len(want) != 250 {
		t.Fatalf("fixture has %d matches, want 250", len(want))
	}
	// 250 matches is five of the grid's 50-photo pages, all in one answer.
	got := h.search(t, searchQuery)
	sameSet(t, "search", got, want)
	if again := h.search(t, searchQuery); !slices.Equal(again, got) {
		t.Error("searching twice gave the matches in a different order")
	}
	sameSet(t, "search in another case", h.search(t, "BEACH"), want)
}

func TestPhotoSearch_LibraryPagesCoverEveryPhotoOnceInSortOrder(t *testing.T) {
	h := newSearchHarness(t)
	library := libraryWhere(func(int) bool { return true })

	newestFirst := slices.Clone(library)
	slices.Reverse(newestFirst)
	byName := slices.Clone(library)
	// The name sort ignores case, so beach_* comes before IMG_*.
	slices.SortFunc(byName, func(a, b string) int {
		return strings.Compare(strings.ToLower(filepath.Base(a)), strings.ToLower(filepath.Base(b)))
	})

	for _, tc := range []struct {
		query string
		want  []string
	}{
		{"sort=added&order=desc", newestFirst},
		{"sort=added&order=asc", library},
		{"sort=name&order=asc", byName},
	} {
		got, totals := h.listAll(t, tc.query, 50)
		if !slices.Equal(got, tc.want) {
			sameSet(t, tc.query, got, tc.want)
			t.Errorf("%s: pages are not in sort order", tc.query)
		}
		for _, total := range totals {
			if total != searchLibrarySize {
				t.Errorf("%s: a page claimed a total of %d, want %d", tc.query, total, searchLibrarySize)
			}
		}
	}
}

func TestPhotoSearch_NoMatchIsAnEmptyListNotAnError(t *testing.T) {
	h := newSearchHarness(t)
	for _, query := range []string{"zebra", "", "%20%20"} {
		body := h.do(t, http.MethodGet, "/api/v0/files/search?query="+query, "", nil)
		if got := strings.TrimSpace(string(body)); got != "[]" {
			t.Errorf("search %q = %s, want []", query, got)
		}
	}
}

func TestPhotoSearch_FollowsUploadDeleteAndRename(t *testing.T) {
	h := newSearchHarness(t)

	// Upload a new match into a folder that is already indexed.
	var form bytes.Buffer
	mw := multipart.NewWriter(&form)
	fw, err := mw.CreateFormFile("files", "beach_new.jpg")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write(h.jpeg); err != nil {
		t.Fatal(err)
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	h.do(t, http.MethodPost, "/api/v0/files/upload/shared", mw.FormDataContentType(), form.Bytes())
	h.eventually(t, "the uploaded match", func(got []string) bool {
		return slices.Contains(got, "shared/beach_new.jpg")
	})

	// A deleted match leaves the results, and its metadata, the viewer's
	// first request, is gone with it.
	deleted := searchLibraryPath(0)
	h.do(t, http.MethodDelete, "/api/v0/files?filePaths="+deleted, "", nil)
	h.eventually(t, "the deleted match gone", func(got []string) bool {
		return !slices.Contains(got, deleted)
	})
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/photos/metadata?relPath="+deleted, nil))
	if w.Code != http.StatusNotFound {
		t.Errorf("metadata of the deleted match = %d, want 404: %s", w.Code, w.Body.String())
	}

	// A rename into the query joins the results and one out of it leaves.
	move := func(from, to string) {
		body, err := json.Marshal(map[string]string{"oldFilePath": from, "newFilePath": to})
		if err != nil {
			t.Fatal(err)
		}
		h.do(t, http.MethodPut, "/api/v0/files", "application/json", body)
	}
	move("shared/IMG_0001.jpg", "shared/beach_renamed.jpg")
	move("shared/beach_0004.jpg", "shared/IMG_renamed.jpg")
	h.eventually(t, "both renames", func(got []string) bool {
		return slices.Contains(got, "shared/beach_renamed.jpg") && !slices.Contains(got, "shared/beach_0004.jpg")
	})

	want := libraryWhere(func(i int) bool { return i%4 == 0 && i != 0 && i != 4 })
	want = append(want, "shared/beach_new.jpg", "shared/beach_renamed.jpg")
	sameSet(t, "search after every change", h.search(t, searchQuery), want)
}

func TestPhotoSearch_ShowsOnlyWhatTheCallerCanRead(t *testing.T) {
	h := newSearchHarness(t)
	*h.principal = accessutil.Principal{UserID: h.userID}

	if got := h.search(t, searchQuery); len(got) != 0 {
		t.Errorf("search with no grants = %d matches, want none: %v", len(got), got[:min(len(got), 5)])
	}
	if _, totals := h.listAll(t, "", 200); totals[0] != 0 {
		t.Errorf("library total with no grants = %d, want 0", totals[0])
	}

	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: "shared",
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	shared := func(i int) bool { return i < searchLibrarySize/2 }
	sameSet(t, "search with a read share", h.search(t, searchQuery),
		libraryWhere(func(i int) bool { return shared(i) && i%4 == 0 }))
	got, totals := h.listAll(t, "sort=added&order=asc", 200)
	sameSet(t, "library with a read share", got, libraryWhere(shared))
	for _, total := range totals {
		if total != searchLibrarySize/2 {
			t.Errorf("library total with a read share = %d, want %d", total, searchLibrarySize/2)
		}
	}
}

package v0_files_test

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"maps"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// accessHarness is the files router over a real device directory, the
// production StorageService-backed VFS and a migrated database, acting as one
// signed-in user (#1903).
type accessHarness struct {
	engine   *gin.Engine
	filesDir string
	database *db.DatabaseSqlc
	userID   int64
	// principal is who requests act as; as() switches it.
	principal *accessutil.Principal
}

func newAccessHarness(t *testing.T, admin bool) accessHarness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	principal := &accessutil.Principal{UserID: user.ID, IsAdmin: admin}
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithEventBus(eventbus.New()).
		WithDatabase(database).
		WithUploadSessions(newTestSessionStore(mountPoint))

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_files.NewRouter())
	return accessHarness{engine: engine, filesDir: filesDir, database: database, userID: user.ID, principal: principal}
}

func (h accessHarness) grant(t *testing.T, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: accessutil.Canonical(rel),
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

func (h accessHarness) get(path string) *httptest.ResponseRecorder {
	return doRequest(h.engine, http.MethodGet, path, nil, "")
}

// names lists a folder and returns the entry names, sorted.
func (h accessHarness) names(t *testing.T, rootDir string) []string {
	t.Helper()
	w := h.get("/api/v0/files?rootDir=" + url.QueryEscape(rootDir))
	if w.Code != http.StatusOK {
		t.Fatalf("list %q returned %d: %s", rootDir, w.Code, w.Body.String())
	}
	var entries []fileEntry
	if err := json.Unmarshal(w.Body.Bytes(), &entries); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, strings.TrimRight(e.Name, "/"))
	}
	slices.Sort(names)
	return names
}

func (h accessHarness) rowCount(t *testing.T) int {
	t.Helper()
	var n int
	if err := h.database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func (h accessHarness) expectStatus(t *testing.T, want int, paths ...string) {
	t.Helper()
	for _, p := range paths {
		if w := h.get(p); w.Code != want {
			t.Errorf("GET %s = %d, want %d: %s", p, w.Code, want, w.Body.String())
		}
	}
}

// writeZip writes an archive holding one entry, inside.txt.
func writeZip(t *testing.T, filesDir, rel string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(full)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	zw := zip.NewWriter(f)
	w, err := zw.Create("inside.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("inside")); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestAccess_NoRowsListsAnEmptyRoot(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "a.txt")
	writeFixture(t, h.filesDir, "dir/b.txt")

	if got := h.names(t, ""); len(got) != 0 {
		t.Errorf("root listing = %v, want empty", got)
	}
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files?rootDir=dir",
		"/api/v0/files/stat?filePath=a.txt",
		"/api/v0/files/download?filePath=a.txt",
		"/api/v0/files/download?filePath=dir",
	)
}

func TestAccess_ReadShareCanListAndDownload(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/f.txt")
	writeFixture(t, h.filesDir, "shared/sub/g.txt")
	writeFixture(t, h.filesDir, "other.txt")
	writeZip(t, h.filesDir, "shared/a.zip")
	writeZip(t, h.filesDir, "private/b.zip")
	h.grant(t, "shared", accessutil.Read)

	if got, want := h.names(t, ""), []string{"shared"}; !slices.Equal(got, want) {
		t.Errorf("root listing = %v, want %v", got, want)
	}
	if got, want := h.names(t, "shared"), []string{"a.zip", "f.txt", "sub"}; !slices.Equal(got, want) {
		t.Errorf("shared listing = %v, want %v", got, want)
	}
	w := h.get("/api/v0/files/download?filePath=shared/f.txt")
	if w.Code != http.StatusOK || w.Body.String() != "fixture shared/f.txt" {
		t.Errorf("download = %d %q", w.Code, w.Body.String())
	}
	h.expectStatus(t, http.StatusOK,
		"/api/v0/files/stat?filePath=shared/sub/g.txt",
		"/api/v0/files/list-archive?filePath=shared/a.zip",
		"/api/v0/files/download-archive-file?filePath=shared/a.zip&entryPath=inside.txt",
	)
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files/download?filePath=other.txt",
		"/api/v0/files/list-archive?filePath=private/b.zip",
		"/api/v0/files/download-archive-file?filePath=private/b.zip&entryPath=inside.txt",
	)
}

func TestAccess_DeepShareShowsBreadcrumbs(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "Family/Bob/x.txt")
	writeFixture(t, h.filesDir, "Family/Alice/y.txt")
	writeFixture(t, h.filesDir, "Family/notes.txt")
	writeFixture(t, h.filesDir, "Work/z.txt")
	h.grant(t, "Family/Bob", accessutil.Read)

	for rootDir, want := range map[string][]string{
		"":           {"Family"},
		"Family":     {"Bob"},
		"Family/Bob": {"x.txt"},
	} {
		if got := h.names(t, rootDir); !slices.Equal(got, want) {
			t.Errorf("listing %q = %v, want %v", rootDir, got, want)
		}
	}
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files?rootDir=Work",
		"/api/v0/files?rootDir=Family/Alice",
		"/api/v0/files/stat?filePath=Family",
		"/api/v0/files/download?filePath=Family/notes.txt",
	)
}

func TestAccess_SymlinkOutOfAShareIsNotFound(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "private/secret.txt")
	writeFixture(t, h.filesDir, "shared/f.txt")
	if err := os.Symlink(filepath.Join(h.filesDir, "private", "secret.txt"),
		filepath.Join(h.filesDir, "shared", "link.txt")); err != nil {
		t.Fatal(err)
	}
	h.grant(t, "shared", accessutil.Read)

	if got, want := h.names(t, "shared"), []string{"f.txt"}; !slices.Equal(got, want) {
		t.Errorf("shared listing = %v, want %v", got, want)
	}
	h.expectStatus(t, http.StatusNotFound, "/api/v0/files/download?filePath=shared/link.txt")

	// Downloading the folder zips it; the link must not carry the secret in.
	w := h.get("/api/v0/files/download?filePath=shared")
	if w.Code != http.StatusOK {
		t.Fatalf("folder download = %d: %s", w.Code, w.Body.String())
	}
	zr, err := zip.NewReader(bytes.NewReader(w.Body.Bytes()), int64(w.Body.Len()))
	if err != nil {
		t.Fatalf("read zip: %v", err)
	}
	zipped := make([]string, 0, len(zr.File))
	for _, f := range zr.File {
		zipped = append(zipped, f.Name)
	}
	if want := []string{"f.txt"}; !slices.Equal(zipped, want) {
		t.Errorf("zipped entries = %v, want %v", zipped, want)
	}
}

// An unknown serial used to fall back to the internal drive (#1903), which
// would have served a path granted there under a device the caller named.
func TestAccess_UnknownSerialIsNotFound(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "a.txt")
	h.grant(t, "", accessutil.Owner)

	h.expectStatus(t, http.StatusOK, "/api/v0/files/download?filePath=a.txt")
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files/download?filePath=a.txt&serial=NOPE",
		"/api/v0/files/stat?filePath=a.txt&serial=NOPE",
	)
}

func (h accessHarness) move(oldPath, newPath string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]string{"oldFilePath": oldPath, "newFilePath": newPath})
	return doRequest(h.engine, http.MethodPut, "/api/v0/files", bytes.NewReader(body), "application/json")
}

// newFolder creates name inside dir; "/" is the root.
func (h accessHarness) newFolder(dir, name string) *httptest.ResponseRecorder {
	return doRequest(h.engine, http.MethodPost, "/api/v0/files/folder/"+dir,
		strings.NewReader("folderName="+url.QueryEscape(name)), "application/x-www-form-urlencoded")
}

func (h accessHarness) post(path string) *httptest.ResponseRecorder {
	return doRequest(h.engine, http.MethodPost, path, nil, "")
}

func (h accessHarness) del(rootDir, name string) *httptest.ResponseRecorder {
	return doRequest(h.engine, http.MethodDelete,
		"/api/v0/files?rootDir="+url.QueryEscape(rootDir)+"&filePaths="+url.QueryEscape(name), nil, "")
}

// levels returns every row as rel_path → level.
func (h accessHarness) levels(t *testing.T) map[string]string {
	t.Helper()
	rows, err := h.database.Db.Query(`SELECT rel_path, level FROM path_access`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	levels := map[string]string{}
	for rows.Next() {
		var rel, level string
		if err := rows.Scan(&rel, &level); err != nil {
			t.Fatal(err)
		}
		levels[rel] = level
	}
	return levels
}

func expectCodes(t *testing.T, want int, responses map[string]*httptest.ResponseRecorder) {
	t.Helper()
	for name, w := range responses {
		if w.Code != want {
			t.Errorf("%s = %d, want %d: %s", name, w.Code, want, w.Body.String())
		}
	}
}

func expectExists(t *testing.T, filesDir string, rels ...string) {
	t.Helper()
	for _, rel := range rels {
		if _, err := os.Lstat(filepath.Join(filesDir, filepath.FromSlash(rel))); err != nil {
			t.Errorf("%s is gone: %v", rel, err)
		}
	}
}

func TestAccess_ReadShareCannotChange(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/f.txt")
	writeZip(t, h.filesDir, "shared/a.zip")
	writeFixture(t, h.filesDir, "other/o.txt")
	h.grant(t, "shared", accessutil.Read)

	expectCodes(t, http.StatusForbidden, map[string]*httptest.ResponseRecorder{
		"move":       h.move("shared/f.txt", "shared/g.txt"),
		"delete":     h.del("shared", "f.txt"),
		"new folder": h.newFolder("shared", "new"),
		"extract":    h.post("/api/v0/files/extract?filePath=shared/a.zip"),
		"convert":    h.post("/api/v0/files/convert/xlsx?filePath=shared/book.xlsx"),
	})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"move from outside": h.move("other/o.txt", "shared/o.txt"),
		"delete outside":    h.del("other", "o.txt"),
		"folder outside":    h.newFolder("other", "new"),
		"extract outside":   h.post("/api/v0/files/extract?filePath=other/o.zip"),
	})
	expectExists(t, h.filesDir, "shared/f.txt", "other/o.txt")
	if _, err := os.Lstat(filepath.Join(h.filesDir, "shared", "a")); err == nil {
		t.Error("a forbidden extraction wrote shared/a")
	}
	if n := h.rowCount(t); n != 1 {
		t.Errorf("rows = %d, want only the share", n)
	}
}

func TestAccess_WriteShareOwnsWhatItCreates(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/f.txt")
	writeZip(t, h.filesDir, "shared/a.zip")
	writeFixture(t, h.filesDir, "shared/existing/e.txt")
	writeFixture(t, h.filesDir, "other/o.txt")
	h.grant(t, "shared", accessutil.Write)

	expectCodes(t, http.StatusOK, map[string]*httptest.ResponseRecorder{
		"new folder":      h.newFolder("shared", "new"),
		"existing folder": h.newFolder("shared", "existing"),
		"extract":         h.post("/api/v0/files/extract?filePath=shared/a.zip"),
	})
	if w := h.move("shared/f.txt", "shared/new/f.txt"); w.Code != http.StatusOK {
		t.Fatalf("move within the share = %d: %s", w.Code, w.Body.String())
	}
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"move out of the share": h.move("shared/new/f.txt", "other/f.txt"),
	})
	expectExists(t, h.filesDir, "shared/new/f.txt", "shared/a/inside.txt")

	want := map[string]string{"shared": "write", "shared/new": "owner", "shared/a": "owner"}
	if got := h.levels(t); len(got) != len(want) || got["shared"] != want["shared"] ||
		got["shared/new"] != want["shared/new"] || got["shared/a"] != want["shared/a"] {
		t.Errorf("rows = %v, want %v", got, want)
	}

	if w := h.del("shared/new", "f.txt"); w.Code != http.StatusOK {
		t.Errorf("delete within the share = %d: %s", w.Code, w.Body.String())
	}
}

// as switches who the harness's requests act as.
func (h accessHarness) as(principal accessutil.Principal) {
	*h.principal = principal
}

// upload sends one multipart file into dir; "" is the top-level directory.
func (h accessHarness) upload(t *testing.T, dir, name string, overwrite bool) *httptest.ResponseRecorder {
	t.Helper()
	target := "/api/v0/files/upload"
	if dir != "" {
		target += "/" + dir
	}
	if overwrite {
		target += "?overwrite=true"
	}
	return uploadFile(t, h.engine, target, name, "content of "+name)
}

func (h accessHarness) openSession(t *testing.T, dir, name string, size int) *httptest.ResponseRecorder {
	t.Helper()
	return openSession(t, h.engine, map[string]any{"rootDir": dir, "fileName": name, "totalSize": size})
}

// uploadInOneChunk sends a small file through a resumable session and fails
// the test unless it commits.
func (h accessHarness) uploadInOneChunk(t *testing.T, dir, name string) {
	t.Helper()
	opened := h.openSession(t, dir, name, 4)
	if opened.Code != http.StatusOK {
		t.Fatalf("open session in %q = %d: %s", dir, opened.Code, opened.Body.String())
	}
	w := putChunk(t, h.engine, decodeSession(t, opened).SessionID, 0, 3, 4, []byte("abcd"))
	if w.Code != http.StatusOK || !decodeSession(t, w).Complete {
		t.Fatalf("chunk in %q = %d: %s", dir, w.Code, w.Body.String())
	}
}

func TestAccess_ReadShareCannotUpload(t *testing.T) {
	h := newAccessHarness(t, false)
	h.grant(t, "shared", accessutil.Read)

	expectCodes(t, http.StatusForbidden, map[string]*httptest.ResponseRecorder{
		"multipart": h.upload(t, "shared", "f.txt", false),
		"session":   h.openSession(t, "shared", "f.txt", 4),
	})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"multipart outside": h.upload(t, "other", "f.txt", false),
		"top level":         h.upload(t, "", "f.txt", false),
		"session outside":   h.openSession(t, "other", "f.txt", 4),
	})
	for _, rel := range []string{"shared/f.txt", "other/f.txt", "f.txt"} {
		if _, err := os.Lstat(filepath.Join(h.filesDir, filepath.FromSlash(rel))); err == nil {
			t.Errorf("a refused upload wrote %s", rel)
		}
	}
}

func TestAccess_UploadOwnsOnlyNewFiles(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/existing.txt")
	h.grant(t, "shared", accessutil.Write)
	h.grant(t, "mine", accessutil.Owner)

	expectCodes(t, http.StatusOK, map[string]*httptest.ResponseRecorder{
		"new file":           h.upload(t, "shared", "new.txt", false),
		"overwrite":          h.upload(t, "shared", "existing.txt", true),
		"into an own folder": h.upload(t, "mine", "x.txt", false),
	})
	h.uploadInOneChunk(t, "shared", "chunked.bin")

	want := map[string]string{
		"shared":             "write",
		"mine":               "owner",
		"shared/new.txt":     "owner",
		"shared/chunked.bin": "owner",
	}
	if got := h.levels(t); !maps.Equal(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

func TestAccess_UploadSessionBelongsToItsOpener(t *testing.T) {
	h := newAccessHarness(t, false)
	ctx := context.Background()
	h.grant(t, "shared", accessutil.Write)
	bob := *h.principal
	eve, err := h.database.Queries.CreateUser(ctx, db.CreateUserParams{
		Username: "eve", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := h.database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "shared", UserID: sql.NullInt64{Int64: eve.ID, Valid: true}, Level: accessutil.Write.String(),
	}); err != nil {
		t.Fatal(err)
	}

	opened := h.openSession(t, "shared", "f.bin", 4)
	if opened.Code != http.StatusOK {
		t.Fatalf("open session = %d: %s", opened.Code, opened.Body.String())
	}
	id := decodeSession(t, opened).SessionID

	h.as(accessutil.Principal{UserID: eve.ID})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"get":    getSession(t, h.engine, id),
		"chunk":  putChunk(t, h.engine, id, 0, 3, 4, []byte("abcd")),
		"delete": doRequest(h.engine, http.MethodDelete, "/api/v0/files/upload-session/"+id, nil, ""),
	})

	h.as(bob)
	if w := getSession(t, h.engine, id); w.Code != http.StatusOK || decodeSession(t, w).Offset != 0 {
		t.Errorf("the opener lost the session: %d %s", w.Code, w.Body.String())
	}
}

// Rows follow a folder rename, and then the file into the trash, so nothing
// is left behind at a path that no longer exists (#1905).
func TestAccess_RowsFollowARenameAndADelete(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/a/x.txt")
	h.grant(t, "shared", accessutil.Write)
	h.grant(t, "shared/a/x.txt", accessutil.Owner)

	if w := h.move("shared/a", "shared/b"); w.Code != http.StatusOK {
		t.Fatalf("rename = %d: %s", w.Code, w.Body.String())
	}
	if got, want := h.levels(t), map[string]string{"shared": "write", "shared/b/x.txt": "owner"}; !maps.Equal(got, want) {
		t.Fatalf("rows after the rename = %v, want %v", got, want)
	}

	if w := h.del("shared/b", "x.txt"); w.Code != http.StatusOK {
		t.Fatalf("delete = %d: %s", w.Code, w.Body.String())
	}
	got := h.levels(t)
	trashed := 0
	for rel, level := range got {
		if strings.HasPrefix(rel, ".trash/") && strings.HasSuffix(rel, "_x.txt") && level == "owner" {
			trashed++
		}
	}
	if len(got) != 2 || got["shared"] != "write" || trashed != 1 {
		t.Errorf("rows after the delete = %v, want the share and the owner row under .trash", got)
	}
}

// The single-admin regression for uploads: they behave as before and never
// write a row.
func TestAccess_AdminUploadsWriteNoRows(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "existing.txt")

	expectCodes(t, http.StatusOK, map[string]*httptest.ResponseRecorder{
		"new file":  h.upload(t, "", "new.txt", false),
		"overwrite": h.upload(t, "", "existing.txt", true),
		"nested":    h.upload(t, "docs", "n.txt", false),
	})
	h.uploadInOneChunk(t, "", "chunked.bin")

	expectExists(t, h.filesDir, "new.txt", "docs/n.txt", "chunked.bin")
	if n := h.rowCount(t); n != 0 {
		t.Errorf("path_access rows after admin uploads = %d, want 0", n)
	}
}

// The single-admin regression: an admin's mutations behave as before and
// never write a row.
func TestAccess_AdminMutationsWriteNoRows(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "f.txt")
	writeZip(t, h.filesDir, "a.zip")

	expectCodes(t, http.StatusOK, map[string]*httptest.ResponseRecorder{
		"new folder": h.newFolder("/", "new"),
		"extract":    h.post("/api/v0/files/extract?filePath=a.zip"),
	})
	if w := h.move("f.txt", "new/f.txt"); w.Code != http.StatusOK {
		t.Fatalf("move = %d: %s", w.Code, w.Body.String())
	}
	if w := h.del("new", "f.txt"); w.Code != http.StatusOK {
		t.Errorf("delete = %d: %s", w.Code, w.Body.String())
	}
	expectExists(t, h.filesDir, "new", "a/inside.txt")
	if n := h.rowCount(t); n != 0 {
		t.Errorf("path_access rows after admin mutations = %d, want 0", n)
	}
}

func TestAccess_AdminSeesEverything(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "a.txt")
	writeFixture(t, h.filesDir, "dir/b.txt")

	if got, want := h.names(t, ""), []string{"a.txt", "dir"}; !slices.Equal(got, want) {
		t.Errorf("admin root listing = %v, want %v", got, want)
	}
	h.expectStatus(t, http.StatusOK,
		"/api/v0/files?rootDir=dir",
		"/api/v0/files/stat?filePath=dir/b.txt",
		"/api/v0/files/download?filePath=dir/b.txt",
	)
	if n := h.rowCount(t); n != 0 {
		t.Errorf("path_access rows after admin requests = %d, want 0", n)
	}
}

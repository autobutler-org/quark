package v0_access_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_access "github.com/autobutler-org/quark/internal/server/api/v0/access"
	v0_events "github.com/autobutler-org/quark/internal/server/api/v0/events"
	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/gin-gonic/gin"
)

type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

// harness is the access, files and events routers over one real device and a
// migrated database. Each request acts as the account its ?as= names, as an
// admin when it carries admin=1.
type harness struct {
	srv      *httptest.Server
	users    map[string]int64
	database *db.DatabaseSqlc
}

func newHarness(t *testing.T) harness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filepath.Join(filesDir, "family"), 0o755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	users := map[string]int64{}
	for _, name := range []string{"bob", "carol", "dave"} {
		user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		users[name] = user.ID
	}
	if err := database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: "family", UserID: sql.NullInt64{Int64: users["bob"], Valid: true}, Level: accessutil.Owner.String(),
	}); err != nil {
		t.Fatal(err)
	}

	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithEventBus(eventbus.New()).
		WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "username", c.Query("as"))
		c = ctxutil.With(c, "principal", accessutil.Principal{
			UserID:  users[c.Query("as")],
			IsAdmin: c.Query("admin") == "1",
		})
		c.Next()
	})
	group := engine.Group("/api/v0")
	for _, r := range []serverutil.Router{v0_access.NewRouter(), v0_files.NewRouter(), v0_events.NewRouter()} {
		serverutil.RegisterRouterWithGroup(group, r)
	}
	srv := httptest.NewServer(engine)
	t.Cleanup(srv.Close)
	return harness{srv: srv, users: users, database: database}
}

func (h harness) do(t *testing.T, method, path, body string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(method, h.srv.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out bytes.Buffer
	if _, err := out.ReadFrom(resp.Body); err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, out.String()
}

// rootNames lists the device root as one account.
func (h harness) rootNames(t *testing.T, as string) []string {
	t.Helper()
	code, body := h.do(t, http.MethodGet, "/api/v0/files?rootDir=&as="+as, "")
	if code != http.StatusOK {
		t.Fatalf("list root as %s = %d %s", as, code, body)
	}
	var entries []struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal([]byte(body), &entries); err != nil {
		t.Fatalf("decode %s: %v", body, err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, strings.TrimRight(e.Name, "/"))
	}
	slices.Sort(names)
	return names
}

func errorText(t *testing.T, body string) string {
	t.Helper()
	var out struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal([]byte(body), &out); err != nil {
		t.Fatalf("decode %q: %v", body, err)
	}
	return out.Error
}

// TestAccess_ShareAndUnshare has bob, who owns family, share it with carol and
// take it back: carol's listing gains and loses the folder, her open stream
// hears access_changed both times, and while she only reads it she can't see
// its sharing. dave, who can't read it, gets 404.
func TestAccess_ShareAndUnshare(t *testing.T) {
	h := newHarness(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(h.srv.URL, "http")+"/api/v0/events?as=carol", nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.CloseNow() })
	time.Sleep(200 * time.Millisecond)
	hearsAccessChanged := func() {
		t.Helper()
		var evt eventbus.Event
		if err := wsjson.Read(ctx, conn, &evt); err != nil || evt != (eventbus.Event{Kind: eventbus.EventAccessChanged, Path: "family"}) {
			t.Fatalf("carol's stream read %+v, %v; want access_changed for family", evt, err)
		}
	}
	carol := strconv.FormatInt(h.users["carol"], 10)

	if got := h.rootNames(t, "carol"); len(got) != 0 {
		t.Fatalf("carol sees %v before the share", got)
	}
	code, body := h.do(t, http.MethodPut, "/api/v0/access?as=bob", `{"relPath":"family","userId":`+carol+`,"level":"read"}`)
	if code != http.StatusOK {
		t.Fatalf("share = %d %s", code, body)
	}
	var result accessutil.GrantsResult
	if err := json.Unmarshal([]byte(body), &result); err != nil {
		t.Fatal(err)
	}
	wantGrants := []accessutil.Grant{
		{UserID: h.users["bob"], Name: "bob", Level: "owner", From: "family"},
		{UserID: h.users["carol"], Name: "carol", Level: "read", From: "family"},
	}
	if result.RelPath != "family" || !result.CanManage || !result.CanGrantOwner || !slices.Equal(result.Grants, wantGrants) {
		t.Errorf("share answered %+v", result)
	}
	hearsAccessChanged()
	if got := h.rootNames(t, "carol"); !slices.Equal(got, []string{"family"}) {
		t.Errorf("carol sees %v after the share, want [family]", got)
	}

	if code, body := h.do(t, http.MethodGet, "/api/v0/access?relPath=family&as=bob", ""); code != http.StatusOK || !strings.Contains(body, `"canGrantOwner":true`) {
		t.Errorf("owner lists = %d %s", code, body)
	}
	if code, body := h.do(t, http.MethodGet, "/api/v0/access?relPath=family&as=carol", ""); code != http.StatusForbidden || errorText(t, body) != accessutil.ErrShareForbidden.Error() {
		t.Errorf("reader lists = %d %s, want 403", code, body)
	}
	if code, body := h.do(t, http.MethodGet, "/api/v0/access?relPath=family&as=dave", ""); code != http.StatusNotFound || errorText(t, body) != accessutil.ErrShareNotFound.Error() {
		t.Errorf("stranger lists = %d %s, want 404", code, body)
	}
	if code, body := h.do(t, http.MethodPut, "/api/v0/access?as=bob", `{"relPath":"family","userId":`+carol+`,"level":"admin"}`); code != http.StatusBadRequest || errorText(t, body) != accessutil.ErrInvalidLevel.Error() {
		t.Errorf("share at an unknown level = %d %s, want 400", code, body)
	}
	if code, body := h.do(t, http.MethodDelete, "/api/v0/access?as=bob", `{"relPath":"family/sub","userId":`+carol+`}`); code != http.StatusConflict || errorText(t, body) != accessutil.ErrInheritedGrant.Error() {
		t.Errorf("revoke inherited = %d %s, want 409", code, body)
	}

	if code, body := h.do(t, http.MethodDelete, "/api/v0/access?as=bob", `{"relPath":"family","userId":`+carol+`}`); code != http.StatusOK {
		t.Fatalf("unshare = %d %s", code, body)
	}
	hearsAccessChanged()
	if got := h.rootNames(t, "carol"); len(got) != 0 {
		t.Errorf("carol sees %v after the unshare", got)
	}
}

// TestAccess_StructuralRootsAreRefused has bob try to share users and groups
// themselves: a grant on either would reach every home or every group folder,
// so both answer 400 before any ownership check (#2016).
func TestAccess_StructuralRootsAreRefused(t *testing.T) {
	h := newHarness(t)
	carol := strconv.FormatInt(h.users["carol"], 10)
	for _, rel := range []string{"users", "groups/"} {
		code, body := h.do(t, http.MethodPut, "/api/v0/access?as=bob", `{"relPath":"`+rel+`","userId":`+carol+`,"level":"read"}`)
		if code != http.StatusBadRequest || errorText(t, body) != accessutil.ErrStructuralShare.Error() {
			t.Errorf("share %s = %d %s, want 400", rel, code, body)
		}
	}
}

// sharedWithMe is what the Shared with me shortcut lists for one account.
func (h harness) sharedWithMe(t *testing.T, query string) []accessutil.SharedItem {
	t.Helper()
	code, body := h.do(t, http.MethodGet, "/api/v0/access/mine?"+query, "")
	if code != http.StatusOK {
		t.Fatalf("GET /access/mine?%s = %d %s", query, code, body)
	}
	var out accessutil.ListSharedWithMeResult
	if err := json.Unmarshal([]byte(body), &out); err != nil {
		t.Fatalf("decode %s: %v", body, err)
	}
	return out.Items
}

// TestAccess_SharedWithMe has bob share family with carol: it is what carol's
// Shared with me lists, labeled with bob, while her own home and her group's
// folder stay out of it. dave, whom nothing was shared with, and an admin, who
// bypasses the table, both get nothing (#2139).
func TestAccess_SharedWithMe(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	group, err := h.database.Queries.CreateGroup(ctx, "family")
	if err != nil {
		t.Fatal(err)
	}
	for _, grant := range []struct {
		rel   string
		user  string
		level accessutil.Level
	}{
		{"users/bob", "bob", accessutil.Owner},
		{"users/carol", "carol", accessutil.Owner},
	} {
		if err := h.database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
			RelPath: grant.rel,
			UserID:  sql.NullInt64{Int64: h.users[grant.user], Valid: true},
			Level:   grant.level.String(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	if err := h.database.Queries.SetGroupPathAccess(ctx, db.SetGroupPathAccessParams{
		RelPath: "groups/family",
		GroupID: sql.NullInt64{Int64: group.ID, Valid: true},
		Level:   accessutil.Write.String(),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := h.database.Queries.AddGroupMember(ctx, db.AddGroupMemberParams{
		GroupID: group.ID,
		UserID:  h.users["carol"],
	}); err != nil {
		t.Fatal(err)
	}

	if got := h.sharedWithMe(t, "as=carol"); len(got) != 0 {
		t.Fatalf("carol is shown %+v before the share", got)
	}
	carol := strconv.FormatInt(h.users["carol"], 10)
	if code, body := h.do(t, http.MethodPut, "/api/v0/access?as=bob",
		`{"relPath":"family","userId":`+carol+`,"level":"read"}`); code != http.StatusOK {
		t.Fatalf("share = %d %s", code, body)
	}

	want := []accessutil.SharedItem{{RelPath: "family", Level: "read", Owner: "bob"}}
	if got := h.sharedWithMe(t, "as=carol"); !slices.Equal(got, want) {
		t.Errorf("carol is shown %+v, want %+v", got, want)
	}
	if got := h.sharedWithMe(t, "as=dave"); len(got) != 0 {
		t.Errorf("dave is shown %+v, want nothing", got)
	}
	if got := h.sharedWithMe(t, "as=carol&admin=1"); len(got) != 0 {
		t.Errorf("an admin is shown %+v, want nothing", got)
	}
}

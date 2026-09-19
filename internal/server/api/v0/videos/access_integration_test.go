package v0_videos_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_videos "github.com/autobutler-org/quark/internal/server/api/v0/videos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/transcodeutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory is the one
// storageutil.GetFilesDir resolves under HOME, the same directory the video
// handlers fall back to.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// videoHarness serves the video routes over a real files directory and a
// migrated database, acting as whoever principal names (#1904).
type videoHarness struct {
	engine    *gin.Engine
	filesDir  string
	database  *db.DatabaseSqlc
	userID    int64
	principal *accessutil.Principal
}

func newVideoHarness(t *testing.T) videoHarness {
	t.Helper()
	if !videoutil.Available() {
		t.Skip("ffmpeg and ffprobe are not installed")
	}
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	storage := storageutil.NewStorageService(systemDevice{})
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database})
	queue.Register(jobutil.RegisterParams{
		Kind:    transcodeutil.Kind,
		Handler: transcodeutil.NewHandler(transcodeutil.NewHandlerParams{Storage: storage}),
	})
	deps := deputil.NewDependencies().
		WithStorageService(storage).
		WithDatabase(database).
		WithJobQueue(queue)
	system := accessutil.System
	principal := &system

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_videos.NewRouter())

	h := videoHarness{engine: engine, filesDir: filesDir, database: database, userID: user.ID, principal: principal}
	h.writeVideo(t, "shared/clip.mp4")
	h.writeVideo(t, "private/clip.mp4")
	return h
}

func (h videoHarness) writeVideo(t *testing.T, rel string) {
	t.Helper()
	full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command("ffmpeg", "-f", "lavfi", "-i", "testsrc=duration=1:size=32x32:rate=5",
		"-c:v", "mpeg4", "-y", full).CombinedOutput()
	if err != nil {
		t.Fatalf("create %s: %v\n%s", rel, err, out)
	}
}

func (h videoHarness) grant(t *testing.T, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: rel,
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

// do sends a request and returns the status and, on success, the relPath the
// edit wrote.
func (h videoHarness) do(t *testing.T, method, path, body string) (int, string) {
	t.Helper()
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(method, path, strings.NewReader(body)))
	var out struct {
		RelPath string `json:"relPath"`
	}
	if w.Code == http.StatusOK && method == http.MethodPost {
		if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
			t.Fatalf("decode %s: %v", w.Body.String(), err)
		}
	}
	return w.Code, out.RelPath
}

// expect checks the status of metadata, extract-frame and trim on one video.
func (h videoHarness) expect(t *testing.T, rel string, metadata, edit int) {
	t.Helper()
	if code, _ := h.do(t, http.MethodGet, "/api/v0/videos/metadata?relPath="+rel, ""); code != metadata {
		t.Errorf("metadata %s = %d, want %d", rel, code, metadata)
	}
	if code, _ := h.do(t, http.MethodPost, "/api/v0/videos/extract-frame", `{"relPath":"`+rel+`"}`); code != edit {
		t.Errorf("extract-frame %s = %d, want %d", rel, code, edit)
	}
	if code, _ := h.do(t, http.MethodPost, "/api/v0/videos/trim", `{"relPath":"`+rel+`","startMs":0,"endMs":500}`); code != edit {
		t.Errorf("trim %s = %d, want %d", rel, code, edit)
	}
}

func (h videoHarness) level(t *testing.T, rel string) string {
	t.Helper()
	var level string
	err := h.database.Db.QueryRow(`SELECT level FROM path_access WHERE rel_path = ?`, rel).Scan(&level)
	if err != nil && err != sql.ErrNoRows {
		t.Fatal(err)
	}
	return level
}

func TestVideoAccess_AdminWritesNoRows(t *testing.T) {
	h := newVideoHarness(t)
	h.expect(t, "private/clip.mp4", http.StatusOK, http.StatusOK)
	var rows int
	if err := h.database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 0 {
		t.Errorf("admin video edits wrote %d access rows, want 0", rows)
	}
}

func TestVideoAccess_NonAdmin(t *testing.T) {
	h := newVideoHarness(t)
	*h.principal = accessutil.Principal{UserID: h.userID}

	h.expect(t, "shared/clip.mp4", http.StatusNotFound, http.StatusNotFound)

	h.grant(t, "shared", accessutil.Read)
	h.expect(t, "shared/clip.mp4", http.StatusOK, http.StatusForbidden)
	h.expect(t, "private/clip.mp4", http.StatusNotFound, http.StatusNotFound)

	h.grant(t, "shared", accessutil.Write)
	code, frame := h.do(t, http.MethodPost, "/api/v0/videos/extract-frame", `{"relPath":"shared/clip.mp4"}`)
	if code != http.StatusOK || h.level(t, frame) != "owner" {
		t.Errorf("extract-frame = %d, owner row on %q = %q, want 200 and owner", code, frame, h.level(t, frame))
	}
	code, clip := h.do(t, http.MethodPost, "/api/v0/videos/trim", `{"relPath":"shared/clip.mp4","startMs":0,"endMs":500}`)
	if code != http.StatusOK || h.level(t, clip) != "owner" {
		t.Errorf("trim = %d, owner row on %q = %q, want 200 and owner", code, clip, h.level(t, clip))
	}
	if got := h.level(t, "shared/clip.mp4"); got != "" {
		t.Errorf("source video gained a %q row, want none", got)
	}
}

// TestTranscodeAccess_NonAdmin queues a transcode only for a caller who can read
// the video and write its folder, and records them as the job's creator (#1979).
func TestTranscodeAccess_NonAdmin(t *testing.T) {
	h := newVideoHarness(t)
	*h.principal = accessutil.Principal{UserID: h.userID}
	transcode := func(rel string) int {
		code, _ := h.do(t, http.MethodPost, "/api/v0/videos/transcode", `{"relPath":"`+rel+`","format":"mov","quality":"original"}`)
		return code
	}

	for _, rel := range []string{"shared/clip.mp4", "shared/missing.mp4", "../../etc/passwd"} {
		if got := transcode(rel); got != http.StatusNotFound {
			t.Errorf("transcode %s with no access = %d, want 404", rel, got)
		}
	}
	h.grant(t, "shared", accessutil.Read)
	if got := transcode("shared/clip.mp4"); got != http.StatusForbidden {
		t.Errorf("transcode with read only = %d, want 403", got)
	}
	h.grant(t, "shared", accessutil.Write)
	if got := transcode("private/clip.mp4"); got != http.StatusNotFound {
		t.Errorf("transcode of an unshared video = %d, want 404", got)
	}
	if got := transcode("shared/clip.mp4"); got != http.StatusAccepted {
		t.Fatalf("transcode with write = %d, want 202", got)
	}

	var jobs int
	var creator sql.NullInt64
	if err := h.database.Db.QueryRow(`SELECT COUNT(*), MAX(user_id) FROM jobs`).Scan(&jobs, &creator); err != nil {
		t.Fatal(err)
	}
	if jobs != 1 || creator.Int64 != h.userID {
		t.Errorf("queued %d job(s) created by %v, want 1 created by %d", jobs, creator, h.userID)
	}
}

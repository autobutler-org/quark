package v0_files_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// newDownloadTokenEngine is the house engine with a named caller on the
// context, which the token endpoint needs to know who the download runs as.
// viaToken marks the request the way requireAuth does when a download token
// authenticated it.
func newDownloadTokenEngine(deps deputil.Dependencies, username string, viaToken bool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		if username != "" {
			c = ctxutil.With(c, "username", username)
		}
		if viaToken {
			c = ctxutil.With(c, "downloadToken", true)
		}
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_files.NewRouter())
	return engine
}

func TestCreateDownloadToken_IssuesATokenForThePath(t *testing.T) {
	deps := deputil.NewDependencies()
	engine := newDownloadTokenEngine(deps, "alice", false)

	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodPost,
		"/api/v0/files/download-token?filePath=users/video.mp4&serial=disk-1", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("got %d, want 200: %s", w.Code, w.Body.String())
	}
	var body struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}

	consumed, err := deps.DownloadTokens().ConsumeToken(downloadutil.ConsumeTokenParams{
		Token: body.Token, FilePath: "users/video.mp4", Serial: "disk-1",
	})
	if err != nil {
		t.Fatalf("ConsumeToken: %v", err)
	}
	if consumed.Username != "alice" {
		t.Errorf("username = %q, want alice", consumed.Username)
	}
}

func TestCreateDownloadToken_NeedsACaller(t *testing.T) {
	engine := newDownloadTokenEngine(deputil.NewDependencies(), "", false)

	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodPost,
		"/api/v0/files/download-token?filePath=users/video.mp4", nil))
	if w.Code != http.StatusUnauthorized {
		t.Errorf("got %d, want 401", w.Code)
	}
}

// TestDownload_TokenMakesAnAttachment verifies a download authenticated by a
// download token is always an attachment, so the browser saves it instead of
// opening it in the tab, while every other request keeps its disposition —
// the video player relies on inline (#2226).
func TestDownload_TokenMakesAnAttachment(t *testing.T) {
	deps, filesDir := newStorageVFSDeps(t)
	for _, name := range []string{"video.mp4", "café.mp4", filepath.Join("album", "a.jpg")} {
		full := filepath.Join(filesDir, name)
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("content"), 0644); err != nil {
			t.Fatal(err)
		}
	}

	for _, tc := range []struct {
		name, filePath string
		viaToken       bool
		want           string
	}{
		{"file with token", "video.mp4", true, `attachment; filename=video.mp4`},
		{"file without token", "video.mp4", false, `inline; filename=video.mp4`},
		{"non-ASCII name with token", "café.mp4", true, `attachment; filename*=utf-8''caf%C3%A9.mp4`},
		{"folder with token", "album", true, `attachment; filename=album.zip`},
		{"folder without token", "album", false, `attachment; filename="album.zip"`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			engine := newDownloadTokenEngine(deps, "alice", tc.viaToken)
			w := httptest.NewRecorder()
			engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet,
				"/api/v0/files/download?filePath="+url.QueryEscape(tc.filePath), nil))
			if w.Code != http.StatusOK {
				t.Fatalf("got %d, want 200: %s", w.Code, w.Body.String())
			}
			if got := w.Header().Get("Content-Disposition"); got != tc.want {
				t.Errorf("Content-Disposition = %q, want %q", got, tc.want)
			}
		})
	}
}

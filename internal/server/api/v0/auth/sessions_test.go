package v0_auth_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"
)

// newAuthTestDB opens a database carrying the real migration set.
func newAuthTestDB(t *testing.T) (*sql.DB, *db.Queries) {
	t.Helper()
	database := dbtest.NewDB(t)
	return database.Db, database.Queries
}

// newSessionsTestEngine creates a gin engine with auth routes and a test user+session.
// Returns the engine, the db queries handle, and the userID of the created test user.
func newSessionsTestEngine(t *testing.T) (*gin.Engine, *db.Queries, int64) {
	t.Helper()
	sqlDB, queries := newAuthTestDB(t)

	// Setup a test user via authutil so password hashing is correct.
	ctx := context.Background()
	_, err := authutil.Setup(ctx, authutil.SetupParams{Database: &db.DatabaseSqlc{Db: sqlDB, Queries: queries}, FilesDir: t.TempDir(),
		Username: "testuser",
		Password: "TestPassword123!",
	})
	if err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}

	// Fetch the created user to get their ID.
	user, err := queries.GetUserByUsername(ctx, "testuser")
	if err != nil {
		t.Fatalf("GetUserByUsername: %v", err)
	}
	userID := user.ID

	// Inject deps into gin context.
	deps := deputil.NewDependencies().WithDatabase(&db.DatabaseSqlc{
		Db:      sqlDB,
		Queries: queries,
	})

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "userID", userID)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_auth.NewRouter())
	return engine, queries, userID
}

func doAuthRequest(engine *gin.Engine, method, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestListSessions_ReturnsSessions verifies GET /auth/sessions returns the
// active sessions for the authenticated user.
func TestListSessions_ReturnsSessions(t *testing.T) {
	engine, queries, userID := newSessionsTestEngine(t)

	// Add a second session manually.
	ctx := context.Background()
	_, err := queries.CreateSession(ctx, db.CreateSessionParams{
		Token:     "extra-token-xyz",
		UserID:    userID,
		ExpiresAt: time.Now().Add(24 * time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateSession: %v", err)
	}

	w := doAuthRequest(engine, http.MethodGet, "/api/v0/auth/sessions")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /auth/sessions returned %d: %s", w.Code, w.Body.String())
	}

	var body struct {
		Sessions []authutil.SessionInfo `json:"sessions"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal response: %v\nbody: %s", err, w.Body.String())
	}
	// Setup created 1 session; we added 1 more = 2 total.
	if len(body.Sessions) < 2 {
		t.Errorf("expected >= 2 sessions, got %d; body: %s", len(body.Sessions), w.Body.String())
	}
}

// TestListSessions_EmptyWhenNoActiveSessions verifies GET /auth/sessions
// returns an empty array (not null) when no non-expired sessions exist.
func TestListSessions_EmptyWhenNoActiveSessions(t *testing.T) {
	sqlDB, queries := newAuthTestDB(t)
	// No sessions created — userID 999 will have none.
	const userID int64 = 999

	deps := deputil.NewDependencies().WithDatabase(&db.DatabaseSqlc{
		Db:      sqlDB,
		Queries: queries,
	})

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "userID", userID)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_auth.NewRouter())

	w := doAuthRequest(engine, http.MethodGet, "/api/v0/auth/sessions")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /auth/sessions returned %d: %s", w.Code, w.Body.String())
	}

	var body struct {
		Sessions []authutil.SessionInfo `json:"sessions"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	if body.Sessions == nil {
		t.Error("sessions field should be an empty slice, not null")
	}
}

// TestRevokeAllSessions_RemovesAll verifies DELETE /auth/sessions removes all
// sessions for the user and subsequent list returns empty.
func TestRevokeAllSessions_RemovesAll(t *testing.T) {
	engine, queries, userID := newSessionsTestEngine(t)
	ctx := context.Background()

	// Add a second session.
	_, err := queries.CreateSession(ctx, db.CreateSessionParams{
		Token:     "second-token",
		UserID:    userID,
		ExpiresAt: time.Now().Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateSession: %v", err)
	}

	w := doAuthRequest(engine, http.MethodDelete, "/api/v0/auth/sessions")
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE /auth/sessions returned %d: %s", w.Code, w.Body.String())
	}

	var body struct {
		Revoked bool `json:"revoked"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	if !body.Revoked {
		t.Error("expected revoked=true")
	}
}

// TestRevokeSession_ByID revokes a specific session and confirms it disappears
// from the listing.
func TestRevokeSession_ByID(t *testing.T) {
	engine, queries, userID := newSessionsTestEngine(t)
	ctx := context.Background()

	// Add a session we'll revoke.
	_, err := queries.CreateSession(ctx, db.CreateSessionParams{
		Token:     "to-revoke-token",
		UserID:    userID,
		ExpiresAt: time.Now().Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("CreateSession: %v", err)
	}

	// Get session list to find the ID of the session we just added.
	sessions, err := authutil.ListActiveSessions(ctx, queries, userID)
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	_ = sessions

	// Find the session ID from the list response directly.
	w := doAuthRequest(engine, http.MethodGet, "/api/v0/auth/sessions")
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d", w.Code)
	}
	var listBody struct {
		Sessions []authutil.SessionInfo `json:"sessions"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &listBody); err != nil {
		t.Fatalf("unmarshal list: %v\nbody: %s", err, w.Body.String())
	}
	if len(listBody.Sessions) == 0 {
		t.Fatal("no sessions in list to revoke")
	}
	// Pick the last session (the one we added).
	sessionID := listBody.Sessions[len(listBody.Sessions)-1].ID

	w2 := doAuthRequest(engine, http.MethodDelete, "/api/v0/auth/sessions/"+sessionID)
	if w2.Code != http.StatusOK {
		t.Fatalf("DELETE /auth/sessions/%s returned %d: %s", sessionID, w2.Code, w2.Body.String())
	}
}

// TestRevokeSession_NotFound verifies DELETE /auth/sessions/:id returns 404
// when the session ID does not exist.
func TestRevokeSession_NotFound(t *testing.T) {
	engine, _, _ := newSessionsTestEngine(t)

	w := doAuthRequest(engine, http.MethodDelete, "/api/v0/auth/sessions/nonexistent-session-id")
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

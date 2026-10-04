package authutil_test

import (
	"context"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// setupUserWithSessions creates a user and N sessions, returning the user ID
// and the raw session tokens so callers can compute expected IDs.
func setupUserWithSessions(t *testing.T, q *db.Queries, n int) (int64, []string) {
	t.Helper()
	ctx := context.Background()

	user, err := q.CreateUser(ctx, db.CreateUserParams{
		Username:           "testuser",
		PasswordHash:       "hash",
		RecoveryPhraseHash: "rphash",
	})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	tokens := make([]string, n)
	for i := range n {
		tok, err := authutil.GenerateSessionToken()
		if err != nil {
			t.Fatalf("GenerateSessionToken: %v", err)
		}
		_, err = q.CreateSession(ctx, db.CreateSessionParams{
			Token:     tok,
			UserID:    user.ID,
			ExpiresAt: time.Now().Add(24 * time.Hour),
		})
		if err != nil {
			t.Fatalf("CreateSession: %v", err)
		}
		tokens[i] = tok
	}
	return user.ID, tokens
}

func TestListActiveSessions(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 3)

	sessions, err := authutil.ListActiveSessions(ctx, q, userID, "")
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	if len(sessions) != 3 {
		t.Errorf("expected 3 sessions, got %d", len(sessions))
	}
	for _, s := range sessions {
		if s.ID == "" {
			t.Error("session ID should not be empty")
		}
		if s.ExpiresAt.IsZero() {
			t.Error("session ExpiresAt should not be zero")
		}
	}
}

func TestListActiveSessions_Empty(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 0)

	sessions, err := authutil.ListActiveSessions(ctx, q, userID, "")
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	if len(sessions) != 0 {
		t.Errorf("expected 0 sessions, got %d", len(sessions))
	}
}

func TestRevokeSession(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 2)

	sessions, err := authutil.ListActiveSessions(ctx, q, userID, "")
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	if len(sessions) != 2 {
		t.Fatalf("expected 2 sessions before revoke, got %d", len(sessions))
	}

	targetID := sessions[0].ID
	deleted, err := authutil.RevokeSession(ctx, q, userID, targetID)
	if err != nil {
		t.Fatalf("RevokeSession: %v", err)
	}
	if !deleted {
		t.Error("expected deleted=true")
	}

	remaining, err := authutil.ListActiveSessions(ctx, q, userID, "")
	if err != nil {
		t.Fatalf("ListActiveSessions after revoke: %v", err)
	}
	if len(remaining) != 1 {
		t.Errorf("expected 1 session after revoke, got %d", len(remaining))
	}
	if remaining[0].ID == targetID {
		t.Error("revoked session still present")
	}
}

func TestRevokeSession_NotFound(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 1)

	deleted, err := authutil.RevokeSession(ctx, q, userID, "nonexistent-hash")
	if err != nil {
		t.Fatalf("RevokeSession: %v", err)
	}
	if deleted {
		t.Error("expected deleted=false for unknown session ID")
	}
}

func TestRevokeSession_WrongUser(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 1)

	sessions, _ := authutil.ListActiveSessions(ctx, q, userID, "")
	targetID := sessions[0].ID

	// Try to revoke with a different userID.
	deleted, err := authutil.RevokeSession(ctx, q, userID+99, targetID)
	if err != nil {
		t.Fatalf("RevokeSession: %v", err)
	}
	if deleted {
		t.Error("should not delete another user's session")
	}
}

func TestRevokeAllSessions(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 4)

	if err := authutil.RevokeAllSessions(ctx, q, userID); err != nil {
		t.Fatalf("RevokeAllSessions: %v", err)
	}

	remaining, err := authutil.ListActiveSessions(ctx, q, userID, "")
	if err != nil {
		t.Fatalf("ListActiveSessions after revoke-all: %v", err)
	}
	if len(remaining) != 0 {
		t.Errorf("expected 0 sessions after revoke-all, got %d", len(remaining))
	}
}

// TestListActiveSessions_MarksCurrentAndLastUsed verifies the listing carries
// each session's last use and flags only the session the caller named.
func TestListActiveSessions_MarksCurrentAndLastUsed(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, _ := setupUserWithSessions(t, q, 1)

	lastUsed := time.Now().Add(-time.Hour).UTC().Truncate(time.Second)
	if _, err := q.CreateSession(ctx, db.CreateSessionParams{
		Token:      "current-digest",
		UserID:     userID,
		ExpiresAt:  time.Now().Add(time.Hour),
		LastUsedAt: lastUsed,
	}); err != nil {
		t.Fatalf("CreateSession: %v", err)
	}

	sessions, err := authutil.ListActiveSessions(ctx, q, userID, "current-digest")
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	if len(sessions) != 2 {
		t.Fatalf("expected 2 sessions, got %d", len(sessions))
	}
	for _, s := range sessions {
		if s.Current != (s.ID == "current-digest") {
			t.Errorf("session %q: Current = %v", s.ID, s.Current)
		}
		if s.ID == "current-digest" && !s.LastUsedAt.Equal(lastUsed) {
			t.Errorf("LastUsedAt = %v, want %v", s.LastUsedAt, lastUsed)
		}
	}
}

// TestRevokeOtherSessions verifies every session but the named one goes, and
// that another user's sessions are left alone.
func TestRevokeOtherSessions(t *testing.T) {
	database := newTestDB(t)
	q := database.Queries
	ctx := context.Background()
	userID, tokens := setupUserWithSessions(t, q, 3)

	other, err := q.CreateUser(ctx, db.CreateUserParams{
		Username:           "other",
		PasswordHash:       "hash",
		RecoveryPhraseHash: "rphash",
	})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	if _, err := q.CreateSession(ctx, db.CreateSessionParams{
		Token:     "other-digest",
		UserID:    other.ID,
		ExpiresAt: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatalf("CreateSession: %v", err)
	}

	// setupUserWithSessions stores each token as given, so it is its own id.
	if err := authutil.RevokeOtherSessions(ctx, q, userID, tokens[1]); err != nil {
		t.Fatalf("RevokeOtherSessions: %v", err)
	}

	remaining, err := authutil.ListActiveSessions(ctx, q, userID, tokens[1])
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	if len(remaining) != 1 || remaining[0].ID != tokens[1] {
		t.Errorf("expected only the kept session to remain, got %+v", remaining)
	}
	if theirs, _ := authutil.ListActiveSessions(ctx, q, other.ID, ""); len(theirs) != 1 {
		t.Errorf("expected the other user's session to survive, got %d", len(theirs))
	}
}

// TestSessionID verifies a token's id is the digest its session is stored
// under, which is what lets the middleware name the caller's own session.
func TestSessionID(t *testing.T) {
	database := newTestDB(t)
	ctx := context.Background()
	result, err := authutil.Setup(ctx, authutil.SetupParams{
		Database: database, FilesDir: t.TempDir(),
		Username: "admin", AuthKey: dbtest.AuthKey("SecurePass1!"), SaltSecret: dbtest.SaltSecret,
	})
	if err != nil {
		t.Fatalf("Setup: %v", err)
	}
	user, err := database.Queries.GetUserByUsername(ctx, "admin")
	if err != nil {
		t.Fatalf("GetUserByUsername: %v", err)
	}
	sessions, err := authutil.ListActiveSessions(ctx, database.Queries, user.ID, authutil.SessionID(result.SessionToken))
	if err != nil {
		t.Fatalf("ListActiveSessions: %v", err)
	}
	if len(sessions) != 1 || !sessions[0].Current {
		t.Errorf("expected the setup session to be current, got %+v", sessions)
	}
}

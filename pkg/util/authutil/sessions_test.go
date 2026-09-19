package authutil_test

import (
	"context"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
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

	sessions, err := authutil.ListActiveSessions(ctx, q, userID)
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

	sessions, err := authutil.ListActiveSessions(ctx, q, userID)
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

	sessions, err := authutil.ListActiveSessions(ctx, q, userID)
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

	remaining, err := authutil.ListActiveSessions(ctx, q, userID)
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

	sessions, _ := authutil.ListActiveSessions(ctx, q, userID)
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

	remaining, err := authutil.ListActiveSessions(ctx, q, userID)
	if err != nil {
		t.Fatalf("ListActiveSessions after revoke-all: %v", err)
	}
	if len(remaining) != 0 {
		t.Errorf("expected 0 sessions after revoke-all, got %d", len(remaining))
	}
}

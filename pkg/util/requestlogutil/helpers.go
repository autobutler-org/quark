package requestlogutil

import (
	"context"
	"fmt"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
)

// legacyPath is the history file of a Quark from before the history moved
// into the database.
func legacyPath(dataDir string) string {
	return filepath.Join(dataDir, "account-request-history.jsonl")
}

// add inserts one decision. The same decision twice is one row.
func add(ctx context.Context, queries *db.Queries, entry Entry) error {
	if err := queries.AddAccountRequestDecision(ctx, db.AddAccountRequestDecisionParams{
		Username: entry.Username, Outcome: entry.Outcome, DecidedBy: entry.DecidedBy, DecidedAt: entry.DecidedAt,
	}); err != nil {
		return fmt.Errorf("record account request decision: %w", err)
	}
	return nil
}

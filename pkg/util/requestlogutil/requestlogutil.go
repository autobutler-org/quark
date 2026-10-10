// Package requestlogutil keeps the history of account request decisions: who
// asked, whether an admin approved or denied them, which admin, and when.
// authutil keeps none of that — a denial deletes the pending row and an
// approval only flips its status (#2730). The history is the
// account_request_history table, capped at the last MaxEntries decisions, so
// every instance on one database reads and adds to the same history (#3083).
// Import moves in the file it used to be, account-request-history.jsonl in
// the Quark's data directory.
package requestlogutil

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// MaxEntries is how many decisions the history keeps. Older ones are dropped.
const MaxEntries = 100

// The outcomes an Entry records.
const (
	OutcomeApproved = "approved"
	OutcomeDenied   = "denied"
)

// Entry is one decision an admin made about an account request.
type Entry struct {
	// Username is the account that asked.
	Username string `json:"username"`
	// Outcome is approved or denied.
	Outcome string `json:"outcome"`
	// DecidedBy is the username of the admin who decided.
	DecidedBy string `json:"decidedBy"`
	// DecidedAt is when they decided.
	DecidedAt time.Time `json:"decidedAt"`
}

// AppendParams is a decision to add to the history.
type AppendParams struct {
	Queries *db.Queries
	Entry   Entry
}

// AppendResult is empty; an appended decision has nothing to report.
type AppendResult struct{}

// ListParams locates the history.
type ListParams struct {
	Queries *db.Queries
}

// ListResult is the history, newest decision first and never nil.
type ListResult struct {
	Entries []Entry
}

// ImportParams locates the history file of a Quark from before the history
// moved into the database.
type ImportParams struct {
	Queries *db.Queries
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
}

// ImportResult reports what Import found.
type ImportResult struct {
	// Entries is how many decisions the file held. Zero when there was no file.
	Entries int
}

// Append adds a decision to the history and drops whatever falls past
// MaxEntries. The database keeps DecidedAt to the second.
func Append(ctx context.Context, params AppendParams) (AppendResult, error) {
	if err := add(ctx, params.Queries, params.Entry); err != nil {
		return AppendResult{}, err
	}
	if err := params.Queries.TrimAccountRequestHistory(ctx, MaxEntries); err != nil {
		return AppendResult{}, fmt.Errorf("trim account request history: %w", err)
	}
	return AppendResult{}, nil
}

// List returns the history, newest decision first. A Quark that has decided
// nothing has an empty history.
func List(ctx context.Context, params ListParams) (ListResult, error) {
	rows, err := params.Queries.ListAccountRequestHistory(ctx, MaxEntries)
	if err != nil {
		return ListResult{}, fmt.Errorf("list account request history: %w", err)
	}
	entries := make([]Entry, 0, len(rows))
	for _, row := range rows {
		entries = append(entries, Entry{
			Username: row.Username, Outcome: row.Outcome, DecidedBy: row.DecidedBy, DecidedAt: row.DecidedAt.UTC(),
		})
	}
	return ListResult{Entries: entries}, nil
}

// Import moves the history file of an older Quark into the database, oldest
// decision first, and renames it account-request-history.jsonl.imported so
// the next start finds nothing to do. A line that does not parse is skipped.
// A decision already in the database is not added twice, so two instances
// importing the same file at once end up with one copy. No file is nothing to
// do.
func Import(ctx context.Context, params ImportParams) (ImportResult, error) {
	path := legacyPath(params.DataDir)
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return ImportResult{}, nil
	}
	if err != nil {
		return ImportResult{}, fmt.Errorf("open account request history: %w", err)
	}
	defer f.Close()

	result := ImportResult{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		var entry Entry
		if json.Unmarshal(scanner.Bytes(), &entry) != nil {
			continue
		}
		if err := add(ctx, params.Queries, entry); err != nil {
			return ImportResult{}, err
		}
		result.Entries++
	}
	if err := scanner.Err(); err != nil {
		return ImportResult{}, fmt.Errorf("read account request history: %w", err)
	}
	if err := params.Queries.TrimAccountRequestHistory(ctx, MaxEntries); err != nil {
		return ImportResult{}, fmt.Errorf("trim account request history: %w", err)
	}
	// Another instance may have renamed it first; its rows are the same ones.
	if err := os.Rename(path, path+".imported"); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return ImportResult{}, fmt.Errorf("retire account request history file: %w", err)
	}
	return result, nil
}

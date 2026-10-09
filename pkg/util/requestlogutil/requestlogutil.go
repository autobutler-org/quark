// Package requestlogutil keeps the history of account request decisions: who
// asked, whether an admin approved or denied them, which admin, and when.
// authutil keeps none of that — a denial deletes the pending row and an
// approval only flips its status (#2730). The history is one JSON object per
// line in the Quark's data directory, account-request-history.jsonl, written
// 0600 and capped at the last MaxEntries decisions.
package requestlogutil

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"time"
)

// MaxEntries is how many decisions the history keeps. Older ones are dropped.
const MaxEntries = 100

// The outcomes an Entry records.
const (
	OutcomeApproved = "approved"
	OutcomeDenied   = "denied"
)

// mu serializes Append's read, trim and rewrite, so two decisions made at
// once both land. The one server process is the file's only writer.
var mu sync.Mutex

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
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
	Entry   Entry
}

// AppendResult is empty; an appended decision has nothing to report.
type AppendResult struct{}

// ListParams locates the history.
type ListParams struct {
	DataDir string
}

// ListResult is the history, newest decision first and never nil.
type ListResult struct {
	Entries []Entry
}

// Path returns the history file.
func Path(dataDir string) string {
	return filepath.Join(dataDir, "account-request-history.jsonl")
}

// Append adds a decision to the history and drops whatever falls past
// MaxEntries. The file is replaced by rename, so a reader never sees half of
// it.
func Append(params AppendParams) (AppendResult, error) {
	mu.Lock()
	defer mu.Unlock()

	listed, err := List(ListParams{DataDir: params.DataDir})
	if err != nil {
		return AppendResult{}, err
	}
	entries := append([]Entry{params.Entry}, listed.Entries...)
	entries = entries[:min(len(entries), MaxEntries)]

	// Whole in memory is fine: MaxEntries short records, bounded by us.
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	for _, entry := range slices.Backward(entries) {
		if err := enc.Encode(entry); err != nil {
			return AppendResult{}, fmt.Errorf("encode account request history: %w", err)
		}
	}
	if err := os.MkdirAll(params.DataDir, 0o700); err != nil {
		return AppendResult{}, fmt.Errorf("create data directory: %w", err)
	}
	path := Path(params.DataDir)
	if err := os.WriteFile(path+".tmp", buf.Bytes(), 0o600); err != nil {
		return AppendResult{}, fmt.Errorf("write account request history: %w", err)
	}
	if err := os.Rename(path+".tmp", path); err != nil {
		return AppendResult{}, fmt.Errorf("replace account request history: %w", err)
	}
	return AppendResult{}, nil
}

// List returns the history, newest decision first. A Quark that has decided
// nothing has no file and an empty history. A line that does not parse is
// skipped, so one damaged record does not hide the rest.
func List(params ListParams) (ListResult, error) {
	f, err := os.Open(Path(params.DataDir))
	if os.IsNotExist(err) {
		return ListResult{Entries: []Entry{}}, nil
	}
	if err != nil {
		return ListResult{}, fmt.Errorf("open account request history: %w", err)
	}
	defer f.Close()

	entries := []Entry{}
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		var entry Entry
		if json.Unmarshal(scanner.Bytes(), &entry) != nil {
			continue
		}
		entries = append(entries, entry)
	}
	if err := scanner.Err(); err != nil {
		return ListResult{}, fmt.Errorf("read account request history: %w", err)
	}
	slices.Reverse(entries)
	return ListResult{Entries: entries[:min(len(entries), MaxEntries)]}, nil
}

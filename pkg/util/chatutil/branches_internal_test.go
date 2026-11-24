package chatutil

import (
	"context"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// countingQuerier answers ListChatBranchSummariesBetween with rows and counts
// the calls. Any other query panics on the nil Querier.
type countingQuerier struct {
	db.Querier
	rows  []db.ListChatBranchSummariesBetweenRow
	calls int
}

func (q *countingQuerier) ListChatBranchSummariesBetween(_ context.Context, arg db.ListChatBranchSummariesBetweenParams) ([]db.ListChatBranchSummariesBetweenRow, error) {
	q.calls++
	return q.rows, nil
}

// TestAttachBranchesOneQueryPerPage attaches the branches of a 200-message
// page with a single query, and only to the messages that have one (#4346).
func TestAttachBranchesOneQueryPerPage(t *testing.T) {
	messages := make([]Message, 200)
	for i := range messages {
		messages[i].ID = int64(i*2 + 1)
	}
	at := time.Date(2026, 11, 24, 12, 0, 0, 0, time.UTC)
	q := &countingQuerier{rows: []db.ListChatBranchSummariesBetweenRow{
		{RootID: 1, ReplyCount: 3, LastReplyAt: at},
		{RootID: 2, ReplyCount: 9, LastReplyAt: at}, // not in the page
		{RootID: 399, ReplyCount: 1, LastReplyAt: at},
	}}
	if err := attachBranches(context.Background(), q, 7, messages); err != nil {
		t.Fatal(err)
	}
	if q.calls != 1 {
		t.Errorf("attachBranches ran %d queries for 200 messages, want 1", q.calls)
	}
	with := 0
	for _, m := range messages {
		if m.Branch != nil {
			with++
		}
	}
	if with != 2 || messages[0].Branch.ReplyCount != 3 || messages[199].Branch.ReplyCount != 1 {
		t.Errorf("branches on %d messages, first %+v, last %+v; want 2, 3 replies and 1", with, messages[0].Branch, messages[199].Branch)
	}
}

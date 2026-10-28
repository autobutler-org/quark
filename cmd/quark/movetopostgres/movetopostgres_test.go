package movetopostgres

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

func TestPrintSummary_SaysFileContentWasLeftEmptyRatherThanMatched(t *testing.T) {
	var out bytes.Buffer
	printSummary(&out, db.MoveToPostgresResult{
		Tables: []db.MovedTable{
			{Table: "users", Rows: 2},
			{Table: "file_content", Rows: 0, Rebuilt: true},
			{Table: "sessions", Rows: 3},
		},
		Elapsed: 1500 * time.Millisecond,
	})
	got := out.String()
	for _, want := range []string{
		"Moved 5 rows in 2 tables in 1.5s; every copied table matches its row count in SQLite.",
		"file_content was left empty, not copied: the server rebuilds it from the files when it starts.",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("summary is missing %q:\n%s", want, got)
		}
	}
}

package searchutil

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
)

// BenchmarkSearch measures one content search over 2,000 indexed documents of
// about 2 KiB each, a large personal library: the baseline #1780 measured
// before memoizing searches in the client.
func BenchmarkSearch(b *testing.B) {
	// dbtest.NewDB takes a *testing.T, so the benchmark opens its own copy of
	// the real schema the same way.
	sqlDB, err := sql.Open("sqlite", db.DSN(filepath.Join(b.TempDir(), "quark.db")))
	if err != nil {
		b.Fatal(err)
	}
	defer sqlDB.Close()
	if err := db.ResetDatabase(&db.DatabaseSqlc{Db: sqlDB, Queries: db.New(sqlDB)}); err != nil {
		b.Fatal(err)
	}
	ctx := context.Background()
	words := strings.Fields("quarterly budget meeting notes travel plans recipe garden invoice draft")
	for i := range 2000 {
		var text strings.Builder
		fmt.Fprintf(&text, "doc%04d ", i)
		for j := range 300 {
			text.WriteString(words[(i+j)%len(words)])
			text.WriteByte(' ')
		}
		if err := UpsertContent(ctx, sqlDB, "", fmt.Sprintf("docs/%04d.qdoc", i), text.String()); err != nil {
			b.Fatal(err)
		}
	}
	// "common" matches every document, so FTS5 ranks all of them to return
	// the top 50; "rare" matches one.
	for name, query := range map[string]string{"common": "budget", "rare": "doc1234"} {
		b.Run(name, func(b *testing.B) {
			for b.Loop() {
				if _, err := Search(ctx, sqlDB, query, 0); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}

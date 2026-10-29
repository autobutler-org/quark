package db

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
	"strings"
)

// ContentMatch is one content search hit.
type ContentMatch struct {
	// Serial is the storage device serial that holds the file.
	Serial string
	// RelPath is the file's path within the device's files directory.
	RelPath string
	// Snippet is an excerpt of the file's text with the matched terms wrapped
	// in <b>…</b>.
	Snippet string
}

// SearchContentParams is one page of a content search.
type SearchContentParams struct {
	// Query is the search text as the user typed it. Plain text is searched
	// as one phrase; FTS5 syntax (quotes, AND, OR, NOT, NEAR, prefix stars,
	// column filters) is honored on SQLite and translated on PostgreSQL.
	Query string
	// Limit and Offset pick the page out of the ranked matches. The caller
	// bounds Limit.
	Limit  int
	Offset int
}

// SearchContent runs a content search over file_content and returns up to
// Limit matches, best ranked first, after the first Offset.
//
// Raw SQL rather than sqlc, and one statement per engine, which is why it
// lives here and not in a caller: nothing outside this package branches on
// the engine. On SQLite it is FTS5's MATCH, rank and snippet(), which sqlc's
// SQLite parser does not accept. On PostgreSQL it is the tsvector column and
// GIN index from 041_content_search, ranked with ts_rank and excerpted with
// ts_headline. The two find the same files for the same words, stemmed the
// same way, but rank them by different formulas;
// docs/architecture/data.md says how they differ.
func SearchContent(ctx context.Context, sqlDB *sql.DB, params SearchContentParams) ([]ContentMatch, error) {
	var rows *sql.Rows
	var err error
	if BackendOf(sqlDB) == Postgres {
		function, text := postgresTSQuery(params.Query)
		rows, err = sqlDB.QueryContext(ctx, fmt.Sprintf(postgresContentSearch, function), text, params.Limit, params.Offset)
	} else {
		rows, err = sqlDB.QueryContext(ctx, sqliteContentSearch, FTS5Query(params.Query), params.Limit, params.Offset)
	}
	if err != nil {
		return nil, fmt.Errorf("content search: %w", err)
	}
	defer func() { _ = rows.Close() }()

	matches := []ContentMatch{}
	for rows.Next() {
		var m ContentMatch
		if err := rows.Scan(&m.Serial, &m.RelPath, &m.Snippet); err != nil {
			return nil, fmt.Errorf("scan content search result: %w", err)
		}
		matches = append(matches, m)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("content search: %w", err)
	}
	return matches, nil
}

// FTS5Query makes search text safe to hand to FTS5's MATCH. Text with no FTS5
// syntax becomes one quoted phrase, so a stray character cannot raise a
// syntax error; text that uses the syntax, with its quotes and parentheses
// paired, passes through, so "artist:nina" still filters a column. Empty
// text matches nothing.
func FTS5Query(q string) string {
	q = strings.TrimSpace(q)
	if q == "" {
		return `""`
	}
	if usesFTS5Syntax(q) {
		return q
	}
	return `"` + strings.ReplaceAll(q, `"`, `""`) + `"`
}

// sqliteContentSearch is SearchContent's statement on SQLite.
const sqliteContentSearch = `
	SELECT
	    fc.serial,
	    fc.rel_path,
	    snippet(file_content_fts, 0, '<b>', '</b>', '…', 20) AS snippet
	FROM file_content_fts
	JOIN file_content fc ON fc.id = file_content_fts.rowid
	WHERE file_content_fts MATCH ?
	ORDER BY rank
	LIMIT ? OFFSET ?`

// postgresContentSearch is SearchContent's statement on PostgreSQL, with the
// tsquery function postgresTSQuery picks in place of %s.
//
// The page is ranked and cut in the inner query and only then excerpted:
// ts_headline re-reads a file's whole text, so it runs for the rows returned
// and not for every match. ts_rank's normalization 1 divides by the log of
// the text's length, the nearest it has to bm25's length normalization.
const postgresContentSearch = `
	SELECT
	    fc.serial,
	    fc.rel_path,
	    ts_headline('english', fc.extracted, hit.q,
	        'StartSel=<b>, StopSel=</b>, MaxWords=20, MinWords=10, MaxFragments=1') AS snippet
	FROM (
	    SELECT fc.id, ts_rank(fc.search_vector, q, 1) AS rank, q
	    FROM file_content fc, %s('english', $1) AS q
	    WHERE fc.search_vector @@ q
	    ORDER BY rank DESC, fc.id
	    LIMIT $2 OFFSET $3
	) hit
	JOIN file_content fc ON fc.id = hit.id
	ORDER BY hit.rank DESC, hit.id`

// usesFTS5Syntax reports whether q is meant as an FTS5 query rather than
// plain text: it uses the syntax, and its quotes and parentheses pair up.
// FTS5 rejects unpaired ones as a syntax error, so such text is searched for
// as text instead.
func usesFTS5Syntax(q string) bool {
	upper := strings.ToUpper(q)
	balanced := strings.Count(q, `"`)%2 == 0 && strings.Count(q, "(") == strings.Count(q, ")")
	return balanced && (strings.ContainsAny(q, `"*:()`) ||
		strings.Contains(upper, " AND ") ||
		strings.Contains(upper, " OR ") ||
		strings.Contains(upper, " NOT ") ||
		strings.Contains(upper, "NEAR("))
}

// The FTS5 syntax postgresTSQuery rewrites for websearch_to_tsquery.
var (
	fts5ColumnFilter = regexp.MustCompile(`\{[^}]*\}\s*:|\b\w+\s*:`)
	fts5NearDistance = regexp.MustCompile(`,\s*\d+\s*\)`)
	fts5Near         = regexp.MustCompile(`\bNEAR\b`)
	fts5And          = regexp.MustCompile(`\bAND\b`)
	fts5Not          = regexp.MustCompile(`\bNOT\s+`)
)

// postgresTSQuery turns search text into the tsquery function and argument
// that find what FTS5Query's form finds on SQLite. Plain text is a phrase,
// phraseto_tsquery. FTS5 syntax goes to websearch_to_tsquery, which reads
// quoted phrases, OR and a leading minus: NOT becomes the minus, AND and NEAR
// become its implicit AND, and column filters and prefix stars are dropped,
// so a prefix matches its whole word only and parentheses do not group.
func postgresTSQuery(q string) (function, text string) {
	q = strings.TrimSpace(q)
	if !usesFTS5Syntax(q) {
		return "phraseto_tsquery", q
	}
	q = fts5ColumnFilter.ReplaceAllString(q, " ")
	q = fts5NearDistance.ReplaceAllString(q, ")")
	q = fts5Near.ReplaceAllString(q, " ")
	q = fts5And.ReplaceAllString(q, " ")
	q = fts5Not.ReplaceAllString(q, "-")
	return "websearch_to_tsquery", strings.ReplaceAll(q, "*", "")
}

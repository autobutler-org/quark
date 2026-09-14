package searchutil

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// Search runs a full-text query against the FTS5 index and returns up to
// limit results ordered by relevance rank. If limit <= 0, DefaultLimit is used.
// The query string is passed directly to FTS5's MATCH operator — callers
// should sanitize it for user-facing inputs (e.g. quote terms to avoid FTS5
// syntax errors).
func Search(ctx context.Context, db *sql.DB, query string, limit int) ([]SearchResult, error) {
	if limit <= 0 {
		limit = DefaultLimit
	}
	return searchPage(ctx, db, query, limit, 0)
}

// SearchReadableParams is a content search on behalf of one caller.
type SearchReadableParams struct {
	Ctx context.Context
	DB  *sql.DB
	// Query is passed to Search.
	Query string
	// Limit caps the results, DefaultLimit when zero or less.
	Limit int
	// Access drops the matches the caller cannot read. A snippet is file
	// content, so an unreadable match must not come back at all.
	Access accessutil.Access
}

// SearchReadableResult is up to Limit readable matches, best ranked first.
type SearchReadableResult struct {
	Results []SearchResult
}

// SearchReadable runs a content search and keeps only the matches the caller
// can read, still returning up to Limit of them when that many exist (#1907).
// An admin's search is the single query Search runs.
func SearchReadable(params SearchReadableParams) (SearchReadableResult, error) {
	limit := params.Limit
	if limit <= 0 {
		limit = DefaultLimit
	}
	if params.Access.Principal().IsAdmin {
		results, err := searchPage(params.Ctx, params.DB, params.Query, limit, 0)
		return SearchReadableResult{Results: results}, err
	}

	// ponytail: pages through the ranked matches in batches of twice the limit
	// and filters each batch in memory, so a caller who can read few of many
	// matches costs several queries. Upgrade to an EXISTS join on path_access
	// if it measures slow.
	batch := 2 * limit
	kept := make([]SearchResult, 0, limit)
	for offset := 0; ; offset += batch {
		page, err := searchPage(params.Ctx, params.DB, params.Query, batch, offset)
		if err != nil {
			return SearchReadableResult{}, err
		}
		for _, r := range page {
			if !params.Access.Check(r.Serial, r.RelPath, accessutil.Read).Readable {
				continue
			}
			kept = append(kept, r)
			if len(kept) == limit {
				return SearchReadableResult{Results: kept}, nil
			}
		}
		if len(page) < batch {
			return SearchReadableResult{Results: kept}, nil
		}
	}
}

// searchPage returns up to limit matches ranked after the first offset.
//
// This is the one statement in this package that stays raw rather than going
// through sqlc. MATCH, the rank ordering it implies, and snippet() are FTS5
// extensions that sqlc's SQLite parser does not accept; the writes next door
// in searchutil.go are ordinary SQL and are generated.
func searchPage(ctx context.Context, db *sql.DB, query string, limit, offset int) ([]SearchResult, error) {
	// Sanitize the query: wrap in double-quotes if it contains no FTS5
	// operators so a bare word search never triggers syntax errors.
	safeQuery := sanitizeFTSQuery(query)

	rows, err := db.QueryContext(ctx, `
		SELECT
		    fc.serial,
		    fc.rel_path,
		    snippet(file_content_fts, 0, '<b>', '</b>', '…', 20) AS snippet
		FROM file_content_fts
		JOIN file_content fc ON fc.id = file_content_fts.rowid
		WHERE file_content_fts MATCH ?
		ORDER BY rank
		LIMIT ? OFFSET ?`, safeQuery, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("fts5 search: %w", err)
	}
	defer rows.Close()

	var results []SearchResult
	for rows.Next() {
		var r SearchResult
		if err := rows.Scan(&r.Serial, &r.RelPath, &r.Snippet); err != nil {
			return nil, fmt.Errorf("scan search result: %w", err)
		}
		results = append(results, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("fts5 result iteration: %w", err)
	}
	if results == nil {
		results = []SearchResult{}
	}
	return results, nil
}

// sanitizeFTSQuery wraps the query in double-quotes if it contains no FTS5
// operators, preventing syntax errors from bare special characters.
// FTS5 operators: AND, OR, NOT, NEAR, column filters, prefix wildcards.
func sanitizeFTSQuery(q string) string {
	q = strings.TrimSpace(q)
	if q == "" {
		return `""`
	}
	// If the query already contains FTS5 operators or quotes, pass it through.
	upper := strings.ToUpper(q)
	if strings.ContainsAny(q, `"*:()`) ||
		strings.Contains(upper, " AND ") ||
		strings.Contains(upper, " OR ") ||
		strings.Contains(upper, " NOT ") ||
		strings.Contains(upper, "NEAR(") {
		return q
	}
	// Plain term(s) — wrap in double-quotes to treat as phrase search.
	return `"` + strings.ReplaceAll(q, `"`, `""`) + `"`
}

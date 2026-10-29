package searchutil

import (
	"context"
	"database/sql"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// Search runs a full-text query against the content index and returns up to
// limit results ordered by relevance rank. If limit <= 0, DefaultLimit is used,
// and a limit above MaxLimit is clamped to it. Plain text is searched as one
// phrase and FTS5 syntax is honored (db.SearchContentParams.Query).
func Search(ctx context.Context, db *sql.DB, query string, limit int) ([]SearchResult, error) {
	return searchPage(ctx, db, query, clampLimit(limit), 0)
}

// SearchReadableParams is a content search on behalf of one caller.
type SearchReadableParams struct {
	Ctx context.Context
	DB  *sql.DB
	// Query is passed to Search.
	Query string
	// Limit caps the results, DefaultLimit when zero or less and never more
	// than MaxLimit.
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
	limit := clampLimit(params.Limit)
	if params.Access.Principal().IsAdmin {
		results, err := searchPage(params.Ctx, params.DB, params.Query, limit, 0)
		return SearchReadableResult{Results: results}, err
	}

	page, err := ReadablePage(ReadablePageParams[SearchResult]{
		Limit: limit,
		Fetch: func(limit, offset int) ([]SearchResult, error) {
			return searchPage(params.Ctx, params.DB, params.Query, limit, offset)
		},
		Readable: func(r SearchResult) bool {
			return params.Access.Check(r.Serial, r.RelPath, accessutil.Read).Readable
		},
	})
	return SearchReadableResult(page), err
}

// readablePage is ReadablePage's loop.
//
// ponytail: pages through the ranked matches in batches of twice the limit
// and filters each batch in memory, so a caller who can read few of many
// matches costs several queries. Upgrade to an EXISTS join on path_access
// if it measures slow.
func readablePage[T any](params ReadablePageParams[T]) ([]T, error) {
	limit := min(max(params.Limit, 1), MaxLimit)
	batch := 2 * limit
	kept := []T{}
	for offset := 0; ; offset += batch {
		page, err := params.Fetch(batch, offset)
		if err != nil {
			return nil, err
		}
		for _, r := range page {
			if !params.Readable(r) {
				continue
			}
			kept = append(kept, r)
			if len(kept) == limit {
				return kept, nil
			}
		}
		if len(page) < batch {
			return kept, nil
		}
	}
}

// clampLimit bounds a caller's limit to (0, MaxLimit], using DefaultLimit for
// zero or less. The limit reaches a SQL LIMIT and sizes each fetched batch,
// so it must never trust the caller's value.
func clampLimit(limit int) int {
	if limit <= 0 {
		return DefaultLimit
	}
	return min(limit, MaxLimit)
}

// searchPage returns up to limit matches ranked after the first offset.
// db.SearchContent holds the statement, one per engine.
func searchPage(ctx context.Context, sqlDB *sql.DB, query string, limit, offset int) ([]SearchResult, error) {
	matches, err := db.SearchContent(ctx, sqlDB, db.SearchContentParams{Query: query, Limit: limit, Offset: offset})
	if err != nil {
		return nil, err
	}
	results := make([]SearchResult, len(matches))
	for i, m := range matches {
		results[i] = SearchResult(m)
	}
	return results, nil
}

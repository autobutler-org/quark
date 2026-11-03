package db

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"unicode/utf8"
)

// SearchIndexedFiles returns the next page of files in the filename index
// (044_file_index) on one device whose lowered name holds params.Query, which
// the caller lowers with strings.ToLower. The page is in (dir, name) order
// after (AfterDir, AfterName), so a caller pages by passing the last row back.
//
// A query of three or more characters on SQLite is answered from
// file_index_fts, the trigram index, through raw SQL: sqlc's SQLite parser does
// not accept MATCH on a virtual table. A shorter query has no trigram to look
// up, and PostgreSQL has no such index yet, so both read the rows in order
// through the generated ListIndexedFilesPage. The two give the same rows.
func SearchIndexedFiles(ctx context.Context, sqlDB *sql.DB, params ListIndexedFilesPageParams) ([]ListIndexedFilesPageRow, error) {
	if BackendOf(sqlDB) == Postgres || utf8.RuneCountInString(params.Query) < 3 {
		return NewQueries(sqlDB).ListIndexedFilesPage(ctx, params)
	}
	rows, err := sqlDB.QueryContext(ctx, sqliteIndexedFileSearch,
		`"`+strings.ReplaceAll(params.Query, `"`, `""`)+`"`,
		params.Serial, params.AfterDir, params.AfterDir, params.AfterName, params.Limit)
	if err != nil {
		return nil, fmt.Errorf("filename search: %w", err)
	}
	defer func() { _ = rows.Close() }()
	out := []ListIndexedFilesPageRow{}
	for rows.Next() {
		var r ListIndexedFilesPageRow
		if err := rows.Scan(&r.Dir, &r.Name, &r.Size, &r.ModTime); err != nil {
			return nil, fmt.Errorf("scan filename search result: %w", err)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("filename search: %w", err)
	}
	return out, nil
}

// sqliteIndexedFileSearch is ListIndexedFilesPage with the substring found
// through the trigram index. The query is one quoted FTS5 phrase, which on a
// trigram table matches exactly the rows whose search_name contains it.
const sqliteIndexedFileSearch = `
	SELECT f.dir, f.name, f.size, f.mod_time
	FROM file_index f
	WHERE f.id IN (SELECT rowid FROM file_index_fts WHERE file_index_fts MATCH ?)
	  AND f.serial = ?
	  AND f.is_dir = FALSE
	  AND f.dir >= ?
	  AND (f.dir > ? OR f.name > ?)
	ORDER BY f.dir, f.name
	LIMIT ?`

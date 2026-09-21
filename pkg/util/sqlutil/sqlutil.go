// Package sqlutil holds small conversions between Go values and database/sql types, and recognizes SQLite's
// unique-constraint errors.
package sqlutil

import (
	"database/sql"
	"time"
)

// NullInt64 converts a *int64 to a sql.NullInt64 for use in sqlc-generated queries.
func NullInt64(id *int64) sql.NullInt64 {
	if id == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: *id, Valid: true}
}

// FormatTime formats a time.Time as an RFC3339 UTC string for JSON responses.
func FormatTime(t time.Time) string {
	return t.UTC().Format(time.RFC3339)
}

// NullStringPtr converts a sql.NullString to a *string for JSON responses.
// Returns nil if the value is not valid (NULL in the DB).
func NullStringPtr(s sql.NullString) *string {
	if !s.Valid {
		return nil
	}
	return &s.String
}

package sqlutil

import "strings"

// IsUniqueConstraintErr reports whether err is a SQLite unique-constraint
// violation (modernc.org/sqlite surfaces these as error strings).
func IsUniqueConstraintErr(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed")
}

package authutil_test

import (
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// newTestDB returns a database carrying the real migration set. Shared by
// every test in this package.
func newTestDB(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	return dbtest.NewDB(t)
}

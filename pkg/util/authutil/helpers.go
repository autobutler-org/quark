package authutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sync"

	"github.com/autobutler-org/quark/internal/db"
)

// setupMu serializes founding setup so two first-boot requests cannot both
// observe an empty users table and both become admin (quark-project #118).
var setupMu sync.Mutex

// inTx runs fn against queries bound to one transaction, committing only if fn
// succeeds.
func inTx(ctx context.Context, database *db.DatabaseSqlc, fn func(*db.Queries) error) error {
	tx, err := database.Db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(database.Queries.WithTx(tx)); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

package backup

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
)

// MigrateVault copies the vault from source into target in one transaction on
// target. Whatever target already holds is replaced, not merged: a move cut
// short after its copy committed leaves one behind, and the retry has to
// succeed over it rather than fail on its ids (#2517).
func MigrateVault(ctx context.Context, source, target *db.DatabaseSqlc) error {
	srcDB := source.Db
	dstDB := target.Db

	tx, err := dstDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin target tx: %w", err)
	}
	defer tx.Rollback()

	if err := clearVaultTables(ctx, tx); err != nil {
		return err
	}
	if err := copyVaultConfig(ctx, srcDB, tx); err != nil {
		return err
	}
	if err := copyVaultFolders(ctx, srcDB, tx); err != nil {
		return err
	}
	if err := copyVaultEntries(ctx, srcDB, tx); err != nil {
		return err
	}

	return tx.Commit()
}

// TruncateVaultTables empties the vault in d in one transaction, so it is
// either all there or all gone.
func TruncateVaultTables(ctx context.Context, d *db.DatabaseSqlc) error {
	tx, err := d.Db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin truncate tx: %w", err)
	}
	defer tx.Rollback()

	if err := clearVaultTables(ctx, tx); err != nil {
		return err
	}
	return tx.Commit()
}

// clearVaultTables deletes every vault row inside tx, children before the
// config they hang off.
func clearVaultTables(ctx context.Context, tx *sql.Tx) error {
	for _, table := range []string{"vault_entries", "vault_folders", "vault_config"} {
		if _, err := tx.ExecContext(ctx, "DELETE FROM "+table); err != nil {
			return fmt.Errorf("truncate %s: %w", table, err)
		}
	}
	return nil
}

func copyVaultConfig(ctx context.Context, src *sql.DB, dst *sql.Tx) error {
	row := src.QueryRowContext(ctx,
		`SELECT id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
			verification_blob, verification_nonce, auto_lock_seconds, created_at
		FROM vault_config WHERE id = 1`)

	var id int64
	var salt, vBlob, vNonce []byte
	var argMem, argIter, argPar, autoLock int64
	var createdAt string
	if err := row.Scan(&id, &salt, &argMem, &argIter, &argPar, &vBlob, &vNonce, &autoLock, &createdAt); err != nil {
		if err == sql.ErrNoRows {
			return nil
		}
		return fmt.Errorf("read source vault_config: %w", err)
	}

	_, err := dst.ExecContext(ctx,
		`INSERT INTO vault_config (id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
			verification_blob, verification_nonce, auto_lock_seconds, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, salt, argMem, argIter, argPar, vBlob, vNonce, autoLock, createdAt)
	if err != nil {
		return fmt.Errorf("insert target vault_config: %w", err)
	}
	return nil
}

func copyVaultFolders(ctx context.Context, src *sql.DB, dst *sql.Tx) error {
	rows, err := src.QueryContext(ctx,
		`SELECT id, name, parent_id, sort_order, created_at FROM vault_folders ORDER BY id`)
	if err != nil {
		return fmt.Errorf("read source vault_folders: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id int64
		var name string
		var parentID sql.NullInt64
		var sortOrder int64
		var createdAt string
		if err := rows.Scan(&id, &name, &parentID, &sortOrder, &createdAt); err != nil {
			return fmt.Errorf("scan source folder: %w", err)
		}
		_, err := dst.ExecContext(ctx,
			`INSERT INTO vault_folders (id, name, parent_id, sort_order, created_at)
			VALUES (?, ?, ?, ?, ?)`,
			id, name, parentID, sortOrder, createdAt)
		if err != nil {
			return fmt.Errorf("insert target folder %d: %w", id, err)
		}
	}
	return rows.Err()
}

func copyVaultEntries(ctx context.Context, src *sql.DB, dst *sql.Tx) error {
	rows, err := src.QueryContext(ctx,
		`SELECT id, name, url_host, folder_id, ciphertext, nonce, created_at, updated_at
		FROM vault_entries ORDER BY id`)
	if err != nil {
		return fmt.Errorf("read source vault_entries: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id int64
		var name, urlHost string
		var folderID sql.NullInt64
		var ct, nonce []byte
		var createdAt, updatedAt string
		if err := rows.Scan(&id, &name, &urlHost, &folderID, &ct, &nonce, &createdAt, &updatedAt); err != nil {
			return fmt.Errorf("scan source entry: %w", err)
		}
		_, err := dst.ExecContext(ctx,
			`INSERT INTO vault_entries (id, name, url_host, folder_id, ciphertext, nonce, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			id, name, urlHost, folderID, ct, nonce, createdAt, updatedAt)
		if err != nil {
			return fmt.Errorf("insert target entry %d: %w", id, err)
		}
	}
	return rows.Err()
}

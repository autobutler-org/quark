package backup

import (
	"context"
	"crypto/rand"
	"database/sql"
	"database/sql/driver"
	"fmt"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	// Registers the "sqlite" driver with database/sql.
	_ "modernc.org/sqlite"
)

const backupChatFilename = "chat_backup.db"

// chatBackupTables is every chat table, parents before children: the order a
// restore has to load them in for the live foreign keys to hold.
// chat_read_markers (#2424) is left out on purpose: it is only how far each
// account has read, so a restored Quark starts with everything unread.
var chatBackupTables = []string{
	"chat_servers",
	"chat_channels",
	"chat_channel_members",
	"user_chat_keys",
	"chat_channel_keys",
	"chat_key_grants",
	"chat_channel_events",
	"chat_messages",
	"chat_reactions",
}

// ExportChat writes the chat tables of liveDB to chat_backup.db in targetDir
// and returns its path (#2428). Unlike the vault export it asks for no
// password: message bodies, reactions and channel keys are ciphertext the
// Quark cannot open, and the rest is public keys, so the copy is as private as
// the database it came from.
//
// The file is built under a temp name of its own and renamed into place, so a
// failed export leaves the previous backup whole and two exports never share a
// temp (#3084).
func ExportChat(ctx context.Context, liveDB *sql.DB, targetDir string) (string, error) {
	dbPath := filepath.Join(targetDir, backupChatFilename)
	tmpPath := filepath.Join(targetDir, storageutil.WriteTempPrefix+rand.Text()+"-"+backupChatFilename)

	// A no-op once the rename has happened; cleans up after any failure before it.
	defer os.Remove(tmpPath)
	defer os.Remove(tmpPath + "-journal")

	if err := createChatBackupFile(tmpPath); err != nil {
		return "", fmt.Errorf("create chat backup schema: %w", err)
	}
	if err := copyChatTables(ctx, liveDB, tmpPath); err != nil {
		return "", err
	}

	if err := storageutil.SyncFile(tmpPath); err != nil {
		return "", fmt.Errorf("flush chat backup: %w", err)
	}
	if err := os.Rename(tmpPath, dbPath); err != nil {
		return "", fmt.Errorf("replace chat backup: %w", err)
	}
	if err := storageutil.SyncDir(targetDir); err != nil {
		return "", fmt.Errorf("flush chat backup directory: %w", err)
	}
	return dbPath, nil
}

func createChatBackupFile(path string) error {
	backupDB, err := sql.Open("sqlite", db.DSN(path))
	if err != nil {
		return err
	}
	if err := db.InitChatBackupSchema(backupDB); err != nil {
		backupDB.Close()
		return err
	}
	return backupDB.Close()
}

// copyChatTables fills the backup file at backupPath from liveDB.
//
// Raw SQL rather than sqlc, under the same exception as vault_export.go: each
// statement spans the live database and an attached one outside the migration
// set, which sqlc has no schema for and cannot type-check. Attaching is what
// keeps the copy inside SQLite. Chat history has no upper bound, and a listing
// query would lift every message onto the Go heap to write it back out.
//
// One transaction covers every table, so the file is a single moment of the
// chat: no message naming a key version the copy missed.
// ponytail: that read lock holds a writer's COMMIT back until the copy ends
// (the database is not in WAL mode), and a writer gives up after
// busy_timeout's five seconds. Copy in id ranges if a history ever takes
// longer than that to write.
func copyChatTables(ctx context.Context, liveDB *sql.DB, backupPath string) error {
	conn, err := attachChatBackup(ctx, liveDB, backupPath)
	if err != nil {
		return err
	}
	defer discardChatConn(conn)

	tx, err := conn.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin chat export: %w", err)
	}
	defer tx.Rollback()

	// The directory a restore matches accounts through: names, never hashes.
	statements := []string{
		`INSERT INTO chat_backup.users (id, username) SELECT id, username FROM main.users`,
		`INSERT INTO chat_backup.groups (id, name) SELECT id, name FROM main.groups`,
	}
	for _, table := range chatBackupTables {
		// SELECT * is safe because the backup schema carries the live columns
		// in the live order, which TestChatBackupSchema_MatchesLiveTables pins.
		statements = append(statements, "INSERT INTO chat_backup."+table+" SELECT * FROM main."+table)
	}
	for _, statement := range statements {
		if _, err := tx.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("export chat (%s): %w", statement, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit chat export: %w", err)
	}
	return nil
}

// attachChatBackup takes a connection of its own out of liveDB and attaches
// the backup file at path (or file: URI) to it as chat_backup. ATTACH belongs
// to one connection, so everything that reads or writes the backup has to run
// on the connection returned, and the caller ends with [discardChatConn].
func attachChatBackup(ctx context.Context, liveDB *sql.DB, path string) (*sql.Conn, error) {
	conn, err := liveDB.Conn(ctx)
	if err != nil {
		return nil, fmt.Errorf("take chat backup connection: %w", err)
	}
	if _, err := conn.ExecContext(ctx, `ATTACH DATABASE ? AS chat_backup`, path); err != nil {
		discardChatConn(conn)
		return nil, fmt.Errorf("attach chat backup: %w", err)
	}
	return conn, nil
}

// discardChatConn closes conn for good instead of handing it back to the pool.
// A connection returned still attached, or with a transaction a failure left
// open, would be given to the next request as it is; closing it detaches the
// file and rolls back whatever was not committed, whichever path led here.
func discardChatConn(conn *sql.Conn) {
	// database/sql throws away a connection whose Raw callback reports it bad.
	_ = conn.Raw(func(any) error { return driver.ErrBadConn })
}

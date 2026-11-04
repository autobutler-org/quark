package backup

import (
	"context"
	"crypto/rand"
	"database/sql"
	"database/sql/driver"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	// Registers the "sqlite" driver with database/sql.
	_ "modernc.org/sqlite"
)

// ciphertextBackup is one SQLite file a snapshot writes beside the files: a
// copy of live tables whose secrets are ciphertext the Quark cannot open, so
// it asks for no password and is as private as the database it came from.
// The chat (#2428) and the vault (#3460) are the two.
type ciphertextBackup struct {
	// filename is the file's name in the backup directory. Without ".db" it is
	// also the name the file is attached under, which directory and steps
	// spell out.
	filename string
	// feature names the backup in the refusal a PostgreSQL-backed Quark is
	// answered with.
	feature string
	// ddl creates the file's schema and sets its user_version to version.
	ddl     string
	version int
	// errVersion is what a restore answers a file of another version with.
	errVersion error
	// directory copies the names behind every account (or group) id the rows
	// mention, never a hash, so a restore can find the same account on a
	// Quark that numbered its accounts differently.
	directory []string
	// tables are copied whole, parents before children. SELECT * is safe
	// because the backup schema carries the live columns in the live order,
	// which a schema test per backup pins.
	tables []string
	// occupied answers whether the live tables hold something a restore must
	// not overwrite, and errOccupied is the refusal then. A restore replaces;
	// it never merges.
	occupied    string
	errOccupied error
	// check, when set, runs on the restore's connection once
	// temp.restore_users, the map from backup account ids to live ones, is
	// made and before the first step. An error refuses the restore, before
	// any row is written.
	check func(ctx context.Context, conn *sql.Conn) error
	// steps restore the rows, in the order the live foreign keys need.
	steps []restoreStep
	// settle, when set, runs on the restore's connection after the last step,
	// before the commit. An error refuses the restore and rolls it back; what
	// it returns comes back as the restore's report.
	settle func(ctx context.Context, conn *sql.Conn) (restoreReport, error)
}

// restoreReport is what a backup's settle reports about a restore.
type restoreReport struct {
	// named is the usernames the backup calls out to the caller.
	named []string
	// restored is the live accounts that got rows back.
	restored []restoredAccount
}

// restoredAccount is one live account a restore wrote rows for.
type restoredAccount struct {
	userID   int64
	username string
}

// restoreStep is one statement of a restore. name keys the rows it changed in
// [ciphertextBackup.restore]'s result.
type restoreStep struct{ name, statement string }

// ciphertextBackups is every ciphertext backup a snapshot writes.
var ciphertextBackups = []ciphertextBackup{chatBackup, vaultBackup}

// schema is the name the backup file is attached under.
func (b ciphertextBackup) schema() string {
	return strings.TrimSuffix(b.filename, ".db")
}

// ErrDatabaseBackedUpSeparately is what the chat and vault backups answer on
// a PostgreSQL-backed Quark. There the chat and the vault are rows in the
// operator's database, and the operator's PostgreSQL backups (pg_dump, a
// managed service's snapshots) carry them; a SQLite copy beside the files
// would be a second, older copy nobody restores from (#2963).
var ErrDatabaseBackedUpSeparately = errors.New(
	"on PostgreSQL the chat and the vault are backed up with the database, by the operator's PostgreSQL backups, not by Quark")

// require turns away a live database the backup cannot attach a file to. The
// copy is SQLite's ATTACH DATABASE on the live connection. This check stands
// in for db.RequireSQLite in front of that SQLite-only SQL: on PostgreSQL the
// refusal is by design, not a feature still to come.
func (b ciphertextBackup) require(liveDB *sql.DB) error {
	if db.BackendOf(liveDB) == db.Postgres {
		return fmt.Errorf("%s: %w", b.feature, ErrDatabaseBackedUpSeparately)
	}
	return nil
}

// export writes the backup of liveDB into targetDir and returns its path.
//
// The file is built under a temp name of its own and renamed into place, so a
// failed export leaves the previous backup whole and two exports never share a
// temp (#3084).
func (b ciphertextBackup) export(ctx context.Context, liveDB *sql.DB, targetDir string) (string, error) {
	if err := b.require(liveDB); err != nil {
		return "", err
	}
	dbPath := filepath.Join(targetDir, b.filename)
	tmpPath := filepath.Join(targetDir, storageutil.WriteTempPrefix+rand.Text()+"-"+b.filename)

	// A no-op once the rename has happened; cleans up after any failure before it.
	defer os.Remove(tmpPath)
	defer os.Remove(tmpPath + "-journal")

	if err := b.createFile(tmpPath); err != nil {
		return "", fmt.Errorf("create %s schema: %w", b.filename, err)
	}
	if err := b.copyTables(ctx, liveDB, tmpPath); err != nil {
		return "", err
	}

	if err := storageutil.SyncFile(tmpPath); err != nil {
		return "", fmt.Errorf("flush %s: %w", b.filename, err)
	}
	if err := os.Rename(tmpPath, dbPath); err != nil {
		return "", fmt.Errorf("replace %s: %w", b.filename, err)
	}
	if err := storageutil.SyncDir(targetDir); err != nil {
		return "", fmt.Errorf("flush %s directory: %w", b.filename, err)
	}
	return dbPath, nil
}

func (b ciphertextBackup) createFile(path string) error {
	backupDB, err := sql.Open("sqlite", db.DSN(path))
	if err != nil {
		return err
	}
	if _, err := backupDB.Exec(b.ddl); err != nil {
		backupDB.Close()
		return err
	}
	return backupDB.Close()
}

// copyTables fills the backup file at backupPath from liveDB.
//
// Raw SQL rather than sqlc: each statement spans the live database and an
// attached one outside the migration set, which sqlc has no schema for and
// cannot type-check. Attaching is what keeps the copy inside SQLite. Chat
// history and vaults have no upper bound, and a listing query would lift every
// row onto the Go heap to write it back out.
//
// One transaction covers every table, so the file is a single moment: no
// message naming a key version the copy missed, no item without its key.
// ponytail: that read lock holds a writer's COMMIT back until the copy ends
// (the database is not in WAL mode), and a writer gives up after
// busy_timeout's five seconds. Copy in id ranges if a history ever takes
// longer than that to write.
func (b ciphertextBackup) copyTables(ctx context.Context, liveDB *sql.DB, backupPath string) error {
	conn, err := b.attach(ctx, liveDB, backupPath)
	if err != nil {
		return err
	}
	defer discardConn(conn)

	tx, err := conn.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin %s export: %w", b.filename, err)
	}
	defer tx.Rollback()

	statements := append([]string{}, b.directory...)
	for _, table := range b.tables {
		statements = append(statements, "INSERT INTO "+b.schema()+"."+table+" SELECT * FROM main."+table)
	}
	for _, statement := range statements {
		if _, err := tx.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("export %s (%s): %w", b.filename, statement, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit %s export: %w", b.filename, err)
	}
	return nil
}

// restore loads the backup in backupDir into liveDB, in one transaction: a
// refused or failed restore changes nothing. It returns the rows each step
// changed, by step name, the backup's usernames that have no account here, and
// what settle reported.
//
// The backup does not carry accounts, so every account a row names is looked
// up by username on this Quark through temp.restore_users. A step treats an
// account that is not here as the live schema treats a deleted one.
func (b ciphertextBackup) restore(ctx context.Context, liveDB *sql.DB, backupDir string) (map[string]int64, []string, restoreReport, error) {
	if err := b.require(liveDB); err != nil {
		return nil, nil, restoreReport{}, err
	}
	dbPath, err := filepath.Abs(filepath.Join(backupDir, b.filename))
	if err != nil {
		return nil, nil, restoreReport{}, err
	}
	// ATTACH would otherwise answer a missing file with a less helpful error.
	// Only the cause goes out, never the *fs.PathError around it: its path is
	// where the drive is mounted on the host, and that is no client's business.
	if _, err := os.Stat(dbPath); err != nil {
		if pathErr, ok := errors.AsType[*fs.PathError](err); ok {
			err = pathErr.Err
		}
		if errors.Is(err, fs.ErrNotExist) {
			return nil, nil, restoreReport{}, fmt.Errorf("%s not found on device: %w", b.filename, fs.ErrNotExist)
		}
		return nil, nil, restoreReport{}, fmt.Errorf("read %s on device: %w", b.filename, err)
	}

	// Read-only, so a restore can never change the file the manifest hashed.
	backupURI := url.URL{Scheme: "file", Path: dbPath, RawQuery: "mode=ro"}
	conn, err := b.attach(ctx, liveDB, backupURI.String())
	if err != nil {
		return nil, nil, restoreReport{}, err
	}
	// Also what rolls the transaction below back on every early return.
	defer discardConn(conn)

	var version int
	if err := conn.QueryRowContext(ctx, `PRAGMA `+b.schema()+`.user_version`).Scan(&version); err != nil {
		return nil, nil, restoreReport{}, fmt.Errorf("read %s version: %w", b.filename, err)
	}
	if version != b.version {
		return nil, nil, restoreReport{}, fmt.Errorf("%w: the file is format %d, this Quark reads format %d",
			b.errVersion, version, b.version)
	}

	// IMMEDIATE takes the write lock before the emptiness check, so nobody
	// writes between the check and the delete that follows it.
	// database/sql can only begin a deferred transaction, hence the Exec.
	if _, err := conn.ExecContext(ctx, `BEGIN IMMEDIATE`); err != nil {
		return nil, nil, restoreReport{}, fmt.Errorf("begin %s restore: %w", b.filename, err)
	}

	var occupied bool
	if err := conn.QueryRowContext(ctx, b.occupied).Scan(&occupied); err != nil {
		return nil, nil, restoreReport{}, fmt.Errorf("check live tables for %s: %w", b.filename, err)
	}
	if occupied {
		return nil, nil, restoreReport{}, b.errOccupied
	}

	if _, err := conn.ExecContext(ctx, `
		CREATE TEMP TABLE restore_users AS
		SELECT b.id AS backup_id, l.id AS live_id
		FROM `+b.schema()+`.users AS b JOIN main.users AS l ON l.username = b.username`); err != nil {
		return nil, nil, restoreReport{}, fmt.Errorf("restore %s (map users): %w", b.filename, err)
	}
	if b.check != nil {
		if err := b.check(ctx, conn); err != nil {
			return nil, nil, restoreReport{}, err
		}
	}

	rows := make(map[string]int64, len(b.steps))
	for _, step := range b.steps {
		res, err := conn.ExecContext(ctx, step.statement)
		if err != nil {
			return nil, nil, restoreReport{}, fmt.Errorf("restore %s (%s): %w", b.filename, step.name, err)
		}
		// modernc's RowsAffected never fails.
		rows[step.name], _ = res.RowsAffected()
	}

	unmatched, err := b.unmatchedUsers(ctx, conn)
	if err != nil {
		return nil, nil, restoreReport{}, err
	}
	var report restoreReport
	if b.settle != nil {
		if report, err = b.settle(ctx, conn); err != nil {
			return nil, nil, restoreReport{}, err
		}
	}

	if _, err := conn.ExecContext(ctx, `COMMIT`); err != nil {
		return nil, nil, restoreReport{}, fmt.Errorf("commit %s restore: %w", b.filename, err)
	}
	return rows, unmatched, report, nil
}

// unmatchedUsers lists the backup's accounts that have no account of the same
// username on this Quark. A handful of names, so reading them is fine.
func (b ciphertextBackup) unmatchedUsers(ctx context.Context, conn *sql.Conn) ([]string, error) {
	usernames, err := queryStrings(ctx, conn, `
		SELECT username FROM `+b.schema()+`.users
		WHERE id NOT IN (SELECT backup_id FROM temp.restore_users)
		ORDER BY username`)
	if err != nil {
		return nil, fmt.Errorf("list unmatched accounts in %s: %w", b.filename, err)
	}
	return usernames, nil
}

// queryStrings reads the one text column query returns, row by row. It is for
// short lists, usernames, not for anything a user can make long.
func queryStrings(ctx context.Context, conn *sql.Conn, query string) ([]string, error) {
	rows, err := conn.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var values []string
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			return nil, err
		}
		values = append(values, value)
	}
	return values, rows.Err()
}

// attach takes a connection of its own out of liveDB and attaches the backup
// file at path (or file: URI) to it under [ciphertextBackup.schema]. ATTACH
// belongs to one connection, so everything that reads or writes the backup
// has to run on the connection returned, and the caller ends with
// [discardConn].
func (b ciphertextBackup) attach(ctx context.Context, liveDB *sql.DB, path string) (*sql.Conn, error) {
	conn, err := liveDB.Conn(ctx)
	if err != nil {
		return nil, fmt.Errorf("take %s connection: %w", b.filename, err)
	}
	if _, err := conn.ExecContext(ctx, `ATTACH DATABASE ? AS `+b.schema(), path); err != nil {
		discardConn(conn)
		return nil, fmt.Errorf("attach %s: %w", b.filename, err)
	}
	return conn, nil
}

// discardConn closes conn for good instead of handing it back to the pool.
// A connection returned still attached, or with a transaction a failure left
// open, would be given to the next request as it is; closing it detaches the
// file and rolls back whatever was not committed, whichever path led here.
func discardConn(conn *sql.Conn) {
	// database/sql throws away a connection whose Raw callback reports it bad.
	_ = conn.Raw(func(any) error { return driver.ErrBadConn })
}

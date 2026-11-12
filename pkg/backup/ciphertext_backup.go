package backup

import (
	"context"
	"crypto/hkdf"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"database/sql/driver"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
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
	// errRole is what a restore from a drive without the snapshot-backup
	// role is answered with ([ciphertextBackup.fromDrive]).
	errRole error
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
//
// A key binds the file to this Quark: its MAC goes beside it, under
// [bindingSuffix], and [ciphertextBackup.checkBinding] reads it back (#4010).
// With no key the file is unbound and any binding an earlier export left is
// removed, so it cannot refuse the new file.
func (b ciphertextBackup) export(ctx context.Context, liveDB *sql.DB, targetDir string, key []byte) (string, error) {
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
	// ponytail: the binding lands before the file it binds, so a power cut
	// between the two renames leaves the old file beside the new MAC, which a
	// restore refuses until the next snapshot. Fail closed; carry the MAC
	// inside the file if that window ever matters.
	if err := b.writeBinding(key, tmpPath, targetDir); err != nil {
		return "", err
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

// bindingSuffix follows a ciphertext backup's file name to name the file
// holding its MAC, the hex of HMAC-SHA256 under [bindingKey] over the file
// name, a NUL, and the file's bytes. The MAC is what binds the file to the
// Quark that wrote it (#4010).
const bindingSuffix = ".mac"

// boundDriveKeyPrefix starts the settings key recording that this Quark binds
// the chat and vault files it writes to a drive: backupBound:<serial>. Without
// the record, a bound file whose MAC was deleted would pass for one written
// before binding.
const boundDriveKeyPrefix = "backupBound:"

// bindingKeyInfo separates the binding key from every other use of the salt
// secret. HKDF, not HMAC(secret, label): /auth/salt answers HMAC(secret,
// username) for any username, so a label there could be asked for.
const bindingKeyInfo = "quark snapshot backup binding v1"

// bindingKey is the key this Quark MACs its chat and vault backups with,
// derived from the install's salt secret in queries. The secret lives in the
// settings table, which no snapshot copies, so a drive's contents cannot
// produce it.
func bindingKey(ctx context.Context, queries db.Querier) ([]byte, error) {
	secret, err := settingsutil.AuthSaltSecretIn(ctx, queries)
	if err != nil {
		return nil, fmt.Errorf("read the backup binding key: %w", err)
	}
	return hkdf.Key(sha256.New, secret, nil, bindingKeyInfo, sha256.Size)
}

// markDriveBound records that this Quark binds what it writes to the drive
// serial. It is written before the first bound file, so a failure afterwards
// leaves the drive refusing unbound files rather than accepting them.
func markDriveBound(ctx context.Context, queries db.Querier, serial string) error {
	if err := queries.SetSetting(ctx, db.SetSettingParams{Key: boundDriveKeyPrefix + serial, Value: "true"}); err != nil {
		return fmt.Errorf("record the backup binding for the drive: %w", err)
	}
	return nil
}

// fileMAC is the binding MAC of the file at path, read as a stream.
func (b ciphertextBackup) fileMAC(key []byte, path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(b.filename + "\x00"))
	if _, err := io.Copy(mac, f); err != nil {
		return nil, err
	}
	return mac.Sum(nil), nil
}

// writeBinding puts the MAC of the file at filePath, under key, in targetDir,
// through a temp name and a rename. A nil key removes the binding instead.
func (b ciphertextBackup) writeBinding(key []byte, filePath, targetDir string) error {
	macPath := filepath.Join(targetDir, b.filename+bindingSuffix)
	if key == nil {
		if err := os.Remove(macPath); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return fmt.Errorf("remove the old %s binding: %w", b.filename, err)
		}
		return nil
	}
	sum, err := b.fileMAC(key, filePath)
	if err != nil {
		return fmt.Errorf("bind %s: %w", b.filename, err)
	}
	tmpPath := filepath.Join(targetDir, storageutil.WriteTempPrefix+rand.Text()+"-"+b.filename+bindingSuffix)
	defer os.Remove(tmpPath)
	if err := os.WriteFile(tmpPath, []byte(hex.EncodeToString(sum)), 0o600); err != nil {
		return fmt.Errorf("bind %s: %w", b.filename, err)
	}
	if err := storageutil.SyncFile(tmpPath); err != nil {
		return fmt.Errorf("flush the %s binding: %w", b.filename, err)
	}
	if err := os.Rename(tmpPath, macPath); err != nil {
		return fmt.Errorf("replace the %s binding: %w", b.filename, err)
	}
	return nil
}

// ErrBackupNotFromThisQuark reports a chat or vault backup file this Quark did
// not write, or one changed since (#4010). Its error says which, and that
// nothing was restored.
var ErrBackupNotFromThisQuark = errors.New("this Quark did not write this backup file, so nothing was restored")

// checkBinding refuses the backup in backupDir, on the drive serial, unless
// this Quark wrote it. A file with a binding must match it under this
// Quark's key. A file without one restores only from a drive this Quark has
// never bound a snapshot to: that is a snapshot taken before binding, and the
// drives already on the shelf keep working. A missing file is left to the
// restore, which names it.
func (b ciphertextBackup) checkBinding(ctx context.Context, queries db.Querier, serial, backupDir string) error {
	dbPath := filepath.Join(backupDir, b.filename)
	if _, err := os.Stat(dbPath); errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	// Bounded: a MAC is 64 hex characters, and the drive is not trusted.
	want, err := readBinding(filepath.Join(backupDir, b.filename+bindingSuffix))
	if errors.Is(err, fs.ErrNotExist) {
		_, err := queries.GetSetting(ctx, boundDriveKeyPrefix+serial)
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("read the drive's backup binding record: %w", err)
		}
		return fmt.Errorf("%w: %s has no binding, but this Quark binds every snapshot it writes to this drive",
			ErrBackupNotFromThisQuark, b.filename)
	}
	if err != nil {
		return fmt.Errorf("read the %s binding on device: %w", b.filename, err)
	}
	key, err := bindingKey(ctx, queries)
	if err != nil {
		return err
	}
	got, err := b.fileMAC(key, dbPath)
	if err != nil {
		return fmt.Errorf("check the %s binding on device: %w", b.filename, err)
	}
	if !hmac.Equal(got, want) {
		return fmt.Errorf("%w: %s was written by another Quark, or changed after the snapshot wrote it",
			ErrBackupNotFromThisQuark, b.filename)
	}
	return nil
}

// fromDrive finds the run a restore of b reads from, on the drive
// params.DeviceSerial names: the run params.Run names, or the newest complete
// one. It answers the run and the host folder b's file is in, once the drive
// has the snapshot-backup role and the file passes [ciphertextBackup.checkBinding].
//
// A drive that is not attached is a *fileutil.NotFoundError, one without the
// role b.errRole, one with no complete run [ErrNoSnapshot], and a run it does
// not hold [ErrRunNotFound]. A restore reads only the drive snapshots are
// written to, never whatever drive holds a file of the right name.
func (b ciphertextBackup) fromDrive(params RestoreVaultParams) (Run, string, error) {
	drive, err := fileutil.FilesVFS(params.Registry, params.DeviceSerial)
	if err != nil {
		return Run{}, "", err
	}
	role, err := params.Queries.GetDeviceRole(params.Ctx, params.DeviceSerial)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && role != "snapshot-backup") {
		return Run{}, "", b.errRole
	}
	if err != nil {
		return Run{}, "", fmt.Errorf("read the drive's role: %w", err)
	}
	run, err := resolveRun(params.Ctx, drive, params.Run)
	if err != nil {
		return Run{}, "", err
	}
	dir, err := hostDir(params.Ctx, drive, runDir(run.Folder))
	if err != nil {
		return Run{}, "", err
	}
	if err := b.checkBinding(params.Ctx, params.Queries, params.DeviceSerial, dir); err != nil {
		return Run{}, "", err
	}
	return run, dir, nil
}

// readBinding reads the MAC at path. Anything that is not one decodes to a
// MAC no file matches.
func readBinding(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		if pathErr, ok := errors.AsType[*fs.PathError](err); ok {
			err = pathErr.Err
		}
		return nil, err
	}
	defer f.Close()
	encoded, err := io.ReadAll(io.LimitReader(f, 2*sha256.Size+1))
	if err != nil {
		return nil, err
	}
	sum, _ := hex.DecodeString(string(encoded))
	return sum, nil
}

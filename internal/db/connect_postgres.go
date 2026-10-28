package db

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net"
	"strconv"
	"time"

	"github.com/golang-migrate/migrate/v4"
	migratepgx "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/stdlib"
)

//go:embed migrations_postgres
var postgresMigrations embed.FS

const (
	// postgresMaxOpenConns is the same bound as SQLite's maxOpenConns, for the
	// same reason: it is how many requests may be in the database at once, and
	// the device or container serving them has a handful of cores. On
	// PostgreSQL it is also a share of the server's max_connections, which
	// defaults to 100 and is lower on a small managed instance, so the pool
	// stays well under it and leaves room for an operator's psql and backups.
	postgresMaxOpenConns = 16
	// postgresConnMaxIdleTime gives a connection nobody has used back to the
	// server. Unlike a SQLite connection, an idle one costs a backend process
	// on someone else's machine. Under load nothing sits idle this long, so
	// this never makes a busy server reconnect.
	postgresConnMaxIdleTime = 5 * time.Minute
	// postgresConnMaxLifetime retires every connection eventually, so that a
	// failover or a moved DNS name is picked up without a restart, and stays
	// under the idle cutoffs of the load balancers managed services sit behind.
	postgresConnMaxLifetime = 30 * time.Minute
	// postgresPingTimeout bounds the wait for the first answer at startup. A
	// database on the same network answers in milliseconds; one that has not
	// answered by now is down or misaddressed, and the server should say so
	// rather than hang.
	postgresPingTimeout = 10 * time.Second
	// postgresMinVersionNum is the oldest server_version_num Quark starts on:
	// PostgreSQL 14. pgx supports the versions the PostgreSQL project still
	// supports, and 13 is past its end of life. CI tests 18.
	postgresMinVersionNum = 140000
)

// ConnectToPostgres opens the PostgreSQL database at url, brings its schema up
// to this build's migrations, and returns it ready to serve.
//
// It never repairs or resets what it finds. A database that does not answer,
// or whose schema this build cannot carry forward, is an error that says what
// was found and what to do, and the database is left as it was.
func ConnectToPostgres(url string) (*DatabaseSqlc, error) {
	config, err := pgx.ParseConfig(url)
	if err != nil {
		// pgx blanks the password in what it quotes back.
		return nil, fmt.Errorf("%s is not a PostgreSQL connection URL: %w", DatabaseURLEnv, err)
	}
	// The session time zone decides how PostgreSQL renders a TIMESTAMPTZ as
	// text and where date arithmetic puts midnight. Pinned to UTC, as the
	// SQLite DSN pins _timezone=UTC, so neither depends on the server's or the
	// role's default.
	config.RuntimeParams["timezone"] = "UTC"

	if err := migratePostgres(*config); err != nil {
		return nil, err
	}

	sqlDB := openPostgresPool(*config)
	sqlDB.SetMaxOpenConns(postgresMaxOpenConns)
	// Idle connections are kept up to the bound, as on SQLite: the default of
	// two would reconnect, and authenticate again, on most requests under load.
	sqlDB.SetMaxIdleConns(postgresMaxOpenConns)
	sqlDB.SetConnMaxIdleTime(postgresConnMaxIdleTime)
	sqlDB.SetConnMaxLifetime(postgresConnMaxLifetime)
	// Host, database and user only: the URL carries the password.
	slog.Info("using the PostgreSQL backend",
		"address", net.JoinHostPort(config.Host, strconv.Itoa(int(config.Port))),
		"database", config.Database, "user", config.User)
	return &DatabaseSqlc{Db: sqlDB, Queries: NewQueries(sqlDB)}, nil
}

// openPostgresPool returns a pool on config whose connections hand back every
// TIMESTAMPTZ in UTC. The driver would otherwise return them in the process's
// local zone, where SQLite's come back in UTC: the same instant, but anything
// that formats one without converting first would differ between the engines.
func openPostgresPool(config pgx.ConnConfig) *sql.DB {
	return stdlib.OpenDB(config, stdlib.OptionAfterConnect(func(_ context.Context, conn *pgx.Conn) error {
		conn.TypeMap().RegisterType(&pgtype.Type{
			Name:  "timestamptz",
			OID:   pgtype.TimestamptzOID,
			Codec: &pgtype.TimestamptzCodec{ScanLocation: time.UTC},
		})
		return nil
	}))
}

// migratePostgres brings the database up to the embedded PostgreSQL migration
// set, on a pool of its own that it closes: golang-migrate's driver keeps a
// connection for its lifetime and closes the pool it was given.
//
// Two servers starting at once on one database are safe. The driver takes a
// session-level advisory lock (pg_advisory_lock, keyed on the database, schema
// and migrations table) before it creates schema_migrations and again around
// the run, so the second waits for the first, then finds the schema current
// and changes nothing. The checks for a dirty or unknown version happen inside
// golang-migrate's Up, under that lock.
func migratePostgres(config pgx.ConnConfig) (err error) {
	target := net.JoinHostPort(config.Host, strconv.Itoa(int(config.Port)))
	sqlDB := openPostgresPool(config)
	closed := false
	defer func() {
		if !closed {
			err = errors.Join(err, sqlDB.Close())
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), postgresPingTimeout)
	defer cancel()
	if err := sqlDB.PingContext(ctx); err != nil {
		return fmt.Errorf(
			"no PostgreSQL answers at %s for database %q as user %q (%w). Check %s, and that the database is "+
				"running and reachable from here; for local development, run `make serve/postgres`",
			target, config.Database, config.User, err, DatabaseURLEnv)
	}

	var versionNum int
	var fsync, synchronousCommit string
	if err := sqlDB.QueryRowContext(ctx, `
		SELECT current_setting('server_version_num')::int, current_setting('fsync'), current_setting('synchronous_commit')`,
	).Scan(&versionNum, &fsync, &synchronousCommit); err != nil {
		return fmt.Errorf("failed to read the settings of the PostgreSQL database at %s: %w", target, err)
	}
	if err := checkPostgresDurability(versionNum, fsync, synchronousCommit); err != nil {
		return fmt.Errorf("the PostgreSQL database %q at %s, as user %q: %w. Nothing was changed",
			config.Database, target, config.User, err)
	}

	// Looked for before golang-migrate is given the database, because it would
	// run the baseline into those tables, fail partway and leave its dirty
	// mark behind.
	var unmanaged bool
	if err := sqlDB.QueryRowContext(ctx, `
		SELECT to_regclass(quote_ident(current_schema()) || '.schema_migrations') IS NULL AND EXISTS (
			SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema())`,
	).Scan(&unmanaged); err != nil {
		return fmt.Errorf("failed to inspect the PostgreSQL database at %s: %w", target, err)
	}
	if unmanaged {
		return fmt.Errorf(
			"the PostgreSQL database %q at %s already has tables but no schema_migrations table, so it was not "+
				"made by Quark. Nothing was changed. Point %s at an empty database, or at an empty schema with "+
				"?search_path=<schema>",
			config.Database, target, DatabaseURLEnv)
	}

	source, err := iofs.New(postgresMigrations, "migrations_postgres")
	if err != nil {
		return fmt.Errorf("failed to open the embedded PostgreSQL migrations: %w", err)
	}
	driver, err := migratepgx.WithInstance(sqlDB, &migratepgx.Config{})
	if err != nil {
		return fmt.Errorf("failed to prepare the PostgreSQL database at %s for migrations: %w", target, err)
	}
	m, err := migrate.NewWithInstance("iofs", source, "pgx5", driver)
	if err != nil {
		return fmt.Errorf("failed to create the PostgreSQL migrate instance: %w", err)
	}
	// Closes the driver's connection and sqlDB with it.
	defer func() {
		closed = true
		sourceErr, databaseErr := m.Close()
		err = errors.Join(err, sourceErr, databaseErr)
	}()

	upErr := m.Up()
	var dirty migrate.ErrDirty
	switch {
	case upErr == nil, errors.Is(upErr, migrate.ErrNoChange):
		return nil
	case errors.As(upErr, &dirty):
		return fmt.Errorf(
			"the PostgreSQL database %q at %s is marked dirty at migration %d: an earlier start failed partway "+
				"through it. Nothing was changed, and Quark never resets a PostgreSQL database on its own. "+
				"Restore the database from a backup, or compare its schema with "+
				"internal/db/migrations_postgres, finish or undo migration %d by hand, and set "+
				"schema_migrations to the version that is fully applied with dirty = false",
			config.Database, target, dirty.Version, dirty.Version)
	case errors.Is(upErr, fs.ErrNotExist):
		version, _, _ := m.Version()
		return fmt.Errorf(
			"the PostgreSQL database %q at %s is at schema version %d, which this build of Quark does not "+
				"have: it was last opened by a different, probably newer, build. Nothing was changed. Start "+
				"the build that wrote it, or restore a backup taken before it ran",
			config.Database, target, version)
	case errors.Is(upErr, migrate.ErrLockTimeout):
		return fmt.Errorf(
			"timed out waiting for the migration lock on the PostgreSQL database %q at %s: another Quark is "+
				"migrating it, or a session that held the lock is stuck. Nothing was changed. Start again "+
				"once the other has finished: %w",
			config.Database, target, upErr)
	default:
		return fmt.Errorf(
			"failed to migrate the PostgreSQL database %q at %s. A migration that fails partway leaves the "+
				"database marked dirty, and Quark will not start on it until that is resolved: %w",
			config.Database, target, upErr)
	}
}

// checkPostgresDurability refuses a server Quark cannot keep its promises on
// (docs/architecture/durability.md): one older than PostgreSQL 14, or one
// that can lose an acknowledged commit. Any synchronous_commit but off (on,
// local, remote_write, remote_apply) flushes the local WAL before the commit
// returns, so each of those is accepted.
func checkPostgresDurability(versionNum int, fsync, synchronousCommit string) error {
	switch {
	case versionNum < postgresMinVersionNum:
		return fmt.Errorf("the server is PostgreSQL %d.%d, and Quark needs PostgreSQL 14 or newer. Upgrade the server",
			versionNum/10000, versionNum%10000)
	case fsync == "off":
		return errors.New("the server runs with fsync = off, so a power cut or an OS crash can corrupt the " +
			"database. Set fsync = on in postgresql.conf; on a managed service it is on unless someone turned it off")
	case synchronousCommit == "off":
		return errors.New("the session runs with synchronous_commit = off, so a crash can lose a write Quark " +
			"already acknowledged. Run `ALTER ROLE <user> SET synchronous_commit = on`, or set it in postgresql.conf")
	}
	return nil
}

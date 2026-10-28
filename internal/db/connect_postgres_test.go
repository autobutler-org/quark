package db_test

import (
	"context"
	"database/sql"
	"fmt"
	"net"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

func TestConfigFromEnv(t *testing.T) {
	const databaseURL = "postgres://quark:hunter2@db.example:5432/quark"
	for _, tc := range []struct {
		name, backend, url string
		want               db.Config
		// wantErr lists what the refusal has to say; empty means no error.
		wantErr []string
	}{
		{name: "unset is SQLite", want: db.Config{Backend: db.SQLite}},
		{name: "blank is SQLite", backend: "  ", want: db.Config{Backend: db.SQLite}},
		{name: "sqlite", backend: "sqlite", want: db.Config{Backend: db.SQLite}},
		{name: "sqlite ignores a URL", backend: "sqlite", url: databaseURL, want: db.Config{Backend: db.SQLite}},
		{name: "postgres", backend: "postgres", url: databaseURL, want: db.Config{Backend: db.Postgres, PostgresURL: databaseURL}},
		{name: "postgres without a URL", backend: "postgres", wantErr: []string{"QUARK_DB_BACKEND=postgres needs QUARK_DATABASE_URL", "postgres://"}},
		{name: "an unknown backend", backend: "mysql", url: databaseURL, wantErr: []string{`QUARK_DB_BACKEND="mysql"`, `"sqlite"`, `"postgres"`}},
		{name: "the name is case-sensitive", backend: "Postgres", url: databaseURL, wantErr: []string{`"sqlite"`, `"postgres"`}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv(db.BackendEnv, tc.backend)
			t.Setenv(db.DatabaseURLEnv, tc.url)
			got, err := db.ConfigFromEnv()
			if len(tc.wantErr) == 0 {
				if err != nil || got != tc.want {
					t.Fatalf("ConfigFromEnv() = %+v, %v, want %+v", got, err, tc.want)
				}
				return
			}
			if err == nil {
				t.Fatalf("ConfigFromEnv() = %+v, want a refusal", got)
			}
			for _, want := range tc.wantErr {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("ConfigFromEnv() error %q does not say %q", err, want)
				}
			}
			if strings.Contains(err.Error(), "hunter2") {
				t.Errorf("ConfigFromEnv() error %q carries the password", err)
			}
		})
	}
}

// connectToPostgres opens the schema at databaseURL through the startup path
// and closes it when the test ends.
func connectToPostgres(t *testing.T, databaseURL string) *db.DatabaseSqlc {
	t.Helper()
	database, err := db.ConnectToPostgres(databaseURL)
	if err != nil {
		t.Fatalf("ConnectToPostgres: %v", err)
	}
	t.Cleanup(func() { database.Db.Close() })
	return database
}

// rawPostgres is a plain connection to the schema at databaseURL, for putting
// it in a state before the startup path sees it and inspecting it after.
func rawPostgres(t *testing.T, databaseURL string) *sql.DB {
	t.Helper()
	conn, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

// An empty database comes up migrated, answers through db.Querier, and hands
// back timestamps in UTC as SQLite does. Opening it again changes nothing.
func TestConnectToPostgresMigratesAnEmptyDatabase(t *testing.T) {
	databaseURL := dbtest.PostgresURL(t)
	database := connectToPostgres(t, databaseURL)
	ctx := context.Background()

	if got := database.Backend(); got != db.Postgres {
		t.Errorf("Backend() = %q, want %q", got, db.Postgres)
	}
	if got := dbtest.NewDB(t).Backend(); got != db.SQLite {
		t.Errorf("a SQLite database's Backend() = %q, want %q", got, db.SQLite)
	}

	installID, err := database.Queries.GetInstallID(ctx)
	if err != nil || installID == "" {
		t.Fatalf("GetInstallID = %q, %v: the baseline seeds one", installID, err)
	}
	// The process's zone is moved off UTC, so a driver left returning local
	// times would show here.
	restore := time.Local
	time.Local = time.FixedZone("UTC+9", 9*60*60)
	t.Cleanup(func() { time.Local = restore })
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "ada"})
	if err != nil {
		t.Fatal(err)
	}
	if user.CreatedAt.Location() != time.UTC {
		t.Errorf("created_at came back in %v, want UTC", user.CreatedAt.Location())
	}
	if age := time.Since(user.CreatedAt); age < -time.Minute || age > time.Minute {
		t.Errorf("created_at is %v from now", age)
	}
	var zone string
	if err := database.Db.QueryRow(`SHOW timezone`).Scan(&zone); err != nil || zone != "UTC" {
		t.Errorf("the session time zone is %q, %v, want UTC", zone, err)
	}

	again := connectToPostgres(t, databaseURL)
	if got, err := again.Queries.GetInstallID(ctx); err != nil || got != installID {
		t.Errorf("after a second start the install id is %q, %v, want %q: the schema was rebuilt", got, err, installID)
	}
	if _, err := again.Queries.GetUserByID(ctx, user.ID); err != nil {
		t.Errorf("after a second start the account is gone: %v", err)
	}
}

// Two servers starting at once on one empty database both come up, on one
// schema: golang-migrate's advisory lock makes the second wait for the first.
func TestConnectToPostgresTwiceAtOnce(t *testing.T) {
	databaseURL := dbtest.PostgresURL(t)
	const starts = 4
	errs := make([]error, starts)
	var wg sync.WaitGroup
	for i := range starts {
		wg.Go(func() {
			database, err := db.ConnectToPostgres(databaseURL)
			if err == nil {
				err = database.Db.Close()
			}
			errs[i] = err
		})
	}
	wg.Wait()
	for i, err := range errs {
		if err != nil {
			t.Errorf("start %d: %v", i, err)
		}
	}
	var version int
	var dirty bool
	if err := rawPostgres(t, databaseURL).QueryRow(`SELECT version, dirty FROM schema_migrations`).Scan(&version, &dirty); err != nil || dirty {
		t.Fatalf("schema_migrations = %d, dirty %v, %v", version, dirty, err)
	}
}

// What startup cannot carry forward it refuses, saying what it found, and
// leaves exactly as it was. There is no reset on PostgreSQL.
func TestConnectToPostgresRefusesWhatItCannotCarryForward(t *testing.T) {
	// state is what a refusal must not have changed: the recorded version
	// and every table.
	state := func(t *testing.T, conn *sql.DB) string {
		t.Helper()
		var tables, version sql.NullString
		if err := conn.QueryRow(`SELECT string_agg(table_name, ',' ORDER BY table_name)
			FROM information_schema.tables WHERE table_schema = current_schema()`).Scan(&tables); err != nil {
			t.Fatal(err)
		}
		if strings.Contains(tables.String, "schema_migrations") {
			if err := conn.QueryRow(`SELECT string_agg(version || ':' || dirty, ',') FROM schema_migrations`).Scan(&version); err != nil {
				t.Fatal(err)
			}
		}
		return tables.String + " @ " + version.String
	}

	for _, tc := range []struct {
		name string
		// arrange puts a migrated or an empty schema into the state under test.
		migrated bool
		arrange  string
		// wantDirtyVersion asks the refusal to name the version arrange left
		// dirty. That version is whatever the migrations applied, read back
		// rather than written here, so the next migration does not break the
		// test the way 033 did when this still said 32.
		wantDirtyVersion bool
		wantErr          []string
	}{
		{
			name: "a dirty flag", migrated: true,
			arrange:          `UPDATE schema_migrations SET dirty = true`,
			wantDirtyVersion: true,
			wantErr:          []string{"Nothing was changed", "never resets"},
		},
		{
			name: "a version this build does not have", migrated: true,
			arrange: `UPDATE schema_migrations SET version = 9999`,
			wantErr: []string{"schema version 9999", "does not", "Nothing was changed"},
		},
		{
			name:    "tables Quark did not make",
			arrange: `CREATE TABLE users (id BIGINT PRIMARY KEY, note TEXT); INSERT INTO users VALUES (1, 'not ours')`,
			wantErr: []string{"already has tables but no schema_migrations", "Nothing was changed", "empty"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			databaseURL := dbtest.PostgresURL(t)
			if tc.migrated {
				connectToPostgres(t, databaseURL)
			}
			conn := rawPostgres(t, databaseURL)
			if _, err := conn.Exec(tc.arrange); err != nil {
				t.Fatal(err)
			}
			before := state(t, conn)

			database, err := db.ConnectToPostgres(databaseURL)
			if err == nil {
				database.Db.Close()
				t.Fatal("ConnectToPostgres opened the database, want a refusal")
			}
			wants := tc.wantErr
			if tc.wantDirtyVersion {
				var version int
				if err := conn.QueryRow(`SELECT version FROM schema_migrations`).Scan(&version); err != nil {
					t.Fatal(err)
				}
				wants = append([]string{fmt.Sprintf("marked dirty at migration %d", version)}, tc.wantErr...)
			}
			for _, want := range wants {
				if !strings.Contains(err.Error(), want) {
					t.Errorf("the refusal %q does not say %q", err, want)
				}
			}
			if after := state(t, conn); after != before {
				t.Errorf("the refusal changed the database:\n before %s\n after  %s", before, after)
			}
		})
	}
}

// A session that would acknowledge a commit before its WAL is flushed is
// refused before anything is migrated. The setting rides on the URL, as a
// startup option of this connection only, so no other test's session sees it.
func TestConnectToPostgresRefusesSynchronousCommitOff(t *testing.T) {
	databaseURL, err := url.Parse(dbtest.PostgresURL(t))
	if err != nil {
		t.Fatal(err)
	}
	query := databaseURL.Query()
	query.Set("options", "-c synchronous_commit=off")
	databaseURL.RawQuery = query.Encode()

	database, err := db.ConnectToPostgres(databaseURL.String())
	if err == nil {
		database.Db.Close()
		t.Fatal("ConnectToPostgres opened the database, want a refusal")
	}
	for _, want := range []string{"synchronous_commit = off", "Nothing was changed"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("the refusal %q does not say %q", err, want)
		}
	}
	var tables int
	if err := rawPostgres(t, databaseURL.String()).QueryRow(
		`SELECT count(*) FROM information_schema.tables WHERE table_schema = current_schema()`).Scan(&tables); err != nil {
		t.Fatal(err)
	}
	if tables != 0 {
		t.Errorf("the refusal left %d tables behind", tables)
	}
}

// Nothing listening is an error that names the address and the fix, within
// the ping timeout, and never repeats the password.
func TestConnectToPostgresWithNothingListening(t *testing.T) {
	// A port that was just free: nothing answers there.
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	listener.Close()
	databaseURL := url.URL{Scheme: "postgres", User: url.UserPassword("quark", "hunter2"), Host: address, Path: "/quark", RawQuery: "sslmode=disable"}

	started := time.Now()
	database, err := db.ConnectToPostgres(databaseURL.String())
	if err == nil {
		database.Db.Close()
		t.Fatal("ConnectToPostgres succeeded with nothing listening")
	}
	if took := time.Since(started); took > 15*time.Second {
		t.Errorf("the refusal took %v", took)
	}
	for _, want := range []string{"no PostgreSQL answers at " + address, `database "quark"`, db.DatabaseURLEnv, "make serve/postgres"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("the refusal %q does not say %q", err, want)
		}
	}
	if strings.Contains(err.Error(), "hunter2") {
		t.Errorf("the refusal %q carries the password", err)
	}

	if _, err := db.ConnectToPostgres("postgres://quark:hunter2@[::1"); err == nil || strings.Contains(err.Error(), "hunter2") {
		t.Errorf("a URL that does not parse gave %v, want an error without the password", err)
	}
}

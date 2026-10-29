package server

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"regexp"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// What a transcript line must not carry for two runs to compare: a session
// token, the digest of one that names a session, and the instant a row was
// made.
var (
	transcriptToken   = regexp.MustCompile(`"token":"[^"]+"`)
	transcriptSession = regexp.MustCompile(`"id":"[0-9a-f]{64}"`)
	// Every timestamp the API returns is RFC 3339 in UTC, on both engines.
	// The fraction is PostgreSQL's: a TIMESTAMPTZ keeps microseconds where
	// SQLite's DATETIME text keeps whole seconds, and a handler that prints a
	// time at full precision shows them.
	transcriptTime = regexp.MustCompile(`"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z"`)
	// Any other spelling of a time is left in the transcript and reported: an
	// offset other than UTC, or the database's own format.
	transcriptOtherTime = regexp.MustCompile(`\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}`)
)

// serveFirstRun starts Quark on backend the way `quark serve` does, on an
// empty database and an empty data directory: db.ConfigFromEnv picks the
// engine, deputil.DefaultDependencies connects, migrates and builds the
// graph, and the real middleware and routers are mounted on a gin engine. It
// then drives a first-run journey over HTTP and returns one line per step:
// the status and the body, with tokens and timestamps blanked.
func serveFirstRun(t *testing.T, backend db.Backend, postgresURL string) map[string]string {
	t.Helper()
	// The data directory, and with it SQLite's quark.db and the files root,
	// hangs off HOME.
	t.Setenv("HOME", t.TempDir())
	t.Setenv(db.BackendEnv, string(backend))
	t.Setenv(db.DatabaseURLEnv, postgresURL)

	deps, err := deputil.DefaultDependencies()
	if err != nil {
		t.Fatalf("%s: DefaultDependencies: %v", backend, err)
	}
	t.Cleanup(func() {
		// Requests leave connected-device records running; they land before
		// the database closes (#2772).
		deps.Background().Wait()
		settingsutil.ResetForTesting("")
		deps.Database().Db.Close()
	})
	if got := deps.Database().Backend(); got != backend {
		t.Fatalf("the server opened %q, want %q", got, backend)
	}

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	middleware.Use(engine, deps)
	setupRouters(engine, nil, deps)

	transcript := map[string]string{}
	token := ""
	// do sends one request as the signed-in account, records it under step,
	// and returns the status and the decoded body.
	do := func(step, method, path string, body any) (int, map[string]any) {
		t.Helper()
		var encoded []byte
		if body != nil {
			if encoded, err = json.Marshal(body); err != nil {
				t.Fatal(err)
			}
		}
		req := httptest.NewRequest(method, path, bytes.NewReader(encoded))
		req.Header.Set("Content-Type", "application/json")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)

		line := transcriptToken.ReplaceAllString(w.Body.String(), `"token":"<token>"`)
		line = transcriptSession.ReplaceAllString(line, `"id":"<session>"`)
		line = transcriptTime.ReplaceAllString(line, `"<time>"`)
		if transcriptOtherTime.MatchString(line) {
			t.Errorf("%s: %s: a timestamp that is not RFC 3339 in UTC: %s", backend, step, line)
		}
		if _, repeated := transcript[step]; repeated {
			t.Fatalf("step %q is recorded twice", step)
		}
		transcript[step] = fmt.Sprintf("%d %s", w.Code, line)

		decoded := map[string]any{}
		// A list decodes into nothing here; the transcript carries it.
		_ = json.Unmarshal(w.Body.Bytes(), &decoded)
		return w.Code, decoded
	}
	// expect fails the test when a step did not answer want.
	expect := func(step string, got, want int) {
		t.Helper()
		if got != want {
			t.Fatalf("%s: %s answered %s, want status %d", backend, step, transcript[step], want)
		}
	}

	// First run: nobody has an account yet.
	code, _ := do("status before setup", http.MethodGet, "/api/v0/auth/status", nil)
	expect("status before setup", code, http.StatusOK)

	// The first account, made in one transaction with its admin flag, its
	// home folder and the grant on it.
	adminKey := dbtest.AuthKey("admin-password")
	code, body := do("setup", http.MethodPost, "/api/v0/auth/setup", map[string]string{"username": "ada", "authKey": adminKey})
	expect("setup", code, http.StatusOK)
	code, _ = do("setup again", http.MethodPost, "/api/v0/auth/setup", map[string]string{"username": "eve", "authKey": adminKey})
	if code < 400 {
		t.Fatalf("%s: a second setup answered %s", backend, transcript["setup again"])
	}
	do("status after setup", http.MethodGet, "/api/v0/auth/status", nil)

	// Read something back with the session setup issued. Listed while it is
	// the only one: sessions are ordered by when they were made, and two made
	// within a second tie on SQLite, which keeps whole seconds, and not on
	// PostgreSQL.
	token, _ = body["token"].(string)
	code, _ = do("sessions", http.MethodGet, "/api/v0/auth/sessions", nil)
	expect("sessions", code, http.StatusOK)
	token = ""

	// Sign in, and be turned away with the wrong key.
	code, _ = do("login with a wrong key", http.MethodPost, "/api/v0/auth/login", map[string]string{"username": "ada", "authKey": dbtest.AuthKey("wrong")})
	expect("login with a wrong key", code, http.StatusUnauthorized)
	code, body = do("login", http.MethodPost, "/api/v0/auth/login", map[string]string{"username": "ada", "authKey": adminKey})
	expect("login", code, http.StatusOK)
	adminToken, _ := body["token"].(string)
	if adminToken == "" {
		t.Fatalf("%s: login returned no token: %s", backend, transcript["login"])
	}
	token = adminToken

	// Read more back as that account.
	code, _ = do("my settings", http.MethodGet, "/api/v0/settings/me", nil)
	expect("my settings", code, http.StatusOK)
	code, _ = do("users", http.MethodGet, "/api/v0/admin/users", nil)
	expect("users", code, http.StatusOK)

	// Writes that go through a transaction, each followed by a list that has
	// to show it, and by the same write again, which hits a unique index.
	code, _ = do("create a user", http.MethodPost, "/api/v0/admin/users", map[string]string{"username": "grace", "authKey": dbtest.AuthKey("grace-password")})
	expect("create a user", code, http.StatusCreated)
	code, _ = do("create the same user", http.MethodPost, "/api/v0/admin/users", map[string]string{"username": "grace", "authKey": dbtest.AuthKey("other")})
	expect("create the same user", code, http.StatusConflict)
	// The refused insert rolled its transaction back and left the pool usable.
	do("users after", http.MethodGet, "/api/v0/admin/users", nil)

	code, _ = do("create a group", http.MethodPost, "/api/v0/admin/groups", map[string]string{"name": "family"})
	expect("create a group", code, http.StatusCreated)
	code, _ = do("create the same group", http.MethodPost, "/api/v0/admin/groups", map[string]string{"name": "Family"})
	expect("create the same group", code, http.StatusConflict)
	do("groups", http.MethodGet, "/api/v0/admin/groups", nil)

	// A unique violation outside a transaction, caught and answered. The
	// first list makes the account's Favorites album, ahead of the refused
	// insert: PostgreSQL's id sequence moves on even when an insert is
	// refused, where SQLite hands the id out again, so an album made after it
	// would get a different id on each.
	do("albums before", http.MethodGet, "/api/v0/albums", nil)
	code, _ = do("create an album", http.MethodPost, "/api/v0/albums", map[string]string{"name": "Summer"})
	expect("create an album", code, http.StatusCreated)
	code, _ = do("create the same album", http.MethodPost, "/api/v0/albums", map[string]string{"name": "summer"})
	expect("create the same album", code, http.StatusConflict)
	do("albums", http.MethodGet, "/api/v0/albums", nil)

	// A snapshot backup starts on either backend: on PostgreSQL it holds the
	// files only. No such device, so both get as far as saying so.
	code, _ = do("snapshot backup", http.MethodPost, "/api/v0/storage/devices/snapshot-backup", map[string]string{"targetDeviceSerial": "no-such-device"})
	expect("snapshot backup", code, http.StatusBadRequest)

	// Content search runs on both (#2958). Nothing is indexed, so both find
	// nothing.
	code, _ = do("content search", http.MethodGet, "/api/v0/files/search/content?q=anything", nil)
	expect("content search", code, http.StatusOK)

	// What PostgreSQL cannot do yet. SQLite answers; PostgreSQL says which
	// feature it is and where that is tracked, and stays up.
	for step, request := range unsupportedOnPostgres {
		do(step, request.method, request.path, request.body)
	}

	// The second account signs in too.
	token = ""
	code, body = do("login as the new user", http.MethodPost, "/api/v0/auth/login", map[string]string{"username": "grace", "authKey": dbtest.AuthKey("grace-password")})
	expect("login as the new user", code, http.StatusOK)
	token, _ = body["token"].(string)
	do("the new user is not an admin", http.MethodGet, "/api/v0/admin/users", nil)

	// The factory reset an admin asks for: the database goes back to first
	// run, on the pool the server already holds.
	token = adminToken
	code, _ = do("factory reset", http.MethodDelete, "/api/v0/auth/account?database=true", map[string]string{"password": adminKey})
	expect("factory reset", code, http.StatusOK)
	token = ""
	if _, err := deps.Database().Queries.GetUserByUsername(t.Context(), "ada"); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("%s: after the factory reset the first account is still there: %v", backend, err)
	}
	code, _ = do("login after the reset", http.MethodPost, "/api/v0/auth/login", map[string]string{"username": "ada", "authKey": adminKey})
	expect("login after the reset", code, http.StatusUnauthorized)

	return transcript
}

// unsupportedOnPostgres are the steps of the journey the two backends answer
// differently, by design: what SQLite answers, and the refusal PostgreSQL
// gives until the issue it names is done.
var unsupportedOnPostgres = map[string]struct {
	method, path string
	body         any
	sqlite       string
	postgres     string
}{}

// Quark starts and serves on an empty PostgreSQL database, and what it serves
// is what it serves on SQLite: the same first-run journey runs on both, and
// every step but those PostgreSQL does not support yet has to answer with
// the same status and the same body, ids included.
//
// Named for PostgreSQL because that is what selects it: `make test/db/postgres`
// and DB_BACKEND=postgres run it, and the default backend skips it by name.
func TestPostgresServesTheFirstRunAsSQLiteDoes(t *testing.T) {
	postgresURL := dbtest.PostgresURL(t)
	sqlite := serveFirstRun(t, db.SQLite, "")
	postgres := serveFirstRun(t, db.Postgres, postgresURL)

	steps := make([]string, 0, len(sqlite))
	for step := range sqlite {
		steps = append(steps, step)
	}
	slices.Sort(steps)
	if len(postgres) != len(sqlite) {
		t.Fatalf("the journey took %d steps on SQLite and %d on PostgreSQL", len(sqlite), len(postgres))
	}
	for _, step := range steps {
		t.Logf("%-30s %s", step, postgres[step])
		if want, designed := unsupportedOnPostgres[step]; designed {
			if sqlite[step] != want.sqlite || postgres[step] != want.postgres {
				t.Errorf("%s answered\n  SQLite     %s\n  PostgreSQL %s\nwant\n  SQLite     %s\n  PostgreSQL %s",
					step, sqlite[step], postgres[step], want.sqlite, want.postgres)
			}
			continue
		}
		if postgres[step] != sqlite[step] {
			t.Errorf("%s differs between the backends:\n  SQLite     %s\n  PostgreSQL %s", step, sqlite[step], postgres[step])
		}
	}
}

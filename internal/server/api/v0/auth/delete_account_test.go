package v0_auth_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"
)

const (
	deleteAccountUser     = "testuser"
	deleteAccountPassword = "TestPassword123!"
)

// newDeleteAccountEngine builds a gin engine wired to a real on-disk database
// carrying the real migration set, with HOME redirected at a temporary
// directory so storageutil.GetDataDir resolves inside the test sandbox rather
// than at the developer's actual data directory. It returns the engine, the
// database handle, and the files directory the handler will delete.
func newDeleteAccountEngine(t *testing.T) (*gin.Engine, *sql.DB, string) {
	t.Helper()
	engine, sqlDB, filesDir, _ := newDeleteAccountEngineWithDeps(t)
	return engine, sqlDB, filesDir
}

// newDeleteAccountEngineWithDeps is newDeleteAccountEngine, also returning the
// dependency graph so a test can reach the shared rate limiter.
func newDeleteAccountEngineWithDeps(t *testing.T) (*gin.Engine, *sql.DB, string, deputil.Dependencies) {
	t.Helper()

	// Redirected before GetDataDir is called anywhere below: every platform
	// branch of GetDataDirForDevice derives from os.UserHomeDir.
	t.Setenv("HOME", t.TempDir())

	sqlDB, err := sql.Open("sqlite", db.DSN(filepath.Join(t.TempDir(), "quark.db")))
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	t.Cleanup(func() { sqlDB.Close() })

	database := &db.DatabaseSqlc{Db: sqlDB}
	// On an empty file the drop half is a no-op, so this is just "run every
	// migration" — the same schema production boots with.
	if err := db.ResetDatabase(database); err != nil {
		t.Fatalf("build schema: %v", err)
	}
	conn, err := sqlDB.Conn(context.Background())
	if err != nil {
		t.Fatalf("get connection: %v", err)
	}
	database.Queries = db.New(conn)

	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(),
		Username: deleteAccountUser,
		Password: deleteAccountPassword,
	}); err != nil {
		t.Fatalf("authutil.Setup: %v", err)
	}

	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatalf("GetFilesDir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "keep.txt"), []byte("data"), 0644); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		// Production's requireAuth sets "username" and nothing else.
		c = ctxutil.With(c, "username", deleteAccountUser)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_auth.NewRouter())
	return engine, sqlDB, filesDir, deps
}

// deleteAccountRequest sends the caller's correct password.
func deleteAccountRequest(engine *gin.Engine, query string) *httptest.ResponseRecorder {
	return deleteAccountRequestWithBody(engine, query, `{"password":"`+deleteAccountPassword+`"}`)
}

// deleteAccountRequestWithBody sends body as the JSON request body, so a test
// can send a wrong password or none.
func deleteAccountRequestWithBody(engine *gin.Engine, query, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodDelete, "/api/v0/auth/account?"+query, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// decodeDeleted reads the {"deleted": {...}} envelope a successful call returns.
func decodeDeleted(t *testing.T, w *httptest.ResponseRecorder) (bool, bool, bool) {
	t.Helper()
	_, database, files, devices := decodeDeletedAspects(t, w)
	return database, files, devices
}

// decodeDeletedAspects reads all four aspects out of the envelope.
func decodeDeletedAspects(t *testing.T, w *httptest.ResponseRecorder) (bool, bool, bool, bool) {
	t.Helper()
	var body struct {
		Deleted struct {
			Account  bool `json:"account"`
			Database bool `json:"database"`
			Files    bool `json:"files"`
			Devices  bool `json:"devices"`
		} `json:"deleted"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	return body.Deleted.Account, body.Deleted.Database, body.Deleted.Files, body.Deleted.Devices
}

// sessionCount reports how many session rows survive. sessions.user_id declares
// ON DELETE CASCADE but SQLite enforces foreign keys only under PRAGMA
// foreign_keys, which nothing here sets, so this asserts the explicit session
// revocation did the work the cascade does not.
func sessionCount(t *testing.T, sqlDB *sql.DB) int {
	t.Helper()
	var count int
	if err := sqlDB.QueryRow(`SELECT count(*) FROM sessions`).Scan(&count); err != nil {
		t.Fatalf("count sessions: %v", err)
	}
	return count
}

func userCount(t *testing.T, sqlDB *sql.DB) int {
	t.Helper()
	var count int
	if err := sqlDB.QueryRow(`SELECT count(*) FROM users`).Scan(&count); err != nil {
		t.Fatalf("count users: %v", err)
	}
	return count
}

// TestDeleteAccount_NoAspectSelected verifies a request that selects nothing is
// rejected rather than treated as a full wipe.
func TestDeleteAccount_NoAspectSelected(t *testing.T) {
	engine, sqlDB, filesDir := newDeleteAccountEngine(t)

	for _, query := range []string{
		"",
		"database=false&files=false",
		"database=false&files=false&devices=false",
		"account=false&database=false&files=false&devices=false",
	} {
		w := deleteAccountRequest(engine, query)
		if w.Code != http.StatusBadRequest {
			t.Errorf("query %q: expected 400, got %d: %s", query, w.Code, w.Body.String())
		}
	}

	if _, err := os.Stat(filesDir); err != nil {
		t.Errorf("files directory should be untouched: %v", err)
	}
	if userCount(t, sqlDB) != 1 {
		t.Error("database should be untouched")
	}
}

// TestDeleteAccount_PasswordRequired verifies a missing, empty or wrong
// password deletes nothing, for every aspect: holding a session is not on its
// own consent (#2346). A wrong password is a 403, so the app does not read it
// as a lost session.
func TestDeleteAccount_PasswordRequired(t *testing.T) {
	for _, query := range []string{"account=true", "database=true&files=true", "devices=true"} {
		for _, tc := range []struct {
			body string
			want int
		}{
			{"", http.StatusBadRequest},
			{`{}`, http.StatusBadRequest},
			{`{"password":""}`, http.StatusBadRequest},
			{`{"password":"not-the-password"}`, http.StatusForbidden},
			{`{"password":"OtherPassword123!"}`, http.StatusForbidden},
		} {
			t.Run(query+" "+tc.body, func(t *testing.T) {
				engine, sqlDB, filesDir := newDeleteAccountEngine(t)
				before := sessionCount(t, sqlDB)

				w := deleteAccountRequestWithBody(engine, query, tc.body)
				if w.Code != tc.want {
					t.Fatalf("expected %d, got %d: %s", tc.want, w.Code, w.Body.String())
				}
				if tc.want == http.StatusForbidden {
					if got := decodeBody(t, w)["error"]; got != authutil.ErrIncorrectPassword.Error() {
						t.Errorf("error = %v, want %q", got, authutil.ErrIncorrectPassword.Error())
					}
				}
				if _, err := os.Stat(filepath.Join(filesDir, "keep.txt")); err != nil {
					t.Errorf("stored files should be untouched: %v", err)
				}
				if userCount(t, sqlDB) != 1 {
					t.Error("the account must survive a refused request")
				}
				if sessionCount(t, sqlDB) != before {
					t.Error("a refused request signed the caller out")
				}
			})
		}
	}
}

// TestDeleteAccount_PasswordNeverReadFromQuery verifies a password in the URL
// counts for nothing: only the body is read, so nobody is tempted to put it
// where access logs keep it.
func TestDeleteAccount_PasswordNeverReadFromQuery(t *testing.T) {
	engine, sqlDB, _ := newDeleteAccountEngine(t)

	w := deleteAccountRequestWithBody(engine, "account=true&password="+deleteAccountPassword, "")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
	if userCount(t, sqlDB) != 1 {
		t.Error("the account must survive a request with no body")
	}
}

// TestDeleteAccount_RateLimited verifies attempts spend from the shared sign-in
// limiter: once an address has used its allowance, even the right password is
// refused with 429 and nothing is deleted, so the endpoint cannot be used to
// guess the password faster than login allows.
func TestDeleteAccount_RateLimited(t *testing.T) {
	engine, sqlDB, filesDir, deps := newDeleteAccountEngineWithDeps(t)

	// Spend the whole allowance of httptest.NewRequest's address, 192.0.2.1.
	if !deps.AuthRateLimiter().AllowN("192.0.2.1", ratelimitutil.DefaultBurst) {
		t.Fatal("could not spend the allowance")
	}

	w := deleteAccountRequest(engine, "account=true&files=true")
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d: %s", w.Code, w.Body.String())
	}
	if _, err := os.Stat(filepath.Join(filesDir, "keep.txt")); err != nil {
		t.Errorf("stored files should be untouched: %v", err)
	}
	if userCount(t, sqlDB) != 1 {
		t.Error("the account must survive a rate-limited request")
	}
}

// TestDeleteAccount_RejectsNonBoolean verifies an unparseable aspect is a 400
// rather than a silent false.
func TestDeleteAccount_RejectsNonBoolean(t *testing.T) {
	engine, _, _ := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "files=not-a-bool")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

// TestDeleteAccount_RejectsNonBooleanDevices verifies the new aspect is
// validated like the other two rather than falling through as false.
func TestDeleteAccount_RejectsNonBooleanDevices(t *testing.T) {
	engine, _, _ := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "devices=sure")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

// TestDeleteAccount_DevicesOnlyIsAValidSelection verifies devices=true on its
// own satisfies the "select something" guard and leaves the appliance's own
// data alone. No drive is attached in the test environment, so this covers the
// plumbing; the path behavior is covered in authutil's own tests.
func TestDeleteAccount_DevicesOnlyIsAValidSelection(t *testing.T) {
	engine, sqlDB, filesDir := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "devices=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	databaseDeleted, filesDeleted, devicesDeleted := decodeDeleted(t, w)
	if databaseDeleted || filesDeleted || !devicesDeleted {
		t.Errorf("expected database=false files=false devices=true, got database=%v files=%v devices=%v",
			databaseDeleted, filesDeleted, devicesDeleted)
	}

	if _, err := os.Stat(filepath.Join(filesDir, "keep.txt")); err != nil {
		t.Errorf("local files must survive a devices-only reset: %v", err)
	}
	if userCount(t, sqlDB) != 1 {
		t.Error("database must survive a devices-only reset")
	}
}

// TestDeleteAccount_FilesOnly verifies files=true removes the files directory
// and leaves the database intact.
func TestDeleteAccount_FilesOnly(t *testing.T) {
	engine, sqlDB, filesDir := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "files=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	databaseDeleted, filesDeleted, devicesDeleted := decodeDeleted(t, w)
	if databaseDeleted || !filesDeleted || devicesDeleted {
		t.Errorf("expected database=false files=true devices=false, got database=%v files=%v devices=%v",
			databaseDeleted, filesDeleted, devicesDeleted)
	}

	if _, err := os.Stat(filesDir); !os.IsNotExist(err) {
		t.Errorf("files directory should be gone, stat returned %v", err)
	}
	if userCount(t, sqlDB) != 1 {
		t.Error("database should have survived a files-only delete")
	}
}

// TestDeleteAccount_DatabaseOnly verifies database=true resets the schema to
// first-boot state and leaves stored files alone.
func TestDeleteAccount_DatabaseOnly(t *testing.T) {
	engine, sqlDB, filesDir := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "database=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	databaseDeleted, filesDeleted, devicesDeleted := decodeDeleted(t, w)
	if !databaseDeleted || filesDeleted || devicesDeleted {
		t.Errorf("expected database=true files=false devices=false, got database=%v files=%v devices=%v",
			databaseDeleted, filesDeleted, devicesDeleted)
	}

	if userCount(t, sqlDB) != 0 {
		t.Error("users should be gone after a database reset")
	}
	// The schema is back, not merely emptied: sessions is queryable again.
	var sessions int
	if err := sqlDB.QueryRow(`SELECT count(*) FROM sessions`).Scan(&sessions); err != nil {
		t.Errorf("schema should have been re-migrated: %v", err)
	}
	if _, err := os.Stat(filepath.Join(filesDir, "keep.txt")); err != nil {
		t.Errorf("files should have survived a database-only delete: %v", err)
	}
}

// TestDeleteAccount_Both verifies the two aspects combine in one call.
func TestDeleteAccount_Both(t *testing.T) {
	engine, sqlDB, filesDir := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "database=true&files=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	databaseDeleted, filesDeleted, devicesDeleted := decodeDeleted(t, w)
	if !databaseDeleted || !filesDeleted {
		t.Errorf("expected both true, got database=%v files=%v", databaseDeleted, filesDeleted)
	}
	if devicesDeleted {
		t.Error("devices must stay false when it was not requested")
	}

	if userCount(t, sqlDB) != 0 {
		t.Error("users should be gone")
	}
	if _, err := os.Stat(filesDir); !os.IsNotExist(err) {
		t.Errorf("files directory should be gone, stat returned %v", err)
	}
}

// TestDeleteAccount_RepeatIsIdempotent verifies deleting what is already gone
// is a 200 rather than a 500. Files-only, because after a database reset the
// caller no longer has an account to authenticate a second call with.
func TestDeleteAccount_RepeatIsIdempotent(t *testing.T) {
	engine, _, filesDir := newDeleteAccountEngine(t)

	first := deleteAccountRequest(engine, "files=true")
	if first.Code != http.StatusOK {
		t.Fatalf("first call: expected 200, got %d: %s", first.Code, first.Body.String())
	}
	second := deleteAccountRequest(engine, "files=true")
	if second.Code != http.StatusOK {
		t.Fatalf("second call: expected 200, got %d: %s", second.Code, second.Body.String())
	}
	if _, err := os.Stat(filesDir); !os.IsNotExist(err) {
		t.Errorf("files directory should still be gone, stat returned %v", err)
	}
}

// TestDeleteAccount_RevokesSessions verifies every session is gone after a
// files-only delete, where the sessions table itself survives.
func TestDeleteAccount_RevokesSessions(t *testing.T) {
	engine, sqlDB, _ := newDeleteAccountEngine(t)

	var before int
	if err := sqlDB.QueryRow(`SELECT count(*) FROM sessions`).Scan(&before); err != nil {
		t.Fatalf("count sessions: %v", err)
	}
	if before == 0 {
		t.Fatal("setup should have created a session to revoke")
	}

	w := deleteAccountRequest(engine, "files=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var after int
	if err := sqlDB.QueryRow(`SELECT count(*) FROM sessions`).Scan(&after); err != nil {
		t.Fatalf("count sessions: %v", err)
	}
	if after != 0 {
		t.Errorf("expected all sessions revoked, %d remain", after)
	}
}

// TestDeleteAccount_AccountOnly verifies account=true removes the caller's user
// row and its sessions while leaving the schema and stored files intact. This
// is the aspect App Store Guideline 5.1.1(v) requires.
func TestDeleteAccount_AccountOnly(t *testing.T) {
	engine, sqlDB, filesDir := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "account=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	accountDeleted, databaseDeleted, filesDeleted, devicesDeleted := decodeDeletedAspects(t, w)
	if !accountDeleted || databaseDeleted || filesDeleted || devicesDeleted {
		t.Errorf("expected account=true and nothing else, got account=%v database=%v files=%v devices=%v",
			accountDeleted, databaseDeleted, filesDeleted, devicesDeleted)
	}

	if userCount(t, sqlDB) != 0 {
		t.Error("the caller's user row should be gone")
	}
	if sessionCount(t, sqlDB) != 0 {
		t.Error("the caller's sessions should be gone")
	}
	if _, err := os.Stat(filepath.Join(filesDir, "keep.txt")); err != nil {
		t.Errorf("stored files should have survived an account-only delete: %v", err)
	}
	// The schema itself must survive: an account delete is not a reset, and the
	// appliance has to stay usable for whoever else has an account on it.
	if _, err := sqlDB.Exec(`SELECT 1 FROM users LIMIT 1`); err != nil {
		t.Errorf("users table should still exist after an account-only delete: %v", err)
	}
}

// TestDeleteAccount_AccountLeavesOtherUsersAlone is the isolation property that
// separates this from a factory reset: deleting one account must not touch
// anyone else's row or their sessions. The other account is an admin, because
// the only active admin cannot delete themselves while another account remains
// (#1909); that refusal has its own test.
func TestDeleteAccount_AccountLeavesOtherUsersAlone(t *testing.T) {
	engine, sqlDB, _ := newDeleteAccountEngine(t)

	database := &db.DatabaseSqlc{Db: sqlDB}
	conn, err := sqlDB.Conn(context.Background())
	if err != nil {
		t.Fatalf("get connection: %v", err)
	}
	database.Queries = db.New(conn)

	const otherUser = "other-user"
	hash, err := authutil.HashPassword("OtherPassword123!")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}
	other, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username:           otherUser,
		PasswordHash:       hash,
		RecoveryPhraseHash: hash,
	})
	if err != nil {
		t.Fatalf("create second user: %v", err)
	}
	if err := authutil.PromoteToAdmin(context.Background(), database.Queries, otherUser); err != nil {
		t.Fatalf("promote second user: %v", err)
	}
	if userCount(t, sqlDB) != 2 {
		t.Fatalf("expected 2 users before the delete, got %d", userCount(t, sqlDB))
	}

	w := deleteAccountRequest(engine, "account=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	if userCount(t, sqlDB) != 1 {
		t.Fatalf("expected exactly the other user to remain, got %d rows", userCount(t, sqlDB))
	}
	survivor, err := database.Queries.GetUserByID(context.Background(), other.ID)
	if err != nil {
		t.Fatalf("the other user's row should have survived: %v", err)
	}
	if survivor.Username != otherUser {
		t.Errorf("expected %q to survive, found %q", otherUser, survivor.Username)
	}
}

// TestDeleteAccount_AccountRepeatAfterDelete verifies a second account delete
// from a session that outlived the account is a 401 rather than a 500: there
// is no password left to check, and nothing the session could still act on.
func TestDeleteAccount_AccountRepeatAfterDelete(t *testing.T) {
	engine, sqlDB, _ := newDeleteAccountEngine(t)

	query := "account=true"
	if w := deleteAccountRequest(engine, query); w.Code != http.StatusOK {
		t.Fatalf("first call: expected 200, got %d: %s", w.Code, w.Body.String())
	}
	w := deleteAccountRequest(engine, query)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("second call: expected 401, got %d: %s", w.Code, w.Body.String())
	}
	if userCount(t, sqlDB) != 0 {
		t.Error("no user rows should remain")
	}
}

// TestDeleteAccount_LastAccountReturnsToSetup verifies deleting the only account
// takes the appliance back to first boot rather than bricking it: IsSetupComplete
// is COUNT(users) > 0, so the setup flow re-triggers.
func TestDeleteAccount_LastAccountReturnsToSetup(t *testing.T) {
	engine, sqlDB, _ := newDeleteAccountEngine(t)

	if w := deleteAccountRequest(engine, "account=true"); w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	conn, err := sqlDB.Conn(context.Background())
	if err != nil {
		t.Fatalf("get connection: %v", err)
	}
	complete, err := authutil.IsSetupComplete(context.Background(), db.New(conn))
	if err != nil {
		t.Fatalf("IsSetupComplete: %v", err)
	}
	if complete {
		t.Error("setup should report incomplete once the last account is gone")
	}
}

// decodeFilesRetained reads the top-level flag warning that stored files
// outlived the account or database that were deleted.
func decodeFilesRetained(t *testing.T, w *httptest.ResponseRecorder) bool {
	t.Helper()
	var body struct {
		FilesRetained bool `json:"filesRetained"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v\nbody: %s", err, w.Body.String())
	}
	return body.FilesRetained
}

// TestDeleteAccount_FilesRetainedWarning covers the disclosure that matters for
// App Store account deletion: deleting the account without files leaves the
// data on disk for whoever sets the appliance up next, and the response has to
// say so. Passing files=true clears the flag because nothing was left behind.
func TestDeleteAccount_FilesRetainedWarning(t *testing.T) {
	for _, testCase := range []struct {
		query string
		want  bool
	}{
		{"account=true", true},
		{"database=true", true},
		{"account=true&database=true", true},
		{"account=true&files=true", false},
		{"database=true&files=true", false},
		{"files=true", false},
	} {
		t.Run(testCase.query, func(t *testing.T) {
			engine, _, _ := newDeleteAccountEngine(t)

			w := deleteAccountRequest(engine, testCase.query)
			if w.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
			}
			if got := decodeFilesRetained(t, w); got != testCase.want {
				t.Errorf("filesRetained = %v, want %v", got, testCase.want)
			}
		})
	}
}

// TestDeleteAccount_FilesSurviveAnAccountDelete is the concrete half of the
// warning above: the flag is not decoration, the files really are still there.
func TestDeleteAccount_FilesSurviveAnAccountDelete(t *testing.T) {
	engine, _, filesDir := newDeleteAccountEngine(t)

	w := deleteAccountRequest(engine, "account=true&database=true")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !decodeFilesRetained(t, w) {
		t.Fatal("filesRetained should be true when the files were not selected")
	}
	if _, err := os.Stat(filepath.Join(filesDir, "keep.txt")); err != nil {
		t.Errorf("the previous owner's file should still be on disk: %v", err)
	}
}

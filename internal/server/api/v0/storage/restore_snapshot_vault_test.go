package v0_storage_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// vaultQuark is a Quark's database holding the accounts named, each with a
// vault key and one item where its value is true.
func vaultQuark(t *testing.T, vaults map[string]bool) *db.DatabaseSqlc {
	t.Helper()
	database := dbtest.NewDB(t)
	for username, withVault := range vaults {
		exec(t, database, `INSERT INTO users (username, password_hash, recovery_phrase_hash, auth_salt) VALUES (?, 'x', 'x', ?)`,
			username, "c2FsdC1vZi0"+username)
		if !withVault {
			continue
		}
		exec(t, database, `INSERT INTO vault_keys (user_id, wrapped_by_password, salt_pw, kdf_params)
			SELECT id, x'0102', x'00112233445566778899aabbccddeeff', '{}' FROM users WHERE username = ?`, username)
		exec(t, database, `INSERT INTO vault_items (user_id, ciphertext, nonce, format_version)
			SELECT id, x'aa', x'bb', 1 FROM users WHERE username = ?`, username)
	}
	return database
}

func exec(t *testing.T, database *db.DatabaseSqlc, query string, args ...any) {
	t.Helper()
	if _, err := database.Db.Exec(query, args...); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
}

// newRestoreEngine serves the admin storage routes over live and a backup
// drive, a directory on disk, under backupSerial.
func newRestoreEngine(t *testing.T, live *db.DatabaseSqlc, driveDir string) *gin.Engine {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	drive, err := vfs.NewLocalVFS(driveDir, vfs.FilesNamespace(backupSerial))
	if err != nil {
		t.Fatal(err)
	}
	reg := vfs.NewRegistry()
	for serial, fsys := range map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), backupSerial: drive} {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(live)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_storage.NewAdminRouter())
	return engine
}

func restoreVault(engine *gin.Engine, serial string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup/restore-vault",
		strings.NewReader(`{"deviceSerial":"`+serial+`"}`))
	req.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(w, req)
	return w
}

// A snapshot's vault backup comes back through the route onto a new Quark
// (#3614): every vault under its username's account, with the accounts whose
// vault opens with the password of backup time named.
func TestRestoreSnapshotVault_RestoresOntoANewQuark(t *testing.T) {
	driveDir := t.TempDir()
	source := vaultQuark(t, map[string]bool{"alice": true, "bob": true, "carol": false})
	if _, err := backup.ExportVault(context.Background(), source.Db, driveDir); err != nil {
		t.Fatal(err)
	}

	live := vaultQuark(t, map[string]bool{"bob": false, "alice": false})
	w := restoreVault(newRestoreEngine(t, live, driveDir), backupSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("restore = %d %s, want 200", w.Code, w.Body.String())
	}
	var result backup.VaultImportResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Accounts != 2 || result.Items != 2 ||
		strings.Join(result.UnmatchedUsers, ",") != "carol" ||
		strings.Join(result.BackupPasswordAccounts, ",") != "alice,bob" {
		t.Errorf("result = %+v, want 2 accounts, 2 items, carol unmatched, alice and bob on the backup's password", result)
	}

	// A second restore finds the vaults full.
	if w := restoreVault(newRestoreEngine(t, live, driveDir), backupSerial); w.Code != http.StatusConflict {
		t.Errorf("second restore = %d %s, want 409", w.Code, w.Body.String())
	}
}

func TestRestoreSnapshotVault_Refusals(t *testing.T) {
	driveDir := t.TempDir()
	source := vaultQuark(t, map[string]bool{"carol": true})
	if _, err := backup.ExportVault(context.Background(), source.Db, driveDir); err != nil {
		t.Fatal(err)
	}

	for _, tc := range []struct {
		name, serial, dir string
		live              map[string]bool
		want              int
		wantBody          string
	}{
		{"no account of the vault's username", backupSerial, driveDir, map[string]bool{"Carol": false}, http.StatusConflict, "carol"},
		{"drive not attached", "GONE", driveDir, map[string]bool{"carol": false}, http.StatusNotFound, ""},
		{"drive holds no vault backup", backupSerial, t.TempDir(), map[string]bool{"carol": false}, http.StatusNotFound, ""},
		{"no device named", "", driveDir, map[string]bool{"carol": false}, http.StatusBadRequest, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			live := vaultQuark(t, tc.live)
			w := restoreVault(newRestoreEngine(t, live, tc.dir), tc.serial)
			if w.Code != tc.want || !strings.Contains(w.Body.String(), tc.wantBody) {
				t.Errorf("restore = %d %s, want %d naming %q", w.Code, w.Body.String(), tc.want, tc.wantBody)
			}
			var keys int
			if err := live.Db.QueryRow(`SELECT COUNT(*) FROM vault_keys`).Scan(&keys); err != nil || keys != 0 {
				t.Errorf("a refused restore left %d vault keys (%v)", keys, err)
			}
		})
	}
}

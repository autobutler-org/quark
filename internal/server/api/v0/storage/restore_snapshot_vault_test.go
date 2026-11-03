package v0_storage_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// validKdfParams is a cost vaultutil.ValidateKey accepts.
const validKdfParams = `{"alg":"argon2id13","opsLimit":3,"memLimit":67108864}`

// vaultQuark is a Quark's database holding the accounts named, each with a
// vault key and one item where its value is true, beside an admin who signs in
// with adminPassword and the backup drive's snapshot-backup role.
func vaultQuark(t *testing.T, vaults map[string]bool) *db.DatabaseSqlc {
	t.Helper()
	database := dbtest.NewDB(t)
	hash, err := authutil.HashKey(dbtest.AuthKey(adminPassword))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := database.Queries.CreateUser(context.Background(),
		db.CreateUserParams{Username: "admin", AuthKeyHash: hash, RecoveryPhraseHash: "r"}); err != nil {
		t.Fatal(err)
	}
	if err := database.Queries.UpsertDeviceRole(context.Background(),
		db.UpsertDeviceRoleParams{DeviceSerial: backupSerial, Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	for username, withVault := range vaults {
		exec(t, database, `INSERT INTO users (username, password_hash, recovery_phrase_hash, auth_salt) VALUES (?, 'x', 'x', ?)`,
			username, "c2FsdC1vZi0"+username)
		if !withVault {
			continue
		}
		exec(t, database, `INSERT INTO vault_keys (user_id, wrapped_by_password, salt_pw, kdf_params)
			SELECT id, x'0102', x'00112233445566778899aabbccddeeff', ? FROM users WHERE username = ?`, validKdfParams, username)
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

const adminPassword = "admin-password"

// restoreEngine is the admin storage routes and the vault_changed events they
// publish.
type restoreEngine struct {
	*gin.Engine
	events <-chan eventbus.Event
}

// heard drains the user ids vault_changed has been published to so far.
func (e restoreEngine) heard() []int64 {
	var out []int64
	for {
		select {
		case evt := <-e.events:
			if data, ok := evt.Data.(eventbus.VaultChanged); ok && evt.Kind == eventbus.EventVaultChanged {
				out = append(out, data.UserID)
			}
		default:
			return out
		}
	}
}

// newRestoreEngine serves the admin storage routes over live and a backup
// drive, a directory on disk, under backupSerial, to live's admin.
func newRestoreEngine(t *testing.T, live *db.DatabaseSqlc, driveDir string) restoreEngine {
	t.Helper()
	admin, err := live.Queries.GetUserByUsername(context.Background(), "admin")
	if err != nil {
		t.Fatal(err)
	}
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
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("restore-vault-test")
	t.Cleanup(unsubscribe)
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(live).WithEventBus(bus)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "username", "admin")
		c = ctxutil.With(c, "userID", admin.ID)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: admin.ID, IsAdmin: true})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_storage.NewAdminRouter())
	return restoreEngine{Engine: engine, events: events}
}

// restoreVault restores from serial's drive as the admin, re-confirmed.
func restoreVault(engine restoreEngine, serial string) *httptest.ResponseRecorder {
	return restoreVaultBody(engine, `{"deviceSerial":"`+serial+`","password":"`+dbtest.AuthKey(adminPassword)+`"}`)
}

func restoreVaultBody(engine restoreEngine, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup/restore-vault",
		strings.NewReader(body))
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
	engine := newRestoreEngine(t, live, driveDir)
	w := restoreVault(engine, backupSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("restore = %d %s, want 200", w.Code, w.Body.String())
	}
	var result backup.VaultImportResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Accounts != 2 || result.Items != 2 ||
		strings.Join(result.UnmatchedUsers, ",") != "carol" ||
		strings.Join(result.BackupPasswordAccounts, ",") != "alice,bob" ||
		strings.Join(result.RestoredAccounts, ",") != "alice,bob" {
		t.Errorf("result = %+v, want 2 accounts, 2 items, carol unmatched, alice and bob restored and on the backup's password", result)
	}

	// Each restored account's sessions are told, and nobody else's.
	var alice, bob int64
	if err := live.Db.QueryRow(`SELECT (SELECT id FROM users WHERE username = 'alice'), (SELECT id FROM users WHERE username = 'bob')`).
		Scan(&alice, &bob); err != nil {
		t.Fatal(err)
	}
	if heard := engine.heard(); !slices.Equal(heard, []int64{alice, bob}) {
		t.Errorf("vault_changed went to %v, want alice %d and bob %d", heard, alice, bob)
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

	emptyDrive := t.TempDir()
	withPassword := func(serial, password string) string {
		return `{"deviceSerial":"` + serial + `","password":"` + password + `"}`
	}
	for _, tc := range []struct {
		name, dir, body string
		live            map[string]bool
		// setup, when set, changes live before the restore.
		setup    func(t *testing.T, live *db.DatabaseSqlc)
		want     int
		wantBody string
		// wantKeys is the vault keys live must still hold afterwards.
		wantKeys int
	}{
		{name: "no account of the vault's username", dir: driveDir, body: withPassword(backupSerial, dbtest.AuthKey(adminPassword)),
			live: map[string]bool{"Carol": false}, want: http.StatusConflict, wantBody: "carol"},
		{name: "drive not attached", dir: driveDir, body: withPassword("GONE", dbtest.AuthKey(adminPassword)),
			live: map[string]bool{"carol": false}, want: http.StatusNotFound},
		{name: "drive holds no vault backup", dir: emptyDrive, body: withPassword(backupSerial, dbtest.AuthKey(adminPassword)),
			live: map[string]bool{"carol": false}, want: http.StatusNotFound, wantBody: "vault_items_backup.db not found"},
		{name: "no device named", dir: driveDir, body: withPassword("", dbtest.AuthKey(adminPassword)),
			live: map[string]bool{"carol": false}, want: http.StatusBadRequest},
		{name: "no password", dir: driveDir, body: `{"deviceSerial":"` + backupSerial + `"}`,
			live: map[string]bool{"carol": false}, want: http.StatusForbidden},
		{name: "wrong password", dir: driveDir, body: withPassword(backupSerial, dbtest.AuthKey("not-the-password")),
			live: map[string]bool{"carol": false}, want: http.StatusForbidden},
		{name: "raw password", dir: driveDir, body: withPassword(backupSerial, "admin-password"),
			live: map[string]bool{"carol": false}, want: http.StatusUpgradeRequired},
		{name: "body over 1 KiB", dir: driveDir, body: withPassword(backupSerial, strings.Repeat("a", 2<<10)),
			live: map[string]bool{"carol": false}, want: http.StatusRequestEntityTooLarge},
		{name: "drive without the snapshot-backup role", dir: driveDir, body: withPassword(backupSerial, dbtest.AuthKey(adminPassword)),
			live: map[string]bool{"carol": false}, want: http.StatusBadRequest, wantBody: "snapshot-backup role",
			setup: func(t *testing.T, live *db.DatabaseSqlc) {
				exec(t, live, `UPDATE device_roles SET role = 'unassigned' WHERE device_serial = ?`, backupSerial)
			}},
		{name: "account already has a vault key", dir: driveDir, body: withPassword(backupSerial, dbtest.AuthKey(adminPassword)),
			live: map[string]bool{"carol": false}, want: http.StatusConflict, wantBody: "(carol)", wantKeys: 1,
			setup: func(t *testing.T, live *db.DatabaseSqlc) {
				exec(t, live, `INSERT INTO vault_keys (user_id, wrapped_by_password, salt_pw, kdf_params)
					SELECT id, x'0303', x'ffeeddccbbaa99887766554433221100', ? FROM users WHERE username = 'carol'`, validKdfParams)
			}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			live := vaultQuark(t, tc.live)
			if tc.setup != nil {
				tc.setup(t, live)
			}
			engine := newRestoreEngine(t, live, tc.dir)
			w := restoreVaultBody(engine, tc.body)
			if w.Code != tc.want || !strings.Contains(w.Body.String(), tc.wantBody) {
				t.Errorf("restore = %d %s, want %d naming %q", w.Code, w.Body.String(), tc.want, tc.wantBody)
			}
			// The 404 for a missing file never shows where the drive is mounted.
			if strings.Contains(w.Body.String(), tc.dir) {
				t.Errorf("restore answer %s shows the drive's host path %s", w.Body.String(), tc.dir)
			}
			var keys int
			if err := live.Db.QueryRow(`SELECT COUNT(*) FROM vault_keys`).Scan(&keys); err != nil || keys != tc.wantKeys {
				t.Errorf("a refused restore left %d vault keys, want %d (%v)", keys, tc.wantKeys, err)
			}
			if tc.wantKeys > 0 {
				var wrapped []byte
				if err := live.Db.QueryRow(`SELECT wrapped_by_password FROM vault_keys`).Scan(&wrapped); err != nil || string(wrapped) != "\x03\x03" {
					t.Errorf("a refused restore replaced the account's own key with %x (%v)", wrapped, err)
				}
			}
			if heard := engine.heard(); len(heard) != 0 {
				t.Errorf("a refused restore published vault_changed to %v", heard)
			}
		})
	}
}

// A backup row this Quark would refuse from a client refuses the restore,
// naming its account, and nothing changes.
func TestRestoreSnapshotVault_RefusesARowOutsideTheValidationBounds(t *testing.T) {
	driveDir := t.TempDir()
	source := vaultQuark(t, map[string]bool{"carol": true, "dave": true})
	if _, err := backup.ExportVault(context.Background(), source.Db, driveDir); err != nil {
		t.Fatal(err)
	}
	backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(driveDir, "vault_items_backup.db")))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := backupDB.Exec(`UPDATE vault_keys SET kdf_params = '{"alg":"x","opsLimit":4294967295,"memLimit":4398046511104}'
		WHERE user_id = (SELECT id FROM users WHERE username = 'dave')`); err != nil {
		t.Fatal(err)
	}
	backupDB.Close()

	live := vaultQuark(t, map[string]bool{"carol": false, "dave": false})
	w := restoreVault(newRestoreEngine(t, live, driveDir), backupSerial)
	if w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "(dave)") {
		t.Errorf("restore = %d %s, want 400 naming dave alone", w.Code, w.Body.String())
	}
	var keys int
	if err := live.Db.QueryRow(`SELECT COUNT(*) FROM vault_keys`).Scan(&keys); err != nil || keys != 0 {
		t.Errorf("a refused restore left %d vault keys (%v)", keys, err)
	}
}

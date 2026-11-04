// cspell:ignore zeroblob

package backup

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"golang.org/x/crypto/chacha20poly1305"
)

// vaultOwner is one account's key material as its client holds it: the key
// the password derives, which wraps the vault key, and the items' plaintext.
type vaultOwner struct {
	username string
	wrapKey  []byte
	items    []string
}

// randomBytes is n bytes from crypto/rand.
func randomBytes(t *testing.T, n int) []byte {
	t.Helper()
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		t.Fatal(err)
	}
	return b
}

// seal encrypts plaintext under key with XChaCha20-Poly1305 and a fresh nonce,
// as the client does.
func seal(t *testing.T, key, plaintext []byte) (ciphertext, nonce []byte) {
	t.Helper()
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		t.Fatal(err)
	}
	nonce = randomBytes(t, chacha20poly1305.NonceSizeX)
	return aead.Seal(nil, nonce, plaintext, nil), nonce
}

// open decrypts what seal produced.
func open(t *testing.T, key, ciphertext, nonce []byte) []byte {
	t.Helper()
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		t.Fatal(err)
	}
	plaintext, err := aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	return plaintext
}

// seedVault gives each owner, who must already have an account in d, a random
// vault key wrapped under its wrapKey (nonce then ciphertext, the client's
// layout) and its items encrypted under that vault key.
func seedVault(t *testing.T, d *sql.DB, owners ...vaultOwner) {
	t.Helper()
	for _, owner := range owners {
		vaultKey := randomBytes(t, chacha20poly1305.KeySize)
		wrapped, wrapNonce := seal(t, owner.wrapKey, vaultKey)
		chatExec(t, d, `
			INSERT INTO vault_keys (user_id, wrapped_by_password, salt_pw, kdf_params)
			SELECT id, ?, ?, ? FROM users WHERE username = ?`,
			append(wrapNonce, wrapped...), randomBytes(t, 16), validKdfParams, owner.username)
		for _, item := range owner.items {
			ciphertext, nonce := seal(t, vaultKey, []byte(item))
			chatExec(t, d, `
				INSERT INTO vault_items (user_id, ciphertext, nonce, format_version, created_at, updated_at)
				SELECT id, ?, ?, 1, '2026-01-02 03:04:05', '2026-01-02 03:04:06' FROM users WHERE username = ?`,
				ciphertext, nonce, owner.username)
		}
	}
}

// validKdfParams is a cost vaultutil.ValidateKey accepts.
const validKdfParams = `{"alg":"argon2id13","opsLimit":3,"memLimit":67108864}`

// dumpVault reads every vault row but those of the account named except,
// naming each row's account by username, so a restore that moved an account
// to another id still compares equal.
func dumpVault(t *testing.T, d *sql.DB, except string) map[string][]string {
	t.Helper()
	return map[string][]string{
		"vault_keys": queryRows(t, d, `
			SELECT u.username, k.wrapped_by_password, k.salt_pw, k.wrapped_by_phrase, k.salt_rp,
				k.kdf_params, k.created_at, k.updated_at
			FROM vault_keys k JOIN users u ON u.id = k.user_id
			WHERE u.username <> '`+except+`' ORDER BY u.username`),
		"vault_items": queryRows(t, d, `
			SELECT i.id, u.username, i.ciphertext, i.nonce, i.format_version, i.created_at, i.updated_at
			FROM vault_items i JOIN users u ON u.id = i.user_id
			WHERE u.username <> '`+except+`' ORDER BY i.id`),
	}
}

func exportVault(t *testing.T, d *sql.DB) string {
	t.Helper()
	dir := t.TempDir()
	if _, err := ExportVault(context.Background(), d, dir); err != nil {
		t.Fatalf("ExportVault: %v", err)
	}
	return dir
}

// The acceptance test of #3460: two accounts' vaults are backed up with no
// password, restored into an empty database, and come back byte for byte,
// still opening with each owner's own key material.
func TestVaultBackup_RoundTripDecryptsWithTheOwnersKey(t *testing.T) {
	ctx := context.Background()
	alice := vaultOwner{"alice", randomBytes(t, chacha20poly1305.KeySize), []string{`{"name":"GitHub"}`, `{"name":"Bank"}`}}
	bob := vaultOwner{"bob", randomBytes(t, chacha20poly1305.KeySize), []string{`{"name":"Mail"}`}}

	source := dbtest.NewDB(t).Db
	// carol never made a vault, and has no account on the new install: she
	// is named, and does not hold the restore up.
	addChatUsers(t, source, "alice", "bob", "carol")
	seedVault(t, source, alice, bob)
	chatExec(t, source, `UPDATE vault_keys SET wrapped_by_phrase = ?, salt_rp = ? WHERE user_id = 1`, []byte("alice-phrase"), randomBytes(t, 16))
	want := dumpVault(t, source, "")
	dir := exportVault(t, source)
	sumBefore := fileChecksum(t, filepath.Join(dir, backupVaultFilename))

	// The new install numbered its accounts differently, has no carol, and
	// dave, whom the backup does not know, has a vault key of his own.
	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "bob", "dave", "alice")
	seedVault(t, live, vaultOwner{username: "dave", wrapKey: randomBytes(t, chacha20poly1305.KeySize)})
	want["vault_keys"] = append(want["vault_keys"], dumpVault(t, live, "")["vault_keys"]...)
	slices.Sort(want["vault_keys"])

	result, err := ImportVault(ctx, live, dir)
	if err != nil {
		t.Fatalf("ImportVault: %v", err)
	}
	if result.Accounts != 2 || result.Items != 3 || !slices.Equal(result.UnmatchedUsers, []string{"carol"}) ||
		!slices.Equal(result.RestoredAccounts, []string{"alice", "bob"}) || len(result.RestoredUserIDs) != 2 {
		t.Errorf("result = %+v, want 2 accounts, 3 items, carol unmatched, alice and bob restored", result)
	}

	got := dumpVault(t, live, "")
	slices.Sort(got["vault_keys"])
	if !reflect.DeepEqual(got, want) {
		t.Errorf("vault after restore\n got %v\nwant %v", got, want)
	}

	for _, owner := range []vaultOwner{alice, bob} {
		var wrapped []byte
		if err := live.QueryRow(`SELECT k.wrapped_by_password FROM vault_keys k JOIN users u ON u.id = k.user_id WHERE u.username = ?`,
			owner.username).Scan(&wrapped); err != nil {
			t.Fatal(err)
		}
		vaultKey := open(t, owner.wrapKey, wrapped[chacha20poly1305.NonceSizeX:], wrapped[:chacha20poly1305.NonceSizeX])
		rows, err := live.Query(`SELECT i.ciphertext, i.nonce FROM vault_items i JOIN users u ON u.id = i.user_id WHERE u.username = ? ORDER BY i.id`, owner.username)
		if err != nil {
			t.Fatal(err)
		}
		var opened []string
		for rows.Next() {
			var ciphertext, nonce []byte
			if err := rows.Scan(&ciphertext, &nonce); err != nil {
				t.Fatal(err)
			}
			opened = append(opened, string(open(t, vaultKey, ciphertext, nonce)))
		}
		rows.Close()
		if !slices.Equal(opened, owner.items) {
			t.Errorf("%s's restored vault opens to %v, want %v", owner.username, opened, owner.items)
		}
	}

	if fileChecksum(t, filepath.Join(dir, backupVaultFilename)) != sumBefore {
		t.Error("the restore changed the backup file")
	}
}

func TestImportVault_RefusesAVaultWithItems(t *testing.T) {
	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice")
	seedVault(t, source, vaultOwner{"alice", randomBytes(t, 32), []string{"a"}})
	dir := exportVault(t, source)

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice")
	seedVault(t, live, vaultOwner{"alice", randomBytes(t, 32), []string{"mine"}})
	before := dumpVault(t, live, "")

	if _, err := ImportVault(context.Background(), live, dir); !errors.Is(err, ErrVaultNotEmpty) {
		t.Fatalf("ImportVault = %v, want ErrVaultNotEmpty", err)
	}
	if after := dumpVault(t, live, ""); !reflect.DeepEqual(after, before) {
		t.Errorf("a refused restore changed the live vault\n got %v\nwant %v", after, before)
	}
}

func TestImportVault_RefusesUnknownVersion(t *testing.T) {
	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice")
	seedVault(t, source, vaultOwner{"alice", randomBytes(t, 32), []string{"a"}})
	dir := exportVault(t, source)

	backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(dir, backupVaultFilename)))
	if err != nil {
		t.Fatal(err)
	}
	chatExec(t, backupDB, fmt.Sprintf(`PRAGMA user_version = %d`, db.VaultItemsBackupVersion+1))
	backupDB.Close()

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice")
	if _, err := ImportVault(context.Background(), live, dir); !errors.Is(err, ErrVaultBackupVersion) {
		t.Fatalf("ImportVault = %v, want ErrVaultBackupVersion", err)
	}
	assertRows(t, live, `SELECT COUNT(*) FROM vault_keys`, "[0]")
}

// ExportVault copies with SELECT * and ImportVault names the live columns, so
// both are wrong the day a migration changes a vault table and the backup
// schema does not follow.
func TestVaultBackupSchema_MatchesLiveTables(t *testing.T) {
	live := dbtest.NewDB(t).Db
	backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(t.TempDir(), "schema.db")))
	if err != nil {
		t.Fatal(err)
	}
	defer backupDB.Close()
	chatExec(t, backupDB, db.VaultItemsBackupSchemaDDL)

	for _, table := range vaultBackup.tables {
		query := "SELECT cid, name FROM pragma_table_info('" + table + "') ORDER BY cid"
		want := queryRows(t, live, query)
		if len(want) == 0 {
			t.Errorf("%s is not a live table", table)
		}
		if got := queryRows(t, backupDB, query); !slices.Equal(got, want) {
			t.Errorf("%s columns: backup schema has %v, the migrations have %v;"+
				" update VaultItemsBackupSchemaDDL, VaultItemsBackupVersion and vaultRestoreSteps", table, got, want)
		}
	}

	// Every live vault table is one the backup knows about.
	assertRows(t, live, `SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name LIKE 'vault\_%' ESCAPE '\'`,
		fmt.Sprintf("[%d]", len(vaultBackup.tables)))
}

// setAuthSalt gives username's account the auth salt its Quark derives every
// key over, as users.auth_salt stores it.
func setAuthSalt(t *testing.T, d *sql.DB, username string, salt []byte) {
	t.Helper()
	chatExec(t, d, `UPDATE users SET auth_salt = ? WHERE username = ?`, base64.StdEncoding.EncodeToString(salt), username)
}

// A restore onto new hardware (#3614). The new install derives each account's
// auth salt from a secret of its own, so the restored password wrap, made over
// the old install's salt, opens with the password the account had when the
// backup was taken and no other. The result names every such account, so the
// app can say why its login password does not open the vault.
func TestImportVault_NamesTheAccountsThatOpenWithTheBackupsPassword(t *testing.T) {
	alice := vaultOwner{"alice", randomBytes(t, chacha20poly1305.KeySize), []string{"a"}}
	bob := vaultOwner{"bob", randomBytes(t, chacha20poly1305.KeySize), []string{"b"}}

	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice", "bob")
	seedVault(t, source, alice, bob)
	oldSalt := map[string][]byte{"alice": randomBytes(t, 16), "bob": randomBytes(t, 16)}
	for username, salt := range oldSalt {
		setAuthSalt(t, source, username, salt)
		chatExec(t, source, `UPDATE vault_keys SET salt_pw = ? WHERE user_id = (SELECT id FROM users WHERE username = ?)`, salt, username)
	}
	dir := exportVault(t, source)

	// alice's new account has a salt of the new install's; bob's happens to
	// keep his, as a restore onto the same Quark would.
	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice", "bob")
	setAuthSalt(t, live, "alice", randomBytes(t, 16))
	setAuthSalt(t, live, "bob", oldSalt["bob"])

	result, err := ImportVault(context.Background(), live, dir)
	if err != nil {
		t.Fatalf("ImportVault: %v", err)
	}
	if !slices.Equal(result.BackupPasswordAccounts, []string{"alice"}) {
		t.Errorf("BackupPasswordAccounts = %v, want [alice]", result.BackupPasswordAccounts)
	}
	// The salt travels with the wrap, so the old password still opens it.
	assertRows(t, live, `SELECT hex(k.salt_pw) FROM vault_keys k JOIN users u ON u.id = k.user_id WHERE u.username = 'alice'`,
		fmt.Sprintf(`["%X"]`, oldSalt["alice"]))
}

// The right account for a backed-up vault is the account on this Quark whose
// username is byte for byte the backup's, as sign-in looks it up. A vault
// whose username has no such account is never placed under a near match
// ("Carol" for "carol") or dropped: the whole restore is refused, naming it,
// and nothing changes. Dropping it would lose it for good, since a second
// restore is refused once any vault has items.
func TestImportVault_RefusesAVaultWithNoAccountOfItsUsername(t *testing.T) {
	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice", "carol", "dave")
	seedVault(t, source,
		vaultOwner{"alice", randomBytes(t, 32), []string{"a"}},
		vaultOwner{"carol", randomBytes(t, 32), []string{"c"}},
		vaultOwner{"dave", randomBytes(t, 32), nil})
	dir := exportVault(t, source)

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice", "Carol")
	// Carol made a key here, which a refused restore keeps.
	seedVault(t, live, vaultOwner{username: "Carol", wrapKey: randomBytes(t, 32)})
	before := dumpVault(t, live, "")

	_, err := ImportVault(context.Background(), live, dir)
	if !errors.Is(err, ErrVaultAccountMissing) {
		t.Fatalf("ImportVault = %v, want ErrVaultAccountMissing", err)
	}
	if !strings.Contains(err.Error(), "carol, dave") {
		t.Errorf("error %q does not name carol and dave", err)
	}
	if after := dumpVault(t, live, ""); !reflect.DeepEqual(after, before) {
		t.Errorf("a refused restore changed the live vault\n got %v\nwant %v", after, before)
	}
}

// RestoreVault reads the backup from the drive a snapshot wrote it to.
func TestRestoreVault_ReadsTheBackupDrive(t *testing.T) {
	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice")
	seedVault(t, source, vaultOwner{"alice", randomBytes(t, 32), []string{"a", "b"}})
	driveDir := exportVault(t, source)
	drive, err := vfs.NewLocalVFS(driveDir, vfs.FilesNamespace("BACKUP-1"))
	if err != nil {
		t.Fatal(err)
	}
	reg := vfs.NewRegistry()
	for serial, fsys := range map[string]vfs.VFS{"": vfs.NewMemVFS(vfs.FilesNamespace("")), "BACKUP-1": drive} {
		if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}

	liveDB := dbtest.NewDB(t)
	live := liveDB.Db
	addChatUsers(t, live, "alice")
	params := RestoreVaultParams{Ctx: context.Background(), LiveDB: live, Queries: liveDB.Queries, Registry: reg, DeviceSerial: "BACKUP-1"}

	// A drive holding the file is not enough: it must be the snapshots' drive.
	for _, role := range []string{"", "unassigned", "default-storage"} {
		if role != "" {
			chatExec(t, live, `INSERT OR REPLACE INTO device_roles (device_serial, role) VALUES ('BACKUP-1', ?)`, role)
		}
		if _, err := RestoreVault(params); !errors.Is(err, ErrVaultRestoreRoleRequired) {
			t.Errorf("RestoreVault from a drive with role %q = %v, want ErrVaultRestoreRoleRequired", role, err)
		}
	}
	assertRows(t, live, `SELECT COUNT(*) FROM vault_keys`, "[0]")

	chatExec(t, live, `INSERT OR REPLACE INTO device_roles (device_serial, role) VALUES ('BACKUP-1', 'snapshot-backup')`)
	result, err := RestoreVault(params)
	if err != nil {
		t.Fatalf("RestoreVault: %v", err)
	}
	if result.Accounts != 1 || result.Items != 2 {
		t.Errorf("result = %+v, want 1 account, 2 items", result)
	}

	var notFound *fileutil.NotFoundError
	params.DeviceSerial = "GONE"
	if _, err := RestoreVault(params); !errors.As(err, &notFound) {
		t.Errorf("RestoreVault from a drive that is not attached = %v, want *fileutil.NotFoundError", err)
	}
}

// A restore never replaces a vault key (quark-project#267). An account the
// backup has a vault for that already has a key here refuses the whole
// restore, naming every such account, and nothing changes: a session open on
// it would otherwise go on sealing items under a key that is gone.
func TestImportVault_RefusesAnAccountThatHasAVaultKey(t *testing.T) {
	source := dbtest.NewDB(t).Db
	addChatUsers(t, source, "alice", "bob", "carol")
	seedVault(t, source,
		vaultOwner{"alice", randomBytes(t, 32), []string{"a"}},
		vaultOwner{"bob", randomBytes(t, 32), nil},
		vaultOwner{"carol", randomBytes(t, 32), []string{"c"}})
	dir := exportVault(t, source)

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "carol", "bob", "alice")
	// bob and carol signed in here and made keys, with no items yet.
	seedVault(t, live,
		vaultOwner{username: "bob", wrapKey: randomBytes(t, 32)},
		vaultOwner{username: "carol", wrapKey: randomBytes(t, 32)})
	before := dumpVault(t, live, "")

	_, err := ImportVault(context.Background(), live, dir)
	if !errors.Is(err, ErrVaultKeyExists) {
		t.Fatalf("ImportVault = %v, want ErrVaultKeyExists", err)
	}
	if !strings.Contains(err.Error(), "(bob, carol)") {
		t.Errorf("error %q does not name bob and carol", err)
	}
	if after := dumpVault(t, live, ""); !reflect.DeepEqual(after, before) {
		t.Errorf("a refused restore changed the live vault\n got %v\nwant %v", after, before)
	}
}

// Every backup key and item passes the checks an API write does
// (vaultutil.ValidateKey, ValidateItem, #3648), or the whole restore is
// refused naming the account and nothing changes.
func TestImportVault_RefusesARowOutsideTheValidationBounds(t *testing.T) {
	for _, tc := range []struct{ name, tamper string }{
		{"kdf algorithm and cost out of bounds", `UPDATE vault_keys SET kdf_params = '{"alg":"x","opsLimit":4294967295,"memLimit":4398046511104}'`},
		{"kdf cost under the floor", `UPDATE vault_keys SET kdf_params = '{"alg":"argon2id13","opsLimit":1,"memLimit":8192}'`},
		{"kdf params not JSON", `UPDATE vault_keys SET kdf_params = 'nope'`},
		{"1-byte password salt", `UPDATE vault_keys SET salt_pw = x'01'`},
		{"empty password wrap", `UPDATE vault_keys SET wrapped_by_password = x''`},
		{"oversized password wrap", `UPDATE vault_keys SET wrapped_by_password = zeroblob(513)`},
		{"phrase wrap without its salt", `UPDATE vault_keys SET wrapped_by_phrase = x'0102'`},
		{"empty item ciphertext", `UPDATE vault_items SET ciphertext = x''`},
		{"oversized item ciphertext", `UPDATE vault_items SET ciphertext = zeroblob(1048577)`},
		{"empty item nonce", `UPDATE vault_items SET nonce = x''`},
		{"oversized item nonce", `UPDATE vault_items SET nonce = zeroblob(65)`},
		{"format version 0", `UPDATE vault_items SET format_version = 0`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			source := dbtest.NewDB(t).Db
			addChatUsers(t, source, "alice", "bob")
			seedVault(t, source,
				vaultOwner{"alice", randomBytes(t, 32), []string{"a"}},
				vaultOwner{"bob", randomBytes(t, 32), []string{"b"}})
			dir := exportVault(t, source)

			backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(dir, backupVaultFilename)))
			if err != nil {
				t.Fatal(err)
			}
			chatExec(t, backupDB, tc.tamper+` WHERE user_id = (SELECT id FROM users WHERE username = 'bob')`)
			backupDB.Close()

			live := dbtest.NewDB(t).Db
			addChatUsers(t, live, "alice", "bob")
			_, err = ImportVault(context.Background(), live, dir)
			if !errors.Is(err, ErrVaultBackupInvalid) {
				t.Fatalf("ImportVault = %v, want ErrVaultBackupInvalid", err)
			}
			if !strings.HasSuffix(err.Error(), "(bob)") {
				t.Errorf("error %q does not name bob alone", err)
			}
			assertRows(t, live, `SELECT COUNT(*) FROM vault_keys`, "[0]")
			assertRows(t, live, `SELECT COUNT(*) FROM vault_items`, "[0]")
		})
	}
}

// The refusal for a drive with no backup file says so without the drive's
// mount path, which is the host's business, not the client's.
func TestImportVault_MissingFileHidesTheHostPath(t *testing.T) {
	live := dbtest.NewDB(t).Db
	dir := t.TempDir()
	_, err := ImportVault(context.Background(), live, dir)
	if !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("ImportVault = %v, want fs.ErrNotExist", err)
	}
	if strings.Contains(err.Error(), dir) {
		t.Errorf("error %q shows the host path %s", err, dir)
	}
}

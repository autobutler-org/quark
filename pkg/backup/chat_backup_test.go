package backup

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	_ "modernc.org/sqlite"
)

func chatExec(t *testing.T, d *sql.DB, query string, args ...any) {
	t.Helper()
	if _, err := d.Exec(query, args...); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
}

// addChatUsers creates the accounts in order, so the first gets id 1.
func addChatUsers(t *testing.T, d *sql.DB, usernames ...string) {
	t.Helper()
	for _, username := range usernames {
		chatExec(t, d, `INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES (?, 'x', 'x')`, username)
	}
}

func addChatKeys(t *testing.T, d *sql.DB, username, marker string) {
	t.Helper()
	chatExec(t, d, `
		INSERT INTO user_chat_keys (user_id, box_public_key, sign_public_key, wrapped_by_password, salt_pw, kdf_params)
		SELECT id, ?, ?, ?, ?, '{}' FROM users WHERE username = ?`,
		[]byte(marker+"-box"), []byte(marker+"-sign"), []byte(marker+"-wrapped"), []byte(marker+"-salt"), username)
}

// seedChat fills a fresh database with one of everything the chat tables
// hold. alice is 1, bob 2 and carol 3; general is channel 1 from the
// migration, plans is 2 and the DM between alice and bob is 3.
func seedChat(t *testing.T, d *sql.DB) {
	t.Helper()
	const at = "2026-01-02 03:04:05"

	addChatUsers(t, d, "alice", "bob", "carol")
	chatExec(t, d, `INSERT INTO groups (name) VALUES ('family')`)

	chatExec(t, d, `INSERT INTO chat_channels (id, server_id, name, topic, created_by, created_at) VALUES (2, 1, 'plans', 'the trip', 1, ?)`, at)
	chatExec(t, d, `INSERT INTO chat_channels (id, server_id, kind, created_by, created_at) VALUES (3, 1, 'dm', 2, ?)`, at)
	chatExec(t, d, `INSERT INTO chat_channel_members (channel_id, user_id, permissions) VALUES (2, 1, 127), (2, 3, 7), (3, 1, 7), (3, 2, 7)`)
	chatExec(t, d, `INSERT INTO chat_channel_members (channel_id, group_id, permissions) SELECT 2, id, 7 FROM groups WHERE name = 'family'`)

	addChatKeys(t, d, "alice", "alice")
	addChatKeys(t, d, "bob", "bob")
	addChatKeys(t, d, "carol", "carol")
	chatExec(t, d, `UPDATE user_chat_keys SET wrapped_by_phrase = ?, salt_rp = ? WHERE user_id = 1`, []byte("alice-phrase"), []byte("alice-rp"))

	chatExec(t, d, `INSERT INTO chat_channel_keys (channel_id, version, created_by, created_at) VALUES (1, 1, 1, ?), (2, 1, 1, ?), (2, 2, 2, ?), (3, 1, 2, ?)`, at, at, at, at)
	for _, g := range []struct{ version, user, by int }{{1, 1, 1}, {1, 2, 1}, {2, 3, 2}, {2, 1, 2}} {
		chatExec(t, d, `
			INSERT INTO chat_key_grants (channel_id, version, user_id, sealed_key, granted_by, granter_sign_key, signature, created_at)
			VALUES (2, ?, ?, ?, ?, ?, ?, ?)`,
			g.version, g.user, []byte(fmt.Sprintf("sealed-%d-%d", g.version, g.user)), g.by,
			[]byte("granter-key"), []byte(fmt.Sprintf("sig-%d-%d", g.version, g.user)), at)
	}

	chatExec(t, d, `
		INSERT INTO chat_channel_events (channel_id, kind, actor_id, payload, signature, signer_sign_key, created_at)
		VALUES (2, 'member_set', 1, '{"userId":3,"name":"carol","permissions":7}', ?, ?, ?),
		       (2, 'key_created', 2, '{"version":2}', NULL, NULL, ?)`,
		[]byte("event-sig"), []byte("alice-sign"), at, at)

	chatExec(t, d, `
		INSERT INTO chat_messages (channel_id, author_id, key_version, ciphertext, created_at, edited_at, deleted_at, nonce)
		VALUES (2, 1, 1, ?, ?, NULL, NULL, ?),
		       (2, 2, 2, ?, ?, ?, NULL, ?),
		       (2, 3, 2, NULL, ?, NULL, ?, ?),
		       (3, 2, 1, ?, ?, NULL, NULL, ?)`,
		[]byte("nonce-1|hello"), at, []byte("nonce-1"),
		[]byte("nonce-2|edited"), at, at, []byte("nonce-2"),
		at, at, []byte("nonce-3"),
		[]byte("nonce-4|dm"), at, []byte("nonce-4"))
	chatExec(t, d, `INSERT INTO chat_reactions (message_id, user_id, key_version, ciphertext, created_at) VALUES (1, 2, 1, ?, ?), (1, 3, 1, ?, ?)`,
		[]byte("react-bob"), at, []byte("react-carol"), at)
}

// dumpChat reads every row of every chat table, keyed by table.
func dumpChat(t *testing.T, d *sql.DB) map[string][]string {
	t.Helper()
	dump := make(map[string][]string)
	for _, table := range chatBackupTables {
		dump[table] = queryRows(t, d, "SELECT * FROM "+table+" ORDER BY 1, 2")
	}
	return dump
}

// queryRows renders each row of query as one string.
func queryRows(t *testing.T, d *sql.DB, query string) []string {
	t.Helper()
	rows, err := d.Query(query)
	if err != nil {
		t.Fatalf("%s: %v", query, err)
	}
	defer rows.Close()
	cols, err := rows.Columns()
	if err != nil {
		t.Fatal(err)
	}

	out := []string{}
	for rows.Next() {
		vals := make([]any, len(cols))
		targets := make([]any, len(cols))
		for i := range vals {
			targets[i] = &vals[i]
		}
		if err := rows.Scan(targets...); err != nil {
			t.Fatal(err)
		}
		parts := make([]string, len(vals))
		for i, val := range vals {
			switch v := val.(type) {
			case []byte:
				parts[i] = strconv.Quote(string(v))
			case string:
				parts[i] = strconv.Quote(v)
			default:
				parts[i] = fmt.Sprint(v)
			}
		}
		out = append(out, "["+strings.Join(parts, " ")+"]")
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

func assertRows(t *testing.T, d *sql.DB, query string, want ...string) {
	t.Helper()
	if want == nil {
		want = []string{}
	}
	if got := queryRows(t, d, query); !slices.Equal(got, want) {
		t.Errorf("%s\n got %v\nwant %v", query, got, want)
	}
}

func exportChat(t *testing.T, d *sql.DB) string {
	t.Helper()
	dir := t.TempDir()
	if _, err := ExportChat(context.Background(), d, dir); err != nil {
		t.Fatalf("ExportChat: %v", err)
	}
	return dir
}

// The issue's acceptance test: create channels and messages, back up, wipe,
// restore, and the same ciphertext and grants come back.
func TestChatBackup_RoundTrip(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)
	seedChat(t, database.Db)
	want := dumpChat(t, database.Db)

	dir := exportChat(t, database.Db)
	backupPath := filepath.Join(dir, backupChatFilename)
	sumBefore, err := BackupVaultChecksum(backupPath)
	if err != nil {
		t.Fatal(err)
	}

	// Wipe, then stand the Quark back up the way a restore finds it: the same
	// accounts, and the keys and grant a client made for general at sign-in.
	if err := db.ResetDatabase(database); err != nil {
		t.Fatal(err)
	}
	addChatUsers(t, database.Db, "alice", "bob", "carol")
	chatExec(t, database.Db, `INSERT INTO groups (name) VALUES ('family')`)
	addChatKeys(t, database.Db, "alice", "fresh")
	chatExec(t, database.Db, `INSERT INTO chat_channel_keys (channel_id, version, created_by) VALUES (1, 1, 1)`)
	chatExec(t, database.Db, `
		INSERT INTO chat_key_grants (channel_id, version, user_id, sealed_key, granted_by, granter_sign_key, signature)
		VALUES (1, 1, 1, 'fresh', 1, 'fresh', 'fresh')`)

	result, err := ImportChat(ctx, database.Db, dir)
	if err != nil {
		t.Fatalf("ImportChat: %v", err)
	}
	if result.Channels != 3 || result.Messages != 4 || len(result.UnmatchedUsers) != 0 {
		t.Errorf("result = %+v, want 3 channels, 4 messages, nobody unmatched", result)
	}

	got := dumpChat(t, database.Db)
	for _, table := range chatBackupTables {
		if len(want[table]) == 0 {
			t.Errorf("%s: the seed left it empty, so the round trip proves nothing about it", table)
		}
		if !slices.Equal(got[table], want[table]) {
			t.Errorf("%s after restore\n got %v\nwant %v", table, got[table], want[table])
		}
	}

	sumAfter, err := BackupVaultChecksum(backupPath)
	if err != nil {
		t.Fatal(err)
	}
	if sumAfter != sumBefore {
		t.Error("the restore changed the backup file")
	}
}

// Accounts come back under whatever ids the new install gave them, or not at
// all. Here carol moved from 3 to 2, bob and the family group are gone, and
// dave is new.
func TestImportChat_FollowsAccountsByName(t *testing.T) {
	source := dbtest.NewDB(t)
	seedChat(t, source.Db)
	dir := exportChat(t, source.Db)

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice", "carol", "dave")
	addChatKeys(t, live, "carol", "fresh")
	addChatKeys(t, live, "dave", "dave")

	result, err := ImportChat(context.Background(), live, dir)
	if err != nil {
		t.Fatalf("ImportChat: %v", err)
	}
	if !slices.Equal(result.UnmatchedUsers, []string{"bob"}) {
		t.Errorf("UnmatchedUsers = %v, want [bob]", result.UnmatchedUsers)
	}

	// bob created the DM; SET NULL.
	assertRows(t, live, `SELECT id, created_by FROM chat_channels ORDER BY id`,
		"[1 <nil>]", "[2 1]", "[3 <nil>]")
	// Memberships follow the username; bob's and the family group's cascade.
	assertRows(t, live, `
		SELECT m.channel_id, COALESCE(u.username, g.name) FROM chat_channel_members m
		LEFT JOIN users u ON u.id = m.user_id LEFT JOIN groups g ON g.id = m.group_id
		ORDER BY 1, 2`,
		`[1 "everyone"]`, `[2 "alice"]`, `[2 "carol"]`, `[3 "alice"]`)
	// carol's backed-up identity replaces the one her new sign-in made, under
	// her new id; dave, whom the backup never knew, keeps his.
	assertRows(t, live, `
		SELECT u.username, CAST(k.box_public_key AS TEXT) FROM user_chat_keys k JOIN users u ON u.id = k.user_id
		ORDER BY 1`,
		`["alice" "alice-box"]`, `["carol" "carol-box"]`, `["dave" "dave-box"]`)
	assertRows(t, live, `SELECT channel_id, version, created_by FROM chat_channel_keys ORDER BY 1, 2`,
		"[1 1 1]", "[2 1 1]", "[2 2 <nil>]", "[3 1 <nil>]")
	// carol's grant is signed over account id 3 and she is 2 now: dropped.
	// bob's stays with no recipient, which is the rotate signal.
	assertRows(t, live, `SELECT version, user_id, granted_by, CAST(sealed_key AS TEXT) FROM chat_key_grants ORDER BY id`,
		`[1 1 1 "sealed-1-1"]`, `[1 <nil> 1 "sealed-1-2"]`, `[2 1 <nil> "sealed-2-1"]`)
	assertRows(t, live, `SELECT kind, actor_id FROM chat_channel_events ORDER BY id`,
		`["member_set" 1]`, `["key_created" <nil>]`)
	// Every message survives; only who wrote it is lost with the account.
	assertRows(t, live, `SELECT id, author_id, CAST(nonce AS TEXT) FROM chat_messages ORDER BY id`,
		`[1 1 "nonce-1"]`, `[2 <nil> "nonce-2"]`, `[3 2 "nonce-3"]`, `[4 <nil> "nonce-4"]`)
	assertRows(t, live, `SELECT user_id, CAST(ciphertext AS TEXT) FROM chat_reactions`,
		`[2 "react-carol"]`)
}

func TestImportChat_RefusesChatWithData(t *testing.T) {
	source := dbtest.NewDB(t)
	seedChat(t, source.Db)
	dir := exportChat(t, source.Db)

	cases := map[string]func(t *testing.T, live *sql.DB){
		"a message": func(t *testing.T, live *sql.DB) {
			chatExec(t, live, `INSERT INTO chat_channel_keys (channel_id, version) VALUES (1, 1)`)
			chatExec(t, live, `INSERT INTO chat_messages (channel_id, key_version, ciphertext, nonce) VALUES (1, 1, 'c', 'n')`)
		},
		"a channel someone made": func(t *testing.T, live *sql.DB) {
			chatExec(t, live, `INSERT INTO chat_channels (server_id, name) VALUES (1, 'mine')`)
		},
	}
	for name, occupy := range cases {
		t.Run(name, func(t *testing.T) {
			live := dbtest.NewDB(t).Db
			addChatUsers(t, live, "alice", "bob", "carol")
			occupy(t, live)
			before := dumpChat(t, live)

			_, err := ImportChat(context.Background(), live, dir)
			if !errors.Is(err, ErrChatNotEmpty) {
				t.Fatalf("ImportChat = %v, want ErrChatNotEmpty", err)
			}
			if after := dumpChat(t, live); !reflect.DeepEqual(after, before) {
				t.Errorf("a refused restore changed the live chat\n got %v\nwant %v", after, before)
			}
		})
	}
}

func TestImportChat_MissingFile(t *testing.T) {
	live := dbtest.NewDB(t).Db
	dir := t.TempDir()

	if _, err := ImportChat(context.Background(), live, dir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("ImportChat = %v, want a not-exist error", err)
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 0 {
		t.Errorf("a failed restore left %v behind", entries)
	}
}

func TestImportChat_RefusesUnknownVersion(t *testing.T) {
	source := dbtest.NewDB(t)
	seedChat(t, source.Db)
	dir := exportChat(t, source.Db)

	backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(dir, backupChatFilename)))
	if err != nil {
		t.Fatal(err)
	}
	chatExec(t, backupDB, fmt.Sprintf(`PRAGMA user_version = %d`, db.ChatBackupVersion+1))
	backupDB.Close()

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice", "bob", "carol")
	before := dumpChat(t, live)

	if _, err := ImportChat(context.Background(), live, dir); !errors.Is(err, ErrChatBackupVersion) {
		t.Fatalf("ImportChat = %v, want ErrChatBackupVersion", err)
	}
	if after := dumpChat(t, live); !reflect.DeepEqual(after, before) {
		t.Errorf("a refused restore changed the live chat\n got %v\nwant %v", after, before)
	}
}

// A file that is not a chat backup at all is an error, not a wiped chat.
func TestImportChat_RejectsGarbageFile(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, backupChatFilename), []byte("this is not a database, just some bytes"), 0644); err != nil {
		t.Fatal(err)
	}
	live := dbtest.NewDB(t).Db
	before := dumpChat(t, live)

	if _, err := ImportChat(context.Background(), live, dir); err == nil {
		t.Fatal("ImportChat accepted a file that is not a database")
	}
	if after := dumpChat(t, live); !reflect.DeepEqual(after, before) {
		t.Errorf("a failed restore changed the live chat\n got %v\nwant %v", after, before)
	}
}

// ExportChat copies with SELECT *, and ImportChat names the live columns, so
// both are wrong the day a migration changes a chat table and the backup
// schema does not follow.
func TestChatBackupSchema_MatchesLiveTables(t *testing.T) {
	live := dbtest.NewDB(t).Db
	backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(t.TempDir(), "schema.db")))
	if err != nil {
		t.Fatal(err)
	}
	defer backupDB.Close()
	if err := db.InitChatBackupSchema(backupDB); err != nil {
		t.Fatalf("InitChatBackupSchema: %v", err)
	}

	for _, table := range chatBackupTables {
		query := "SELECT cid, name FROM pragma_table_info('" + table + "') ORDER BY cid"
		want := queryRows(t, live, query)
		if len(want) == 0 {
			t.Errorf("%s is not a live table", table)
		}
		if got := queryRows(t, backupDB, query); !slices.Equal(got, want) {
			t.Errorf("%s columns: backup schema has %v, the migrations have %v;"+
				" update ChatBackupSchemaDDL, ChatBackupVersion and chatRestoreSteps", table, got, want)
		}
	}

	// Every live chat table is one the backup knows about, but for read
	// markers, which a backup leaves out (see chatBackupTables).
	assertRows(t, live, `
		SELECT COUNT(*) FROM sqlite_master
		WHERE type = 'table' AND name <> 'chat_read_markers'
		  AND (name LIKE 'chat\_%' ESCAPE '\' OR name = 'user_chat_keys')`,
		fmt.Sprintf("[%d]", len(chatBackupTables)))
}

func TestExportChat_ReplacesThePreviousBackup(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)
	seedChat(t, database.Db)
	dir := exportChat(t, database.Db)
	backupPath := filepath.Join(dir, backupChatFilename)

	chatExec(t, database.Db, `INSERT INTO chat_messages (channel_id, author_id, key_version, ciphertext, nonce) VALUES (2, 1, 1, 'later', 'nonce-5')`)
	if _, err := ExportChat(ctx, database.Db, dir); err != nil {
		t.Fatalf("second ExportChat: %v", err)
	}

	backupDB, err := sql.Open("sqlite", db.DSN(backupPath))
	if err != nil {
		t.Fatal(err)
	}
	defer backupDB.Close()
	assertRows(t, backupDB, `SELECT COUNT(*) FROM chat_messages`, "[5]")
	// The directory holds names and nothing a login could use.
	assertRows(t, backupDB, `SELECT name FROM pragma_table_info('users') ORDER BY cid`, `["id"]`, `["username"]`)
	assertRows(t, backupDB, `SELECT id, username FROM users ORDER BY id`, `[1 "alice"]`, `[2 "bob"]`, `[3 "carol"]`)

	if entries, _ := os.ReadDir(dir); len(entries) != 1 {
		t.Errorf("export left more than the backup behind: %v", entries)
	}
}

func TestExportChat_FailureKeepsThePreviousBackup(t *testing.T) {
	database := dbtest.NewDB(t)
	seedChat(t, database.Db)
	dir := exportChat(t, database.Db)
	backupPath := filepath.Join(dir, backupChatFilename)
	want, err := BackupVaultChecksum(backupPath)
	if err != nil {
		t.Fatal(err)
	}

	// The last table copied, so the failure lands with the file half written.
	restore := dbtest.HideTable(t, database.Db, "chat_reactions")
	_, err = ExportChat(context.Background(), database.Db, dir)
	restore()
	if err == nil {
		t.Fatal("ExportChat succeeded without chat_reactions")
	}

	got, err := BackupVaultChecksum(backupPath)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Error("a failed export changed the previous backup")
	}
	if _, err := os.Stat(filepath.Join(dir, storageutil.WriteTempPrefix+backupChatFilename)); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("a failed export left its temp file behind: %v", err)
	}
}

// ATTACH belongs to a connection. One that went back to the pool still
// attached would hold the backup file open and show it to the next request.
func TestChatBackup_LeavesNoAttachedConnectionInThePool(t *testing.T) {
	ctx := context.Background()
	database := dbtest.NewDB(t)
	seedChat(t, database.Db)
	dir := exportChat(t, database.Db)

	if _, err := ImportChat(ctx, database.Db, dir); !errors.Is(err, ErrChatNotEmpty) {
		t.Fatalf("ImportChat = %v, want ErrChatNotEmpty", err)
	}
	if err := db.ResetDatabase(database); err != nil {
		t.Fatal(err)
	}
	if _, err := ImportChat(ctx, database.Db, dir); err != nil {
		t.Fatalf("ImportChat: %v", err)
	}

	// Hold every pooled connection at once, so each is looked at.
	open := database.Db.Stats().OpenConnections
	for range open {
		conn, err := database.Db.Conn(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		var attached int
		if err := conn.QueryRowContext(ctx, `SELECT COUNT(*) FROM pragma_database_list WHERE name = 'chat_backup'`).Scan(&attached); err != nil {
			t.Fatal(err)
		}
		if attached != 0 {
			t.Error("a pooled connection still has the chat backup attached")
		}
	}
}

func TestSnapshotBackup_ExportsChat(t *testing.T) {
	database := dbtest.NewDB(t)
	seedChat(t, database.Db)
	src := makeSource(t, "Drive A", "SERIAL-A", map[string]string{"a.txt": "a"})
	target := makeTarget(t)
	store := NewInMemoryBackupJobStore()
	job := newJob("TARGET")
	store.Create(context.Background(), job)

	err := SnapshotBackup(context.Background(), SnapshotBackupParams{
		TargetDeviceSerial: "TARGET",
		Job:                job,
		Store:              store,
		ChatDB:             database.Db,
	}, []SourceDevice{src}, target.VFS)
	if err != nil {
		t.Fatalf("SnapshotBackup: %v", err)
	}

	manifest, err := ReadManifest(context.Background(), target)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := manifest.Files[backupChatFilename]; !ok {
		t.Errorf("the manifest does not cover %s: %v", backupChatFilename, manifest.Files)
	}

	// What the snapshot wrote is what a restore reads.
	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice", "bob", "carol")
	result, err := ImportChat(context.Background(), live, target.FilesDir)
	if err != nil {
		t.Fatalf("ImportChat: %v", err)
	}
	if result.Messages != 4 {
		t.Errorf("restored %d messages from the snapshot, want 4", result.Messages)
	}
}

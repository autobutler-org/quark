package v0_storage_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// chatQuark is vaultQuark's Quark, with alice and bob, holding a chat: a
// plans channel both are members of, each one's chat keys, a channel key
// granted to both, and a message from each.
func chatQuark(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	database := vaultQuark(t, map[string]bool{"alice": false, "bob": false})
	exec(t, database, `INSERT INTO chat_channels (server_id, name, topic, created_by)
		SELECT 1, 'plans', 'the trip', id FROM users WHERE username = 'alice'`)
	for _, user := range []string{"alice", "bob"} {
		exec(t, database, `INSERT INTO chat_channel_members (channel_id, user_id, permissions)
			SELECT c.id, u.id, 127 FROM chat_channels AS c, users AS u WHERE c.name = 'plans' AND u.username = ?`, user)
		exec(t, database, `INSERT INTO user_chat_keys (user_id, box_public_key, sign_public_key, wrapped_by_password, salt_pw, kdf_params)
			SELECT id, ?, ?, ?, ?, '{}' FROM users WHERE username = ?`,
			[]byte(user+"-box"), []byte(user+"-sign"), []byte(user+"-wrapped"), []byte(user+"-salt"), user)
	}
	exec(t, database, `INSERT INTO chat_channel_keys (channel_id, version, created_by)
		SELECT c.id, 1, u.id FROM chat_channels AS c, users AS u WHERE c.name = 'plans' AND u.username = 'alice'`)
	for _, user := range []string{"alice", "bob"} {
		exec(t, database, `INSERT INTO chat_key_grants (channel_id, version, user_id, sealed_key, granted_by, granter_sign_key, signature)
			SELECT c.id, 1, u.id, ?, g.id, 'alice-sign', ? FROM chat_channels AS c, users AS u, users AS g
			WHERE c.name = 'plans' AND u.username = ? AND g.username = 'alice'`,
			[]byte("sealed-for-"+user), []byte("sig-for-"+user), user)
		exec(t, database, `INSERT INTO chat_messages (channel_id, author_id, key_version, ciphertext, nonce)
			SELECT c.id, u.id, 1, ?, ? FROM chat_channels AS c, users AS u WHERE c.name = 'plans' AND u.username = ?`,
			[]byte("ciphertext-from-"+user), []byte("nonce-"+user), user)
	}
	return database
}

// dumpChatState is every channel, member, chat key, channel key, grant and
// message in database, one string per row.
func dumpChatState(t *testing.T, database *db.DatabaseSqlc) []string {
	t.Helper()
	var out []string
	for _, query := range []string{
		`SELECT id, name, topic, created_by FROM chat_channels ORDER BY id`,
		`SELECT channel_id, user_id, group_id, permissions FROM chat_channel_members ORDER BY id`,
		`SELECT user_id, box_public_key, sign_public_key, wrapped_by_password, salt_pw FROM user_chat_keys ORDER BY user_id`,
		`SELECT channel_id, version, created_by FROM chat_channel_keys ORDER BY 1, 2`,
		`SELECT channel_id, version, user_id, sealed_key, granted_by, granter_sign_key, signature FROM chat_key_grants ORDER BY id`,
		`SELECT id, channel_id, author_id, key_version, ciphertext, nonce FROM chat_messages ORDER BY id`,
	} {
		rows, err := database.Db.Query(query)
		if err != nil {
			t.Fatalf("%s: %v", query, err)
		}
		cols, _ := rows.Columns()
		for rows.Next() {
			vals := make([]any, len(cols))
			targets := make([]any, len(cols))
			for i := range vals {
				targets[i] = &vals[i]
			}
			if err := rows.Scan(targets...); err != nil {
				t.Fatal(err)
			}
			for i, v := range vals {
				if b, ok := v.([]byte); ok {
					vals[i] = string(b)
				}
			}
			out = append(out, fmt.Sprint(vals...))
		}
		if err := rows.Close(); err != nil {
			t.Fatal(err)
		}
	}
	return out
}

// snapshot writes a snapshot of source onto the drive at driveDir, binding
// its chat and vault backups to source, as a scheduled backup does.
func snapshot(t *testing.T, source *db.DatabaseSqlc, driveDir string) {
	t.Helper()
	target, err := vfs.NewLocalVFS(driveDir, vfs.FilesNamespace(backupSerial))
	if err != nil {
		t.Fatal(err)
	}
	if err := backup.SnapshotBackup(context.Background(), backup.SnapshotBackupParams{
		TargetDeviceSerial: backupSerial,
		Job:                &backup.BackupJob{ID: "chat"},
		LiveDB:             source.Db,
		Queries:            source.Queries,
	}, nil, target); err != nil {
		t.Fatal(err)
	}
}

// restoreChatBody restores the chat from the request body as the admin.
func restoreChatBody(engine restoreEngine, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/storage/devices/snapshot-backup/restore-chat",
		strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	engine.ServeHTTP(w, req)
	return w
}

// restoreChat restores the chat from serial's drive as the admin, re-confirmed.
func restoreChat(engine restoreEngine, serial string) *httptest.ResponseRecorder {
	return restoreChatBody(engine, `{"deviceSerial":"`+serial+`","password":"`+dbtest.AuthKey(adminPassword)+`"}`)
}

// channelsHeard drains the channel ids chat_channel_changed has been
// published for so far.
func channelsHeard(engine restoreEngine) []int64 {
	var out []int64
	for {
		select {
		case evt := <-engine.events:
			if data, ok := evt.Data.(eventbus.ChatChannelChanged); ok && evt.Kind == eventbus.EventChatChannelChanged {
				out = append(out, data.ChannelID)
			}
		default:
			return out
		}
	}
}

// wipeChat empties the chat the way a new install's database finds it, and
// takes every account's chat keys with it.
func wipeChat(t *testing.T, database *db.DatabaseSqlc) {
	t.Helper()
	exec(t, database, `DELETE FROM chat_servers`)
	exec(t, database, `DELETE FROM user_chat_keys`)
	exec(t, database, `INSERT INTO chat_servers (id, name) VALUES (1, 'Quark')`)
	exec(t, database, `INSERT INTO chat_channels (server_id, name, is_default) VALUES (1, 'general', 1)`)
}

// The issue's acceptance test (#2428): create channels and messages, back up,
// wipe the chat, restore through the route, and the same ciphertext and
// grants come back.
func TestRestoreSnapshotChat_RoundTrip(t *testing.T) {
	driveDir := t.TempDir()
	live := chatQuark(t)
	want := dumpChatState(t, live)
	snapshot(t, live, driveDir)
	wipeChat(t, live)
	if got := dumpChatState(t, live); slices.Equal(got, want) {
		t.Fatal("the wipe left the chat as it was, so the restore proves nothing")
	}

	engine := newRestoreEngine(t, live, driveDir)
	w := restoreChat(engine, backupSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("restore = %d %s, want 200", w.Code, w.Body.String())
	}
	var result backup.ChatImportResult
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Channels != 2 || result.Messages != 2 || len(result.UnmatchedUsers) != 0 || result.Run == "" {
		t.Errorf("result = %+v, want 2 channels, 2 messages, nobody unmatched, and the run", result)
	}
	if got := dumpChatState(t, live); !slices.Equal(got, want) {
		t.Errorf("chat after restore\n got %q\nwant %q", got, want)
	}

	// Every open client is told to reload each restored channel.
	var ids []int64
	rows, err := live.Db.Query(`SELECT id FROM chat_channels ORDER BY id`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
	}
	rows.Close()
	if heard := channelsHeard(engine); !slices.Equal(heard, ids) {
		t.Errorf("chat_channel_changed went out for %v, want every channel %v", heard, ids)
	}

	// A second restore finds the chat full, and changes nothing.
	again := newRestoreEngine(t, live, driveDir)
	if w := restoreChat(again, backupSerial); w.Code != http.StatusConflict {
		t.Errorf("second restore = %d %s, want 409", w.Code, w.Body.String())
	}
	if got := dumpChatState(t, live); !slices.Equal(got, want) {
		t.Errorf("a refused restore changed the chat\n got %q\nwant %q", got, want)
	}
	if heard := channelsHeard(again); len(heard) != 0 {
		t.Errorf("a refused restore published chat_channel_changed for %v", heard)
	}
}

func TestRestoreSnapshotChat_Refusals(t *testing.T) {
	driveDir := t.TempDir()
	source := chatQuark(t)
	snapshot(t, source, driveDir)
	noRun := t.TempDir()
	body := func(serial, password string) string {
		return `{"deviceSerial":"` + serial + `","password":"` + password + `"}`
	}
	for _, tc := range []struct {
		name, dir, body string
		// setup, when set, changes live before the restore.
		setup    func(t *testing.T, live *db.DatabaseSqlc)
		want     int
		wantBody string
	}{
		{name: "another Quark's snapshot", dir: driveDir, body: body(backupSerial, dbtest.AuthKey(adminPassword)),
			want: http.StatusBadRequest, wantBody: "did not write"},
		{name: "drive not attached", dir: driveDir, body: body("GONE", dbtest.AuthKey(adminPassword)),
			want: http.StatusNotFound},
		{name: "drive holds no run", dir: noRun, body: body(backupSerial, dbtest.AuthKey(adminPassword)),
			want: http.StatusNotFound, wantBody: "holds no snapshot"},
		{name: "drive without the snapshot-backup role", dir: driveDir, body: body(backupSerial, dbtest.AuthKey(adminPassword)),
			want: http.StatusBadRequest, wantBody: "snapshot-backup role",
			setup: func(t *testing.T, live *db.DatabaseSqlc) {
				exec(t, live, `UPDATE device_roles SET role = 'unassigned' WHERE device_serial = ?`, backupSerial)
			}},
		{name: "wrong password", dir: driveDir, body: body(backupSerial, dbtest.AuthKey("not-the-password")),
			want: http.StatusForbidden},
		{name: "raw password", dir: driveDir, body: body(backupSerial, adminPassword),
			want: http.StatusUpgradeRequired},
		{name: "body over 1 KiB", dir: driveDir, body: body(backupSerial, strings.Repeat("a", 2<<10)),
			want: http.StatusRequestEntityTooLarge},
	} {
		t.Run(tc.name, func(t *testing.T) {
			// A Quark of its own, so its secret is not the snapshot's.
			live := vaultQuark(t, map[string]bool{"alice": false, "bob": false})
			if tc.setup != nil {
				tc.setup(t, live)
			}
			before := dumpChatState(t, live)
			engine := newRestoreEngine(t, live, tc.dir)
			w := restoreChatBody(engine, tc.body)
			if w.Code != tc.want || !strings.Contains(w.Body.String(), tc.wantBody) {
				t.Errorf("restore = %d %s, want %d naming %q", w.Code, w.Body.String(), tc.want, tc.wantBody)
			}
			if strings.Contains(w.Body.String(), tc.dir) {
				t.Errorf("restore answer %s shows the drive's host path %s", w.Body.String(), tc.dir)
			}
			if after := dumpChatState(t, live); !slices.Equal(after, before) {
				t.Errorf("a refused restore changed the chat\n got %q\nwant %q", after, before)
			}
			if heard := channelsHeard(engine); len(heard) != 0 {
				t.Errorf("a refused restore published chat_channel_changed for %v", heard)
			}
		})
	}
}

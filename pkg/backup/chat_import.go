package backup

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
)

// The reasons [ImportChat] turns a restore down that the caller can explain to
// whoever asked for it. Anything else it returns is a fault.
var (
	// ErrChatNotEmpty reports a live chat that already holds a message or a
	// channel someone made. A restore replaces the chat; it never merges.
	ErrChatNotEmpty = errors.New("chat already has channels or messages")
	// ErrChatBackupVersion reports a backup file in a format this build does
	// not read.
	ErrChatBackupVersion = errors.New("chat backup was written by a different version of Quark")
)

// ImportChat restores the chat_backup.db that [ExportChat] wrote to backupDir
// into liveDB, in one transaction: a refused or failed restore changes nothing.
//
// It restores only into an empty chat, one with no message and no channel but
// the general a fresh install seeds, and answers [ErrChatNotEmpty] otherwise.
// What an empty chat does hold (the seeded server and channel, keys and grants
// clients made at sign-in) is replaced by the backup, ids and all: message ids
// page, and a ciphertext is bound to its channel id and key version.
//
// The backup does not carry accounts, so every account a chat row names is
// looked up by username (a group by name) on this Quark. An account that is
// not here is treated as the live schema treats a deleted one: the row keeps a
// NULL where the foreign key says SET NULL, and is skipped where it says
// CASCADE. Their usernames come back in the result.
func ImportChat(ctx context.Context, liveDB *sql.DB, backupDir string) (ChatImportResult, error) {
	dbPath, err := filepath.Abs(filepath.Join(backupDir, backupChatFilename))
	if err != nil {
		return ChatImportResult{}, err
	}
	// ATTACH would otherwise answer a missing file with a less helpful error.
	if _, err := os.Stat(dbPath); err != nil {
		return ChatImportResult{}, fmt.Errorf("chat_backup.db not found on device: %w", err)
	}

	// Read-only, so a restore can never change the file the manifest hashed.
	backupURI := url.URL{Scheme: "file", Path: dbPath, RawQuery: "mode=ro"}
	conn, err := attachChatBackup(ctx, liveDB, backupURI.String())
	if err != nil {
		return ChatImportResult{}, err
	}
	// Also what rolls the transaction below back on every early return.
	defer discardChatConn(conn)

	var version int
	if err := conn.QueryRowContext(ctx, `PRAGMA chat_backup.user_version`).Scan(&version); err != nil {
		return ChatImportResult{}, fmt.Errorf("read chat backup version: %w", err)
	}
	if version != db.ChatBackupVersion {
		return ChatImportResult{}, fmt.Errorf("%w: the file is format %d, this Quark reads format %d",
			ErrChatBackupVersion, version, db.ChatBackupVersion)
	}

	// IMMEDIATE takes the write lock before the emptiness check, so nobody
	// posts a message between the check and the delete that follows it.
	// database/sql can only begin a deferred transaction, hence the Exec.
	if _, err := conn.ExecContext(ctx, `BEGIN IMMEDIATE`); err != nil {
		return ChatImportResult{}, fmt.Errorf("begin chat restore: %w", err)
	}

	var occupied bool
	err = conn.QueryRowContext(ctx, `
		SELECT EXISTS (SELECT 1 FROM main.chat_messages)
		    OR EXISTS (SELECT 1 FROM main.chat_channels WHERE is_default = 0)`).Scan(&occupied)
	if err != nil {
		return ChatImportResult{}, fmt.Errorf("check live chat: %w", err)
	}
	if occupied {
		return ChatImportResult{}, ErrChatNotEmpty
	}

	var result ChatImportResult
	for _, step := range chatRestoreSteps {
		res, err := conn.ExecContext(ctx, step.statement)
		if err != nil {
			return ChatImportResult{}, fmt.Errorf("restore chat (%s): %w", step.name, err)
		}
		// modernc's RowsAffected never fails.
		rows, _ := res.RowsAffected()
		switch step.name {
		case "chat_channels":
			result.Channels = int(rows)
		case "chat_messages":
			result.Messages = int(rows)
		}
	}

	result.UnmatchedUsers, err = unmatchedChatUsers(ctx, conn)
	if err != nil {
		return ChatImportResult{}, err
	}

	if _, err := conn.ExecContext(ctx, `COMMIT`); err != nil {
		return ChatImportResult{}, fmt.Errorf("commit chat restore: %w", err)
	}
	return result, nil
}

// chatRestoreSteps is the restore, in the order the live foreign keys need.
//
// Raw SQL rather than sqlc, under the same exception as vault_export.go: each
// statement reads an attached database outside the migration set, which sqlc
// has no schema for and cannot type-check, and it keeps the rows inside SQLite
// instead of on the Go heap (see copyChatTables).
//
// u, and its like, is the backup account's row in the map from backup ids to
// live ids. A LEFT JOIN leaves live_id NULL for an account that is not here,
// which is what an ON DELETE SET NULL column wants; an inner JOIN drops the
// row, which is what ON DELETE CASCADE would have done.
var chatRestoreSteps = []struct{ name, statement string }{
	{"map users", `
		CREATE TEMP TABLE chat_restore_users AS
		SELECT b.id AS backup_id, l.id AS live_id
		FROM chat_backup.users AS b JOIN main.users AS l ON l.username = b.username`},
	{"map groups", `
		CREATE TEMP TABLE chat_restore_groups AS
		SELECT b.id AS backup_id, l.id AS live_id
		FROM chat_backup.groups AS b JOIN main.groups AS l ON l.name = b.name`},

	// Cascades through everything a fresh install seeded and every key or
	// grant a client made for general before the restore.
	{"clear seeded chat", `DELETE FROM main.chat_servers`},

	{"chat_servers", `INSERT INTO main.chat_servers SELECT * FROM chat_backup.chat_servers`},
	{"chat_channels", `
		INSERT INTO main.chat_channels (id, server_id, kind, name, topic, is_default, created_by, created_at)
		SELECT c.id, c.server_id, c.kind, c.name, c.topic, c.is_default, u.live_id, c.created_at
		FROM chat_backup.chat_channels AS c
		LEFT JOIN temp.chat_restore_users AS u ON u.backup_id = c.created_by`},
	// A member row names an account or a group, never both, so a row whose
	// one principal is not here has neither and is left out.
	{"chat_channel_members", `
		INSERT INTO main.chat_channel_members (id, channel_id, user_id, group_id, permissions)
		SELECT m.id, m.channel_id, u.live_id, g.live_id, m.permissions
		FROM chat_backup.chat_channel_members AS m
		LEFT JOIN temp.chat_restore_users AS u ON u.backup_id = m.user_id
		LEFT JOIN temp.chat_restore_groups AS g ON g.backup_id = m.group_id
		WHERE u.live_id IS NOT NULL OR g.live_id IS NOT NULL`},
	// OR REPLACE: an account that signed in to the new install already made
	// itself a key pair, and every grant in the backup is sealed to the old
	// one. An account the backup does not know keeps the keys it has.
	{"user_chat_keys", `
		INSERT OR REPLACE INTO main.user_chat_keys (user_id, box_public_key, sign_public_key,
			wrapped_by_password, salt_pw, wrapped_by_phrase, salt_rp, kdf_params, created_at, updated_at)
		SELECT u.live_id, k.box_public_key, k.sign_public_key,
			k.wrapped_by_password, k.salt_pw, k.wrapped_by_phrase, k.salt_rp, k.kdf_params, k.created_at, k.updated_at
		FROM chat_backup.user_chat_keys AS k
		JOIN temp.chat_restore_users AS u ON u.backup_id = k.user_id`},
	{"chat_channel_keys", `
		INSERT INTO main.chat_channel_keys (channel_id, version, created_by, created_at)
		SELECT k.channel_id, k.version, u.live_id, k.created_at
		FROM chat_backup.chat_channel_keys AS k
		LEFT JOIN temp.chat_restore_users AS u ON u.backup_id = k.created_by`},
	// A grant's signature covers its recipient's account id
	// (chatutil.GrantMessage), so a grant cannot follow an account to a new
	// id: it would never verify again, and it would hold the one slot a valid
	// grant for that member and version could take. It is left out, and the
	// member is handed the key again like any member who lacks it. A grant
	// whose recipient is not here at all keeps a NULL user_id, which is how
	// the Quark already knows a key is held by a stranger and must rotate.
	{"chat_key_grants", `
		INSERT INTO main.chat_key_grants (id, channel_id, version, user_id, sealed_key,
			granted_by, granter_sign_key, signature, created_at)
		SELECT g.id, g.channel_id, g.version, r.live_id, g.sealed_key,
			b.live_id, g.granter_sign_key, g.signature, g.created_at
		FROM chat_backup.chat_key_grants AS g
		LEFT JOIN temp.chat_restore_users AS r ON r.backup_id = g.user_id
		LEFT JOIN temp.chat_restore_users AS b ON b.backup_id = g.granted_by
		WHERE r.live_id IS NULL OR r.live_id = g.user_id`},
	// payload is signed byte for byte, so the ids inside it stay the
	// backup's; it carries the name beside them.
	{"chat_channel_events", `
		INSERT INTO main.chat_channel_events (id, channel_id, kind, actor_id, payload,
			signature, signer_sign_key, created_at)
		SELECT e.id, e.channel_id, e.kind, u.live_id, e.payload,
			e.signature, e.signer_sign_key, e.created_at
		FROM chat_backup.chat_channel_events AS e
		LEFT JOIN temp.chat_restore_users AS u ON u.backup_id = e.actor_id`},
	{"chat_messages", `
		INSERT INTO main.chat_messages (id, channel_id, author_id, key_version, ciphertext,
			created_at, edited_at, deleted_at, nonce)
		SELECT m.id, m.channel_id, u.live_id, m.key_version, m.ciphertext,
			m.created_at, m.edited_at, m.deleted_at, m.nonce
		FROM chat_backup.chat_messages AS m
		LEFT JOIN temp.chat_restore_users AS u ON u.backup_id = m.author_id`},
	{"chat_reactions", `
		INSERT INTO main.chat_reactions (id, message_id, user_id, key_version, ciphertext, created_at)
		SELECT r.id, r.message_id, u.live_id, r.key_version, r.ciphertext, r.created_at
		FROM chat_backup.chat_reactions AS r
		JOIN temp.chat_restore_users AS u ON u.backup_id = r.user_id`},
}

// unmatchedChatUsers lists the backup's accounts that have no account of the
// same username on this Quark. A handful of names, so reading them is fine.
func unmatchedChatUsers(ctx context.Context, conn *sql.Conn) ([]string, error) {
	rows, err := conn.QueryContext(ctx, `
		SELECT username FROM chat_backup.users
		WHERE id NOT IN (SELECT backup_id FROM temp.chat_restore_users)
		ORDER BY username`)
	if err != nil {
		return nil, fmt.Errorf("list unmatched chat accounts: %w", err)
	}
	defer rows.Close()

	var usernames []string
	for rows.Next() {
		var username string
		if err := rows.Scan(&username); err != nil {
			return nil, fmt.Errorf("scan unmatched chat account: %w", err)
		}
		usernames = append(usernames, username)
	}
	return usernames, rows.Err()
}

package backup

import (
	"context"
	"database/sql"
	"errors"
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
	// ErrChatRestoreRoleRequired reports a drive that does not have the
	// snapshot-backup role. Chat is only restored from the drive the
	// snapshots write to.
	ErrChatRestoreRoleRequired = errors.New("chat is restored only from a drive with the snapshot-backup role")
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
//
// Like [ExportChat] it attaches the file to the live connection, and returns
// [ErrDatabaseBackedUpSeparately] on a PostgreSQL-backed Quark: a SQLite
// install's backup restores onto SQLite only.
func ImportChat(ctx context.Context, liveDB *sql.DB, backupDir string) (ChatImportResult, error) {
	rows, unmatched, _, err := chatBackup.restore(ctx, liveDB, backupDir)
	if err != nil {
		return ChatImportResult{}, err
	}
	return ChatImportResult{
		Channels:       int(rows["chat_channels"]),
		Messages:       int(rows["chat_messages"]),
		UnmatchedUsers: unmatched,
	}, nil
}

// RestoreChat restores, as [ImportChat] does, the chat backup a snapshot
// wrote to the drive params.DeviceSerial names, from the run params.Run names
// or the newest complete one (#2428). The drive, the run and the file are
// checked as [RestoreVault] checks them, except that a drive without the
// snapshot-backup role is [ErrChatRestoreRoleRequired].
func RestoreChat(params RestoreChatParams) (ChatImportResult, error) {
	run, dir, err := chatBackup.fromDrive(params)
	if err != nil {
		return ChatImportResult{}, err
	}
	result, err := ImportChat(params.Ctx, params.LiveDB, dir)
	if err != nil {
		return ChatImportResult{}, err
	}
	result.Run = run.Folder
	return result, nil
}

// chatRestoreSteps is the restore, in the order the live foreign keys need.
//
// Raw SQL rather than sqlc, for the reason [ciphertextBackup.copyTables]
// gives: each statement reads an attached database outside the migration set,
// and keeps the rows inside SQLite instead of on the Go heap.
//
// u, and its like, is the backup account's row in the map from backup ids to
// live ids. A LEFT JOIN leaves live_id NULL for an account that is not here,
// which is what an ON DELETE SET NULL column wants; an inner JOIN drops the
// row, which is what ON DELETE CASCADE would have done.
var chatRestoreSteps = []restoreStep{
	{"map groups", `
		CREATE TEMP TABLE restore_groups AS
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
		LEFT JOIN temp.restore_users AS u ON u.backup_id = c.created_by`},
	// A member row names an account or a group, never both, so a row whose
	// one principal is not here has neither and is left out.
	{"chat_channel_members", `
		INSERT INTO main.chat_channel_members (id, channel_id, user_id, group_id, permissions)
		SELECT m.id, m.channel_id, u.live_id, g.live_id, m.permissions
		FROM chat_backup.chat_channel_members AS m
		LEFT JOIN temp.restore_users AS u ON u.backup_id = m.user_id
		LEFT JOIN temp.restore_groups AS g ON g.backup_id = m.group_id
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
		JOIN temp.restore_users AS u ON u.backup_id = k.user_id`},
	{"chat_channel_keys", `
		INSERT INTO main.chat_channel_keys (channel_id, version, created_by, created_at)
		SELECT k.channel_id, k.version, u.live_id, k.created_at
		FROM chat_backup.chat_channel_keys AS k
		LEFT JOIN temp.restore_users AS u ON u.backup_id = k.created_by`},
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
		LEFT JOIN temp.restore_users AS r ON r.backup_id = g.user_id
		LEFT JOIN temp.restore_users AS b ON b.backup_id = g.granted_by
		WHERE r.live_id IS NULL OR r.live_id = g.user_id`},
	// payload is signed byte for byte, so the ids inside it stay the
	// backup's; it carries the name beside them.
	{"chat_channel_events", `
		INSERT INTO main.chat_channel_events (id, channel_id, kind, actor_id, payload,
			signature, signer_sign_key, created_at)
		SELECT e.id, e.channel_id, e.kind, u.live_id, e.payload,
			e.signature, e.signer_sign_key, e.created_at
		FROM chat_backup.chat_channel_events AS e
		LEFT JOIN temp.restore_users AS u ON u.backup_id = e.actor_id`},
	// client_message_id only answers a retry of a send still in flight
	// (#3531), so it stays behind, and a file from before it restores too.
	{"chat_messages", `
		INSERT INTO main.chat_messages (id, channel_id, author_id, key_version, ciphertext,
			created_at, edited_at, deleted_at, nonce)
		SELECT m.id, m.channel_id, u.live_id, m.key_version, m.ciphertext,
			m.created_at, m.edited_at, m.deleted_at, m.nonce
		FROM chat_backup.chat_messages AS m
		LEFT JOIN temp.restore_users AS u ON u.backup_id = m.author_id`},
	{"chat_reactions", `
		INSERT INTO main.chat_reactions (id, message_id, user_id, key_version, ciphertext, created_at)
		SELECT r.id, r.message_id, u.live_id, r.key_version, r.ciphertext, r.created_at
		FROM chat_backup.chat_reactions AS r
		JOIN temp.restore_users AS u ON u.backup_id = r.user_id`},
	{"chat_polls", `INSERT INTO main.chat_polls SELECT * FROM chat_backup.chat_polls`},
	{"chat_poll_answers", `
		INSERT INTO main.chat_poll_answers (id, message_id, user_id, key_version, ciphertext, created_at, updated_at)
		SELECT a.id, a.message_id, u.live_id, a.key_version, a.ciphertext, a.created_at, a.updated_at
		FROM chat_backup.chat_poll_answers AS a
		JOIN temp.restore_users AS u ON u.backup_id = a.user_id`},
	// Channel and message ids come back unchanged, the same as chat_messages.
	// An uploader who is not on this Quark is left out, the same as a reaction.
	{"chat_attachments", `
		INSERT INTO main.chat_attachments (id, channel_id, message_id, uploader_id, byte_size, created_at)
		SELECT a.id, a.channel_id, a.message_id, u.live_id, a.byte_size, a.created_at
		FROM chat_backup.chat_attachments AS a
		JOIN temp.restore_users AS u ON u.backup_id = a.uploader_id`},
}

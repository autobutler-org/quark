package backup

import (
	"context"
	"database/sql"

	"github.com/autobutler-org/quark/internal/db"
)

const backupChatFilename = "chat_backup.db"

// chatBackupTables is every chat table, parents before children: the order a
// restore has to load them in for the live foreign keys to hold.
// chat_read_markers (#2424) is left out on purpose: it is only how far each
// account has read, so a restored Quark starts with everything unread.
var chatBackupTables = []string{
	"chat_servers",
	"chat_channels",
	"chat_channel_members",
	"user_chat_keys",
	"chat_channel_keys",
	"chat_key_grants",
	"chat_channel_events",
	"chat_messages",
	"chat_reactions",
}

// chatBackup is the chat's ciphertext backup, chat_backup.db.
var chatBackup = ciphertextBackup{
	filename:   backupChatFilename,
	feature:    "Chat backup",
	ddl:        db.ChatBackupSchemaDDL,
	version:    db.ChatBackupVersion,
	errVersion: ErrChatBackupVersion,
	directory: []string{
		`INSERT INTO chat_backup.users (id, username) SELECT id, username FROM main.users`,
		`INSERT INTO chat_backup.groups (id, name) SELECT id, name FROM main.groups`,
	},
	tables: chatBackupTables,
	occupied: `
		SELECT EXISTS (SELECT 1 FROM main.chat_messages)
		    OR EXISTS (SELECT 1 FROM main.chat_channels WHERE is_default = 0)`,
	errOccupied: ErrChatNotEmpty,
	steps:       chatRestoreSteps,
}

// ExportChat writes the chat tables of liveDB to chat_backup.db in targetDir
// and returns its path (#2428). It asks for no password: message bodies,
// reactions and channel keys are ciphertext the Quark cannot open, and the
// rest is public keys, so the copy is as private as the database it came from.
//
// A failed export leaves the previous backup whole, and a PostgreSQL-backed
// Quark gets [ErrDatabaseBackedUpSeparately] and nothing written.
func ExportChat(ctx context.Context, liveDB *sql.DB, targetDir string) (string, error) {
	return chatBackup.export(ctx, liveDB, targetDir)
}

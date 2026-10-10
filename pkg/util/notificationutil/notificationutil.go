// Package notificationutil works out which notifications an account has. The
// list is derived on demand from the Quark's state and is not stored: a
// notification exists for as long as its condition holds and is gone once it
// does not. Each account turns types off in its own settings
// (usersettingsutil.Settings.DisabledNotifications).
package notificationutil

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/backup"
)

// Type names a kind of notification. It is what the API sends and what an
// account's settings list to turn one off.
type Type string

const (
	// TypeBackupDue means this Quark has no completed snapshot backup on
	// record.
	TypeBackupDue Type = "backup_due"
	// TypeBackupStale means the last completed snapshot backup is at least
	// BackupStaleAfter old.
	TypeBackupStale Type = "backup_stale"
)

// BackupStaleAfter is how old the last snapshot backup gets before it is
// stale. Provisional: the trigger policy is still to be settled with product
// (#2493).
const BackupStaleAfter = 30 * 24 * time.Hour

// BackupLink is the app route a backup notification opens: the System page's
// Storage tab, where a snapshot backup is started.
const BackupLink = "/system/storage"

// Types returns every notification type.
func Types() []Type {
	return []Type{TypeBackupDue, TypeBackupStale}
}

// Valid reports whether t is a type this Quark knows.
func (t Type) Valid() bool {
	return slices.Contains(Types(), t)
}

// Notification is one thing to tell an account. It carries no title or body:
// the client owns the copy and writes it from Type.
type Notification struct {
	Type Type `json:"type"`
	// Link is the app route to open when the notification is tapped.
	Link string `json:"link"`
	// LastBackupAt is when the last snapshot backup completed. Only
	// TypeBackupStale carries it.
	LastBackupAt *time.Time `json:"lastBackupAt,omitempty"`
}

// ListParams describes the account to list notifications for.
type ListParams struct {
	// Queries is the database the last snapshot backup is recorded in.
	Queries *db.Queries
	// IsAdmin is whether the account is an admin.
	IsAdmin bool
	// Disabled is the types the account turned off.
	Disabled []Type
	// Now is the time to judge staleness against.
	Now time.Time
}

// ListResult is an account's current notifications.
type ListResult struct {
	// Notifications is never nil, so an account with none reads [].
	Notifications []Notification `json:"notifications"`
}

// List returns an account's current notifications.
//
// The backup types go to admins only, since only an admin can start a backup.
// An admin gets TypeBackupDue while no snapshot backup is on record and
// TypeBackupStale once the last one is BackupStaleAfter old. Because the list
// is derived, there is at most one backup notification however often it is
// asked for, and it clears itself when a snapshot backup completes. That is
// all the coalescing and rate limiting these types need.
func List(ctx context.Context, params ListParams) (ListResult, error) {
	result := ListResult{Notifications: []Notification{}}
	if !params.IsAdmin {
		return result, nil
	}
	last, err := backup.LastSnapshot(ctx, params.Queries)
	if err != nil {
		return ListResult{}, fmt.Errorf("list notifications: %w", err)
	}
	backupNotification := Notification{Type: TypeBackupDue, Link: BackupLink}
	if !last.IsZero() {
		if params.Now.Sub(last) < BackupStaleAfter {
			return result, nil
		}
		backupNotification.Type = TypeBackupStale
		backupNotification.LastBackupAt = &last
	}
	if !slices.Contains(params.Disabled, backupNotification.Type) {
		result.Notifications = append(result.Notifications, backupNotification)
	}
	return result, nil
}

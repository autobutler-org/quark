package notificationutil_test

import (
	"context"
	"encoding/json"
	"path"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// backedUp gives the drive serial the snapshot-backup role and one complete
// run, completed at, scans it into the drive's run cache as an attached
// drive's scan does, and returns the drive.
func backedUp(t *testing.T, queries db.Querier, serial string, at time.Time) vfs.VFS {
	t.Helper()
	ctx := context.Background()
	if err := queries.UpsertDeviceRole(ctx, db.UpsertDeviceRoleParams{DeviceSerial: serial, Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	drive := vfs.NewMemVFS(vfs.FilesNamespace(serial))
	dir := path.Join(backup.BackupsDir, "2026-10-01 09.00")
	if err := drive.MkdirAll(ctx, dir); err != nil {
		t.Fatal(err)
	}
	manifest := &backup.Manifest{CompletedAt: at, Drives: []backup.ManifestDrive{{Folder: "Built-in storage", Name: "Pi"}}}
	if err := backup.WriteManifest(ctx, manifest, drive, dir); err != nil {
		t.Fatal(err)
	}
	if _, err := backup.RefreshRunCache(ctx, queries, serial, drive); err != nil {
		t.Fatal(err)
	}
	return drive
}

func list(t *testing.T, queries db.Querier, now time.Time) []notificationutil.Notification {
	t.Helper()
	result, err := notificationutil.List(context.Background(), notificationutil.ListParams{Queries: queries, IsAdmin: true, Now: now})
	if err != nil {
		t.Fatal(err)
	}
	return result.Notifications
}

// Deleting a drive's last run brings the reminder back: the runs are the
// record, and no run is no backup.
func TestList_DueAgainAfterTheLastRunIsDeleted(t *testing.T) {
	ctx := context.Background()
	now := time.Now()
	queries := dbtest.NewDB(t).Queries
	drive := backedUp(t, queries, "BK", now.Add(-time.Hour))
	if got := list(t, queries, now); len(got) != 0 {
		t.Fatalf("notifications with a fresh run = %+v, want none", got)
	}
	reg := vfs.NewRegistry()
	if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace("BK")}, drive); err != nil {
		t.Fatal(err)
	}
	if _, err := backup.DeleteRun(backup.DeleteRunParams{Ctx: ctx, Queries: queries, Registry: reg, DeviceSerial: "BK", Run: "2026-10-01 09.00"}); err != nil {
		t.Fatal(err)
	}
	if got := list(t, queries, now); len(got) != 1 || got[0].Type != notificationutil.TypeBackupDue {
		t.Fatalf("notifications after the last run was deleted = %+v, want backup_due", got)
	}
}

// The last backup is the newest run on any backup drive, attached or not: a
// drive's run cache answers while it is away. A drive that has lost the
// backup role no longer counts.
func TestList_NewestRunAcrossDrives(t *testing.T) {
	now := time.Now()
	queries := dbtest.NewDB(t).Queries
	older := now.Add(-3 * notificationutil.BackupStaleAfter)
	newer := now.Add(-2 * notificationutil.BackupStaleAfter)
	backedUp(t, queries, "", older)
	backedUp(t, queries, "AWAY", newer)
	got := list(t, queries, now)
	if len(got) != 1 || got[0].Type != notificationutil.TypeBackupStale || got[0].LastBackupAt == nil || !got[0].LastBackupAt.Equal(newer) {
		t.Fatalf("notifications = %+v, want backup_stale at the away drive's run, %v", got, newer)
	}

	backedUp(t, queries, "FRESH", now.Add(-time.Hour))
	if got := list(t, queries, now); len(got) != 0 {
		t.Fatalf("notifications with a fresh run on another drive = %+v, want none", got)
	}
	if err := queries.UpsertDeviceRole(context.Background(), db.UpsertDeviceRoleParams{DeviceSerial: "FRESH", Role: "default-storage"}); err != nil {
		t.Fatal(err)
	}
	if got := list(t, queries, now); len(got) != 1 || got[0].Type != notificationutil.TypeBackupStale {
		t.Fatalf("notifications once the fresh drive is no backup drive = %+v, want backup_stale", got)
	}
}

func TestList_BackupNotifications(t *testing.T) {
	now := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	never := time.Time{}
	fresh := now.Add(-notificationutil.BackupStaleAfter + time.Second)
	atThreshold := now.Add(-notificationutil.BackupStaleAfter)
	stale := now.Add(-2 * notificationutil.BackupStaleAfter)

	tests := []struct {
		name       string
		isAdmin    bool
		lastBackup time.Time
		disabled   []notificationutil.Type
		want       notificationutil.Type // empty means no notification
	}{
		{name: "non-admin never backed up", lastBackup: never},
		{name: "non-admin with a stale backup", lastBackup: stale},
		{name: "never backed up", isAdmin: true, lastBackup: never, want: notificationutil.TypeBackupDue},
		{name: "fresh backup", isAdmin: true, lastBackup: fresh},
		{name: "exactly at the threshold", isAdmin: true, lastBackup: atThreshold, want: notificationutil.TypeBackupStale},
		{name: "stale backup", isAdmin: true, lastBackup: stale, want: notificationutil.TypeBackupStale},
		{
			name: "due turned off", isAdmin: true, lastBackup: never,
			disabled: []notificationutil.Type{notificationutil.TypeBackupDue},
		},
		{
			name: "stale turned off", isAdmin: true, lastBackup: stale,
			disabled: []notificationutil.Type{notificationutil.TypeBackupStale},
		},
		{
			name: "due turned off does not hide stale", isAdmin: true, lastBackup: stale,
			disabled: []notificationutil.Type{notificationutil.TypeBackupDue},
			want:     notificationutil.TypeBackupStale,
		},
		{
			name: "stale turned off does not hide due", isAdmin: true, lastBackup: never,
			disabled: []notificationutil.Type{notificationutil.TypeBackupStale},
			want:     notificationutil.TypeBackupDue,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			queries := dbtest.NewDB(t).Queries
			if !tt.lastBackup.IsZero() {
				backedUp(t, queries, "BK", tt.lastBackup)
			}
			result, err := notificationutil.List(ctx, notificationutil.ListParams{
				Queries: queries, IsAdmin: tt.isAdmin, Disabled: tt.disabled, Now: now,
			})
			if err != nil {
				t.Fatal(err)
			}
			got := result.Notifications
			if got == nil {
				t.Fatal("Notifications is nil; it must encode as []")
			}
			if tt.want == "" {
				if len(got) != 0 {
					t.Fatalf("Notifications = %+v, want none", got)
				}
				return
			}
			if len(got) != 1 || got[0].Type != tt.want || got[0].Link != notificationutil.BackupLink {
				t.Fatalf("Notifications = %+v, want one %s linking to %s", got, tt.want, notificationutil.BackupLink)
			}
			if tt.want == notificationutil.TypeBackupStale {
				if got[0].LastBackupAt == nil || !got[0].LastBackupAt.Equal(tt.lastBackup) {
					t.Errorf("LastBackupAt = %v, want %v", got[0].LastBackupAt, tt.lastBackup)
				}
			} else if got[0].LastBackupAt != nil {
				t.Errorf("LastBackupAt = %v on %s, want none", got[0].LastBackupAt, tt.want)
			}
		})
	}
}

func TestList_NoNotificationsEncodesAsEmptyArray(t *testing.T) {
	result, err := notificationutil.List(context.Background(), notificationutil.ListParams{Queries: dbtest.NewDB(t).Queries, Now: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != `{"notifications":[]}` {
		t.Errorf("encoded = %s, want an empty array", data)
	}
}

func TestType_Valid(t *testing.T) {
	for _, typ := range notificationutil.Types() {
		if !typ.Valid() {
			t.Errorf("%q is listed by Types but not Valid", typ)
		}
	}
	for _, typ := range []notificationutil.Type{"", "backup_complete", "BACKUP_DUE"} {
		if typ.Valid() {
			t.Errorf("%q is Valid, want not", typ)
		}
	}
}
